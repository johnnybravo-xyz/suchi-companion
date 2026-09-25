import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';
import 'package:suchi_mobile/auth/pairing_link.dart';
import 'package:suchi_mobile/auth/session_controller.dart';

const _code =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _pairing = PairingLink.parse(
  'suchi://pair?v=1&server=https%3A%2F%2Fsuchi.example.com&code=$_code',
);

void main() {
  test('exchanges a code after handshake, verifies identity, then persists only the token', () async {
    final requests = <http.Request>[];
    final vault = _MemoryVault();
    final session = _session(vault, (request) async {
      requests.add(request);
      return switch (request.url.path) {
        '/api/handshake' => _fixture('handshake.json'),
        '/api/mobile/pairing/exchange' => _json({
          'token': _token,
          'name': 'Suchi mobile',
          'scopes': ['documents:read', 'documents:write'],
        }),
        '/api/whoami' => _fixture('whoami.json'),
        _ => http.Response('', 404),
      };
    });
    await session.pairWithLink(_pairing, deviceName: ' Ritesh’s iPhone ');
    expect(session.state, SessionState.signedIn);
    expect(requests.map((request) => request.url.path), [
      '/api/handshake',
      '/api/mobile/pairing/exchange',
      '/api/whoami',
    ]);
    expect(
      requests
          .take(2)
          .every((request) => !request.headers.containsKey('Authorization')),
      isTrue,
    );
    expect(requests.every((request) => !request.followRedirects), isTrue);
    expect(jsonDecode(requests[1].body), {
      'code': _code,
      'device_name': 'Ritesh’s iPhone',
    });
    expect(requests[1].method, 'POST');
    expect(requests.last.headers['Authorization'], 'Token $_token');
    expect(vault.saved?.token, _token);
  });

  test('QR pairing reprobes after manual origin verification', () async {
    var probes = 0;
    http.Request? exchange;
    final session = _session(_MemoryVault(), (request) async {
      if (request.url.path == '/api/handshake') {
        probes++;
        return _json({
          'product': 'suchi',
          'api_version': 1,
          'mobile_contracts': ['suchi-companion-v1'],
        });
      }
      if (request.url.path == '/api/mobile/pairing/exchange') {
        exchange = request;
        return _json({'token': _token});
      }
      return _fixture('whoami.json');
    });
    expect(
      await session.verifyServerAddress(_pairing.origin.toString()),
      isTrue,
    );
    await session.pairWithLink(_pairing, deviceName: 'Family Pixel');
    expect(session.state, SessionState.signedIn);
    expect(probes, 2);
    expect(jsonDecode(exchange!.body), {
      'code': _code,
      'device_name': 'Family Pixel',
    });
  });

  for (final failure in [
    'handshake',
    'expired',
    'redirect',
    'malformed token',
    'scopes',
  ]) {
    test('$failure refuses pairing and never persists credentials', () async {
      final requests = <http.Request>[];
      final vault = _MemoryVault();
      final session = _session(vault, (request) async {
        requests.add(request);
        if (request.url.path == '/api/handshake') {
          return failure == 'handshake'
              ? _json({'product': 'other'}, status: 200)
              : _fixture('handshake.json');
        }
        if (request.url.path == '/api/mobile/pairing/exchange') {
          if (failure == 'expired') {
            return _json({
              'code': 'pairing_invalid',
              'message': 'Generate a new pairing code in the Suchi web app.',
            }, status: 400);
          }
          if (failure == 'redirect') {
            return http.Response(
              '',
              302,
              headers: {'location': 'https://other.example/exchange'},
            );
          }
          return _json({
            'token': failure == 'malformed token' ? 'bad' : _token,
          });
        }
        if (request.url.path == '/api/whoami') {
          final body = jsonDecode(
            File('test/fixtures/api/v1/whoami.json').readAsStringSync(),
          ) as Map<String, dynamic>;
          body['scopes'] = ['documents:read'];
          return _json(body);
        }
        return http.Response('', 404);
      });
      await session.pairWithLink(_pairing, deviceName: 'Test phone');
      expect(session.state, SessionState.signedOut);
      expect(vault.saved, isNull);
      expect(
        requests.where((request) => request.url.path == '/api/whoami').length,
        failure == 'scopes' ? 1 : 0,
      );
      if (failure == 'handshake') expect(requests, hasLength(1));
      if (failure == 'expired') {
        expect(session.errorMessage, contains('Generate a new pairing code'));
      }
    });
  }

  test(
    'late exchange cannot restore a signed-out account or write credentials',
    () async {
      final pending = Completer<http.Response>();
      final exchanging = Completer<void>();
      final requests = <http.Request>[];
      final vault = _MemoryVault();
      final session = _session(vault, (request) async {
        requests.add(request);
        if (request.url.path == '/api/handshake') {
          return _fixture('handshake.json');
        }
        exchanging.complete();
        return pending.future;
      });
      final pairing = session.pairWithLink(_pairing, deviceName: 'Test phone');
      await exchanging.future;
      await session.signOut();
      pending.complete(_json({'token': _token}));
      await pairing;
      expect(session.state, SessionState.signedOut);
      expect(vault.saved, isNull);
      expect(requests.map((request) => request.url.path), [
        '/api/handshake',
        '/api/mobile/pairing/exchange',
      ]);
    },
  );
}

SessionController _session(
  _MemoryVault vault,
  Future<http.Response> Function(http.Request) handler,
) {
  final transport = MockClient(handler);
  final session = SessionController(
    vault: vault,
    clientFactory: (origin, token) =>
        SuchiClient(origin: origin, token: token, httpClient: transport),
  );
  addTearDown(session.dispose);
  return session;
}

http.Response _fixture(String name) => http.Response(
  File('test/fixtures/api/v1/$name').readAsStringSync(),
  200,
  headers: {'content-type': 'application/json'},
);
http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

final class _MemoryVault implements CredentialVault {
  StoredCredentials? saved;
  @override
  Future<void> clear() async {
    saved = null;
  }

  @override
  Future<StoredCredentials?> read() async => saved;
  @override
  Future<void> save(StoredCredentials credentials) async {
    saved = credentials;
  }
}
