import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';
import 'package:suchi_mobile/auth/pair_screen.dart';
import 'package:suchi_mobile/auth/session_controller.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';

String _fixture(String name) =>
    File('test/fixtures/api/v1/$name').readAsStringSync();

void main() {
  testWidgets('does not render credential fields before a verified handshake', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final controller = SessionController(
      vault: _EmptyVault(),
      clientFactory: (origin, token) => SuchiClient(
        origin: origin,
        token: token,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            _fixture('handshake.json'),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: SuchiTheme.light,
        home: PairScreen(session: controller),
      ),
    );

    expect(find.byKey(const ValueKey('pair-email')), findsNothing);
    expect(find.byKey(const ValueKey('pair-token')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('pair-server')),
      'https://suchi.example.com',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('verify-server')));
    await tester.tap(find.byKey(const ValueKey('verify-server')));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/api/handshake');
    expect(requests.single.headers.containsKey('Authorization'), isFalse);
    expect(find.byKey(const ValueKey('pair-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('pair-password')), findsOneWidget);
  });

  testWidgets('rejects an HTTP DNS origin without making a request', (
    tester,
  ) async {
    var requestCount = 0;
    final controller = SessionController(
      vault: _EmptyVault(),
      clientFactory: (origin, token) => SuchiClient(
        origin: origin,
        token: token,
        httpClient: MockClient((request) async {
          requestCount++;
          return http.Response('', 500);
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: SuchiTheme.light,
        home: PairScreen(session: controller),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('pair-server')),
      'http://suchi.example.com',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('verify-server')));
    await tester.tap(find.byKey(const ValueKey('verify-server')));
    await tester.pumpAndSettle();

    expect(requestCount, 0);
    expect(find.textContaining('private literal IP'), findsOneWidget);
    expect(find.byKey(const ValueKey('pair-email')), findsNothing);
  });
}

final class _EmptyVault implements CredentialVault {
  @override
  Future<void> clear() async {}

  @override
  Future<StoredCredentials?> read() async => null;

  @override
  Future<void> save(StoredCredentials credentials) async {}
}
