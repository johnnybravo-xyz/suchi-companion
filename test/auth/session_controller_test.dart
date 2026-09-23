import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/api/api_error.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';
import 'package:suchi_mobile/auth/session_controller.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _origin = Uri.parse('https://suchi.example.com');

String _fixture(String name) =>
    File('test/fixtures/api/v1/$name').readAsStringSync();

void main() {
  test('pairing probes without credentials before sending the token', () async {
    final requests = <http.Request>[];
    final vault = _MemoryVault();
    final transport = MockClient((request) async {
      requests.add(request);
      return switch (request.url.path) {
        '/api/handshake' => http.Response(
          _fixture('handshake.json'),
          200,
          headers: {'content-type': 'application/json'},
        ),
        '/api/whoami' => http.Response(
          _fixture('whoami.json'),
          200,
          headers: {'content-type': 'application/json'},
        ),
        _ => http.Response('{}', 404),
      };
    });
    final controller = SessionController(
      vault: vault,
      clientFactory: (origin, token) =>
          SuchiClient(origin: origin, token: token, httpClient: transport),
    );

    await controller.pairWithToken(
      serverAddress: _origin.toString(),
      token: _token,
    );

    expect(controller.state, SessionState.signedIn);
    expect(controller.user?.email, 'reader@example.com');
    expect(vault.saved?.token, _token);
    expect(requests.map((request) => request.url.path), [
      '/api/handshake',
      '/api/whoami',
    ]);
    expect(requests.first.headers.containsKey('Authorization'), isFalse);
    expect(requests.last.headers['Authorization'], 'Token $_token');
  });

  test(
    'manual pairing reveals credentials only after one successful probe',
    () async {
      final requests = <http.Request>[];
      final vault = _MemoryVault();
      final transport = MockClient((request) async {
        requests.add(request);
        return http.Response(
          request.url.path == '/api/handshake'
              ? _fixture('handshake.json')
              : _fixture('whoami.json'),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final controller = SessionController(
        vault: vault,
        clientFactory: (origin, token) =>
            SuchiClient(origin: origin, token: token, httpClient: transport),
      );

      expect(await controller.verifyServerAddress(_origin.toString()), isTrue);
      expect(controller.preparedOrigin, _origin);
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/api/handshake');
      expect(requests.single.headers.containsKey('Authorization'), isFalse);

      await controller.pairWithToken(
        serverAddress: _origin.toString(),
        token: _token,
      );

      expect(controller.state, SessionState.signedIn);
      expect(requests.map((request) => request.url.path), [
        '/api/handshake',
        '/api/whoami',
      ]);
      expect(requests.last.headers['Authorization'], 'Token $_token');
    },
  );

  test('password pairing uses the sessionless token exchange', () async {
    final requests = <http.Request>[];
    final vault = _MemoryVault();
    final transport = MockClient((request) async {
      requests.add(request);
      return switch (request.url.path) {
        '/api/handshake' => http.Response(
          _fixture('handshake.json'),
          200,
          headers: {'content-type': 'application/json'},
        ),
        '/api/token/' => http.Response(
          jsonEncode({'token': _token}),
          200,
          headers: {'content-type': 'application/json'},
        ),
        '/api/whoami' => http.Response(
          _fixture('whoami.json'),
          200,
          headers: {'content-type': 'application/json'},
        ),
        _ => http.Response('{}', 404),
      };
    });
    final controller = SessionController(
      vault: vault,
      clientFactory: (origin, token) =>
          SuchiClient(origin: origin, token: token, httpClient: transport),
    );

    await controller.pairWithPassword(
      serverAddress: _origin.toString(),
      email: 'reader@example.com',
      password: 'correct horse battery staple',
    );

    expect(controller.state, SessionState.signedIn);
    expect(requests.map((request) => request.url.path), [
      '/api/handshake',
      '/api/token/',
      '/api/whoami',
    ]);
    expect(requests[1].headers.containsKey('Authorization'), isFalse);
    expect(jsonDecode(requests[1].body), {
      'email': 'reader@example.com',
      'password': 'correct horse battery staple',
    });
    expect(requests.last.headers['Authorization'], 'Token $_token');
    expect(vault.saved?.token, _token);
  });

  test('a token without both mobile scopes is not persisted', () async {
    final whoami = jsonDecode(_fixture('whoami.json')) as Map<String, dynamic>
      ..['scopes'] = ['documents:read'];
    final vault = _MemoryVault();
    final controller = SessionController(
      vault: vault,
      clientFactory: (origin, token) => SuchiClient(
        origin: origin,
        token: token,
        httpClient: MockClient(
          (request) async => http.Response(
            request.url.path == '/api/handshake'
                ? _fixture('handshake.json')
                : jsonEncode(whoami),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    await controller.pairWithToken(
      serverAddress: _origin.toString(),
      token: _token,
    );

    expect(controller.state, SessionState.signedOut);
    expect(controller.errorMessage, contains('documents:read'));
    expect(vault.saved, isNull);
  });

  test('a rejected saved credential becomes expired and is deleted', () async {
    final vault = _MemoryVault(
      initial: StoredCredentials(origin: _origin, token: _token),
    );
    final controller = SessionController(
      vault: vault,
      clientFactory: (origin, token) => SuchiClient(
        origin: origin,
        token: token,
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/handshake') {
            return http.Response(
              _fixture('handshake.json'),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{"code":"unauthorized","message":"unauthorized"}',
            401,
            headers: {
              'content-type': 'application/json',
              'x-request-id': 'expired-1',
            },
          );
        }),
      ),
    );

    await controller.initialize();

    expect(controller.state, SessionState.expired);
    expect(controller.requestId, 'expired-1');
    expect(vault.clearCount, 1);
    expect(controller.client, isNull);
  });

  test(
    'sign out pauses work, attempts logout, and clears local state',
    () async {
      final events = <String>[];
      final vault = _MemoryVault(onClear: () => events.add('clear'));
      final transport = MockClient((request) async {
        if (request.url.path == '/api/handshake') {
          return http.Response(
            _fixture('handshake.json'),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/whoami') {
          return http.Response(
            _fixture('whoami.json'),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        events.add('logout');
        return http.Response('', 503);
      });
      final controller = SessionController(
        vault: vault,
        onPauseUploads: () async => events.add('pause'),
        onClearMemoryCaches: () => events.add('cache'),
        clientFactory: (origin, token) =>
            SuchiClient(origin: origin, token: token, httpClient: transport),
      );
      await controller.pairWithToken(
        serverAddress: _origin.toString(),
        token: _token,
      );

      await controller.signOut();

      expect(events, ['pause', 'clear', 'logout', 'cache']);
      expect(controller.state, SessionState.signedOut);
      expect(controller.client, isNull);
    },
  );

  test('sign out stays active when secure credential deletion fails', () async {
    final events = <String>[];
    final vault = _MemoryVault(
      onClear: () => events.add('clear'),
      clearError: StateError('secure storage unavailable'),
    );
    var logoutRequests = 0;
    final controller = SessionController(
      vault: vault,
      onPauseUploads: () async => events.add('pause'),
      onResumeUploads: () async => events.add('resume'),
      clientFactory: (origin, token) => SuchiClient(
        origin: origin,
        token: token,
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/handshake') {
            return http.Response(
              _fixture('handshake.json'),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/whoami') {
            return http.Response(
              _fixture('whoami.json'),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          logoutRequests++;
          return http.Response('', 204);
        }),
      ),
    );
    await controller.pairWithToken(
      serverAddress: _origin.toString(),
      token: _token,
    );
    events.clear();

    final signedOut = await controller.signOut();

    expect(signedOut, isFalse);
    expect(events, ['pause', 'clear', 'resume']);
    expect(logoutRequests, 0);
    expect(controller.state, SessionState.signedIn);
    expect(controller.client, isNotNull);
    expect(vault.saved?.token, _token);
  });

  test(
    'failed local cleanup keeps sign-out retryable but expiry fails closed',
    () async {
      final vault = _MemoryVault();
      final controller = SessionController(
        vault: vault,
        onPauseUploads: () async =>
            throw const FileSystemException('cleanup failed'),
        clientFactory: (origin, token) => SuchiClient(
          origin: origin,
          token: token,
          httpClient: MockClient(
            (request) async => http.Response(
              _fixture(
                request.url.path == '/api/handshake'
                    ? 'handshake.json'
                    : 'whoami.json',
              ),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );
      await controller.pairWithToken(
        serverAddress: _origin.toString(),
        token: _token,
      );

      expect(await controller.signOut(), false);
      expect(controller.state, SessionState.signedIn);
      expect(controller.client, isNotNull);
      expect(vault.clearCount, 0);

      await controller.expire(
        const ApiException(
          kind: ApiFailureKind.unauthorized,
          message: 'Token revoked',
        ),
      );
      expect(controller.state, SessionState.expired);
      expect(controller.client, isNull);
      expect(vault.clearCount, 1);
    },
  );
}

final class _MemoryVault implements CredentialVault {
  _MemoryVault({this.initial, this.onClear, this.clearError});

  StoredCredentials? initial;
  StoredCredentials? saved;
  int clearCount = 0;
  final void Function()? onClear;
  final Object? clearError;

  @override
  Future<void> clear() async {
    clearCount++;
    onClear?.call();
    if (clearError case final error?) throw error;
    initial = null;
    saved = null;
  }

  @override
  Future<StoredCredentials?> read() async => initial;

  @override
  Future<void> save(StoredCredentials credentials) async {
    saved = credentials;
    initial = credentials;
  }
}
