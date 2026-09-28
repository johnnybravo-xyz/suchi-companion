import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_companion/api/suchi_client.dart';
import 'package:suchi_companion/api/api_models.dart';
import 'package:suchi_companion/api/api_error.dart';
import 'package:suchi_companion/auth/credential_vault.dart';
import 'package:suchi_companion/auth/session_controller.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _origin = Uri.parse('https://suchi.example.com');

String _fixture(String name) =>
    File('test/fixtures/api/v1/$name').readAsStringSync();

UserSelf _userSnapshot() =>
    UserSelf.fromJson(jsonDecode(_fixture('whoami.json')));

StoredCredentials _storedWithSnapshot() => StoredCredentials(
  origin: _origin,
  token: _token,
  userSnapshot: _userSnapshot(),
);

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
      allowDevelopmentHttp: false,
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
    expect(vault.saved?.userSnapshot?.email, 'reader@example.com');
    expect(requests.map((request) => request.url.path), [
      '/api/handshake',
      '/api/whoami',
    ]);
    expect(requests.first.headers.containsKey('Authorization'), isFalse);
    expect(requests.last.headers['Authorization'], 'Token $_token');
  });

  test(
    'explicitly unsupported mobile contract refuses before token use',
    () async {
      final requests = <http.Request>[];
      final vault = _MemoryVault();
      final controller = SessionController(
        vault: vault,
        clientFactory: (origin, token) => SuchiClient(
          origin: origin,
          token: token,
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.url.path != '/api/handshake') {
              throw StateError('Sent credentials to an incompatible server');
            }
            return http.Response(
              '{"product":"suchi","api_version":1,"mobile_contracts":[]}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      addTearDown(controller.dispose);

      await controller.pairWithToken(
        serverAddress: _origin.toString(),
        token: _token,
      );

      expect(controller.state, SessionState.signedOut);
      expect(controller.client, isNull);
      expect(vault.saved, isNull);
      expect(requests, hasLength(1));
      expect(requests.single.headers.containsKey('Authorization'), isFalse);
    },
  );

  test('manual pairing with an undeclared higher-version server sends credentials only after probing', () async {
    final requests = <http.Request>[];
    final vault = _MemoryVault();
    final transport = MockClient((request) async {
      requests.add(request);
      return http.Response(
        request.url.path == '/api/handshake'
            ? '{"product":"suchi","api_version":99,'
                  '"min_app_version":"99.0.0"}'
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
  });

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
    final vault = _MemoryVault(initial: _storedWithSnapshot());
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

  for (final failurePoint in ['handshake', 'whoami']) {
    test(
      'restored verified snapshot enters offline when $failurePoint is unreachable',
      () async {
        final requests = <http.Request>[];
        final pauses = <String>[];
        Future<http.Response> handle(http.Request request) async {
          requests.add(request);
          if (request.url.path == '/api/handshake') {
            if (failurePoint == 'handshake') {
              throw const SocketException('offline');
            }
            return http.Response(
              _fixture('handshake.json'),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          throw const SocketException('offline');
        }

        final vault = _MemoryVault(initial: _storedWithSnapshot());
        final controller = SessionController(
          vault: vault,
          onPauseUploads: () async => pauses.add('pause'),
          clientFactory: (origin, token) => SuchiClient(
            origin: origin,
            token: token,
            httpClient: MockClient(handle),
          ),
        );
        addTearDown(controller.dispose);

        await controller.initialize();

        expect(controller.state, SessionState.offline);
        expect(controller.client, isNull);
        expect(controller.user?.email, 'reader@example.com');
        expect(controller.identity?.userId, 7);
        expect(pauses, ['pause']);
        expect(vault.clearCount, 0);
        expect(
          requests.map((request) => request.url.path),
          failurePoint == 'handshake'
              ? ['/api/handshake']
              : ['/api/handshake', '/api/whoami'],
        );
        expect(requests.first.headers.containsKey('Authorization'), isFalse);
        if (failurePoint == 'whoami') {
          expect(requests.last.headers['Authorization'], 'Token $_token');
        }
      },
    );
  }

  test('offline retry probes anonymously before reusing the token', () async {
    var reachable = false;
    final requests = <http.Request>[];
    Future<http.Response> handle(http.Request request) async {
      requests.add(request);
      if (!reachable) throw const SocketException('offline');
      return http.Response(
        request.url.path == '/api/handshake'
            ? _fixture('handshake.json')
            : _fixture('whoami.json'),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    final vault = _MemoryVault(initial: _storedWithSnapshot());
    final controller = SessionController(
      vault: vault,
      clientFactory: (origin, token) => SuchiClient(
        origin: origin,
        token: token,
        httpClient: MockClient(handle),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.state, SessionState.offline);

    reachable = true;
    requests.clear();
    await controller.retryStoredCredentials();

    expect(controller.state, SessionState.signedIn);
    expect(requests.map((request) => request.url.path), [
      '/api/handshake',
      '/api/whoami',
    ]);
    expect(requests.first.headers.containsKey('Authorization'), isFalse);
    expect(requests.last.headers['Authorization'], 'Token $_token');
    expect(vault.saved?.userSnapshot?.userId, 7);
  });

  for (final failure in ['redirect', 'malformed']) {
    test(
      'verified snapshot does not enter offline after $failure handshake',
      () async {
        final controller = SessionController(
          vault: _MemoryVault(initial: _storedWithSnapshot()),
          clientFactory: (origin, token) => SuchiClient(
            origin: origin,
            token: token,
            httpClient: MockClient(
              (_) async => failure == 'redirect'
                  ? http.Response(
                      '',
                      302,
                      headers: {'location': 'https://other.example.com/'},
                    )
                  : http.Response(
                      'not-json',
                      200,
                      headers: {'content-type': 'application/json'},
                    ),
            ),
          ),
        );
        addTearDown(controller.dispose);

        await controller.initialize();

        expect(controller.state, SessionState.signedOut);
        expect(controller.client, isNull);
        expect(controller.user, isNull);
      },
    );
  }

  test(
    'legacy credential without a verified snapshot cannot enter offline',
    () async {
      final controller = SessionController(
        vault: _MemoryVault(
          initial: StoredCredentials(origin: _origin, token: _token),
        ),
        clientFactory: (origin, token) => SuchiClient(
          origin: origin,
          token: token,
          httpClient: MockClient(
            (_) async => throw const SocketException('offline'),
          ),
        ),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.state, SessionState.signedOut);
      expect(controller.identity, isNull);
    },
  );

  test(
    'restored HTTP token is retained for HTTPS repair without any request',
    () async {
      final stored = StoredCredentials(
        origin: Uri.parse('http://192.168.4.2:8000'),
        token: _token,
      );
      final vault = _MemoryVault(initial: stored);
      var clientCreations = 0;
      final controller = SessionController(
        vault: vault,
        allowDevelopmentHttp: false,
        clientFactory: (origin, token) {
          clientCreations++;
          throw StateError('No HTTP client may be created.');
        },
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(controller.state, SessionState.signedOut);
      expect(controller.errorMessage, contains('HTTPS'));
      expect(controller.canRetryStoredCredentials, isTrue);
      expect(vault.initial, same(stored));
      expect(vault.clearCount, 0);
      expect(clientCreations, 0);

      await controller.retryStoredCredentials();
      expect(controller.errorMessage, contains('HTTPS'));
      expect(clientCreations, 0);
      expect(
        await controller.verifyServerAddress(stored.origin.toString()),
        isFalse,
      );
      await controller.pairWithToken(
        serverAddress: stored.origin.toString(),
        token: _token,
      );
      expect(controller.errorMessage, contains('HTTPS'));
      expect(clientCreations, 0);
      expect(vault.clearCount, 0);
    },
  );

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
        onBeginOfflineSignOut: (identity) async =>
            events.add('quarantine:${identity.userId}'),
        onRollbackOfflineSignOut: (identity) async =>
            events.add('restore:${identity.userId}'),
        onFinishOfflineSignOut: (identity) async =>
            events.add('finish:${identity.userId}'),
        onClearMemoryCaches: () => events.add('cache'),
        clientFactory: (origin, token) =>
            SuchiClient(origin: origin, token: token, httpClient: transport),
      );
      await controller.pairWithToken(
        serverAddress: _origin.toString(),
        token: _token,
      );

      await controller.signOut();

      expect(events, [
        'pause',
        'quarantine:7',
        'clear',
        'finish:7',
        'logout',
        'cache',
      ]);
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
      onBeginOfflineSignOut: (identity) async =>
          events.add('quarantine:${identity.userId}'),
      onRollbackOfflineSignOut: (identity) async =>
          events.add('restore:${identity.userId}'),
      onFinishOfflineSignOut: (identity) async =>
          events.add('finish:${identity.userId}'),
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
    expect(events, ['pause', 'quarantine:7', 'clear', 'restore:7', 'resume']);
    expect(logoutRequests, 0);
    expect(controller.state, SessionState.signedIn);
    expect(controller.client, isNotNull);
    expect(vault.saved?.token, _token);
  });

  test(
    'failed offline-copy quarantine keeps the offline session active',
    () async {
      final events = <String>[];
      final vault = _MemoryVault(initial: _storedWithSnapshot());
      final controller = SessionController(
        vault: vault,
        onPauseUploads: () async => events.add('pause'),
        onResumeUploads: () async => events.add('resume'),
        onBeginOfflineSignOut: (identity) async {
          events.add('quarantine:${identity.userId}');
          throw const FileSystemException('offline quarantine failed');
        },
        clientFactory: (origin, token) => SuchiClient(
          origin: origin,
          token: token,
          httpClient: MockClient(
            (_) async => throw const SocketException('offline'),
          ),
        ),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.state, SessionState.offline);
      events.clear();

      expect(await controller.signOut(), isFalse);

      expect(controller.state, SessionState.offline);
      expect(controller.client, isNull);
      expect(controller.identity?.userId, 7);
      expect(vault.clearCount, 0);
      expect(events, ['pause', 'quarantine:7']);
    },
  );

  test(
    'restored credentials retry interrupted offline sign-out recovery',
    () async {
      final events = <String>[];
      final controller = SessionController(
        vault: _MemoryVault(initial: _storedWithSnapshot()),
        onPauseUploads: () async => events.add('pause'),
        onRollbackOfflineSignOut: (identity) async =>
            events.add('restore:${identity.userId}'),
        clientFactory: (origin, token) => SuchiClient(
          origin: origin,
          token: token,
          httpClient: MockClient(
            (_) async => throw const SocketException('offline'),
          ),
        ),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.state, SessionState.offline);
      expect(events, ['restore:7', 'pause']);
    },
  );

  test(
    'post-credential offline cleanup failure still completes sign-out',
    () async {
      final events = <String>[];
      final vault = _MemoryVault();
      final controller = SessionController(
        vault: vault,
        onPauseUploads: () async => events.add('pause'),
        onBeginOfflineSignOut: (identity) async =>
            events.add('quarantine:${identity.userId}'),
        onRollbackOfflineSignOut: (identity) async =>
            events.add('restore:${identity.userId}'),
        onFinishOfflineSignOut: (identity) async {
          events.add('finish:${identity.userId}');
          throw const FileSystemException('offline deletion failed');
        },
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
      events.clear();

      expect(await controller.signOut(), isTrue);

      expect(events, ['pause', 'quarantine:7', 'finish:7']);
      expect(controller.state, SessionState.signedOut);
      expect(controller.client, isNull);
      expect(vault.clearCount, 1);
    },
  );

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
