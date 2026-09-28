import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_companion/api/suchi_client.dart';
import 'package:suchi_companion/auth/credential_vault.dart';
import 'package:suchi_companion/auth/session_controller.dart';
import 'package:suchi_companion/theme/suchi_theme.dart';
import 'package:suchi_companion/trash/trash_screen.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _origin = 'https://suchi.example.com';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('${platform.name}: load, page, restore and refresh archive', (
      tester,
    ) async {
      final first = Completer<http.Response>();
      final pages = <String>[];
      var restores = 0;
      var archiveRefreshes = 0;
      final session = await _session((request) async {
        if (request.method == 'POST') {
          expect(request.url.path, '/api/documents/1/restore');
          restores++;
          return _json({'affected': 1});
        }
        expect(request.url.path, '/api/documents/');
        expect(request.url.queryParameters['trashed'], '1');
        expect(request.url.queryParameters['page_size'], '30');
        expect(request.url.queryParameters['ordering'], '-updated_at');
        pages.add(request.url.queryParameters['page']!);
        if (pages.length == 1) return first.future;
        return restores > 0 ? _page([2, 3]) : _page([3], count: 3);
      });
      await _pump(
        tester,
        session,
        platform,
        onRestored: () => archiveRefreshes++,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      first.complete(_page([1, 2], count: 3, hasMore: true));
      await tester.pumpAndSettle();
      expect(find.text('Document 1'), findsOneWidget);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Document 3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('restore-1')));
      await tester.pumpAndSettle();
      expect(archiveRefreshes, 1);
      expect(restores, 1);
      expect(pages, ['1', '2', '1']);
      expect(find.text('Document 1'), findsNothing);
      expect(find.text('Document 2'), findsOneWidget);
      expect(find.text('Document 3'), findsOneWidget);
      expect(find.text('Restored “Document 1”.'), findsOneWidget);
    });

    testWidgets('${platform.name}: retry initial and pagination failures', (
      tester,
    ) async {
      final pages = <String>[];
      final session = await _session((request) async {
        pages.add(request.url.queryParameters['page']!);
        if (pages.length == 1 || pages.length == 3) {
          return _failure(503, requestId: 'trash-request');
        }
        return pages.last == '1'
            ? _page([1], count: 2, hasMore: true)
            : _page([2], count: 2);
      });
      await _pump(tester, session, platform);
      await tester.pumpAndSettle();
      expect(find.text('Request trash-request'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Document 1'), findsOneWidget);
      expect(find.text('Request trash-request'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Document 2'), findsOneWidget);
      expect(pages, ['1', '1', '2', '2']);
    });

    for (final status in [403, 404]) {
      testWidgets(
        '${platform.name}: restore $status keeps the row and allows retry',
        (tester) async {
          var attempts = 0;
          var restored = 0;
          final session = await _session((request) async {
            if (request.method == 'POST') {
              attempts++;
              return attempts == 1 ? _failure(status) : _json({'affected': 1});
            }
            return _page(attempts < 2 ? [1] : []);
          });
          await _pump(tester, session, platform, onRestored: () => restored++);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('restore-1')));
          await tester.pumpAndSettle();
          expect(find.text('Document 1'), findsOneWidget);
          expect(restored, 0);
          expect(session.state, SessionState.signedIn);
          expect(
            find.text(
              status == 403
                  ? 'Your token does not permit this action.'
                  : 'This document is no longer available.',
            ),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('restore-1')));
          await tester.pumpAndSettle();
          expect(restored, 1);
          expect(find.text('Trash is empty'), findsOneWidget);
        },
      );
    }

    testWidgets('${platform.name}: an expired token clears loaded documents', (
      tester,
    ) async {
      final session = await _session(
        (request) async =>
            request.method == 'POST' ? _failure(401) : _page([1]),
      );
      await _pump(tester, session, platform);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('restore-1')));
      await tester.pumpAndSettle();
      expect(session.state, SessionState.expired);
      expect(find.text('Document 1'), findsNothing);
      expect(find.text('Account changed'), findsOneWidget);
    });

    testWidgets(
      '${platform.name}: a previous account response cannot refill Trash',
      (tester) async {
        final pending = Completer<http.Response>();
        final session = await _session((_) => pending.future);
        await _pump(tester, session, platform);
        await session.pairWithToken(serverAddress: _origin, token: _token);
        pending.complete(_page([1]));
        await tester.pumpAndSettle();
        expect(session.state, SessionState.signedIn);
        expect(find.text('Document 1'), findsNothing);
        expect(find.text('Account changed'), findsOneWidget);
      },
    );

    for (final status in [200, 401]) {
      testWidgets(
        '${platform.name}: old restore $status cannot affect a new session',
        (tester) async {
          final pending = Completer<http.Response>();
          var refreshes = 0;
          var restores = 0;
          final session = await _session((request) async {
            if (request.method == 'POST') {
              restores++;
              return pending.future;
            }
            return _page([1]);
          });
          await _pump(tester, session, platform, onRestored: () => refreshes++);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('restore-1')));
          await tester.pump();
          expect(find.text('Restoring…'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('restore-1')));
          await tester.pump();
          expect(restores, 1);
          await session.pairWithToken(serverAddress: _origin, token: _token);
          pending.complete(
            status == 200 ? _json({'affected': 1}) : _failure(status),
          );
          await tester.pumpAndSettle();
          expect(session.state, SessionState.signedIn);
          expect(refreshes, 0);
          expect(find.text('Restored “Document 1”.'), findsNothing);
          expect(find.text('Document 1'), findsNothing);
        },
      );
    }

    testWidgets(
      '${platform.name}: empty Trash refreshes and supports larger text',
      (tester) async {
        var requests = 0;
        final session = await _session((_) async {
          requests++;
          return _page(requests == 1 ? [] : [1]);
        });
        await _pump(tester, session, platform, textScale: 2);
        await tester.pumpAndSettle();
        expect(find.text('Trash is empty'), findsOneWidget);
        await tester.drag(find.byType(ListView), const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(requests, 2);
        expect(find.text('Document 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<SessionController> _session(
  Future<http.Response> Function(http.Request) handler,
) async {
  final session = SessionController(
    vault: _MemoryVault(),
    clientFactory: (origin, token) => SuchiClient(
      origin: origin,
      token: token,
      httpClient: MockClient((request) async {
        final fixture = switch (request.url.path) {
          '/api/handshake' => 'handshake.json',
          '/api/whoami' => 'whoami.json',
          _ => null,
        };
        if (fixture != null) {
          return http.Response(
            File('test/fixtures/api/v1/$fixture').readAsStringSync(),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return handler(request);
      }),
    ),
  );
  addTearDown(session.dispose);
  await session.pairWithToken(serverAddress: _origin, token: _token);
  return session;
}

Future<void> _pump(
  WidgetTester tester,
  SessionController session,
  TargetPlatform platform, {
  VoidCallback? onRestored,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: SuchiTheme.light.copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: TrashScreen(
        client: session.client!,
        session: session,
        onRestored: onRestored ?? () {},
      ),
    ),
  );
}

http.Response _page(List<int> ids, {int? count, bool hasMore = false}) =>
    _json({
      'count': count ?? ids.length,
      'next': hasMore ? '/api/documents/?page=2&trashed=1' : null,
      'previous': null,
      'results': [
        for (final id in ids)
          {
            'id': id,
            'title': 'Document $id',
            'mime_type': 'application/pdf',
            'original_size': 42,
            'created_at': 1770000000,
            'updated_at': 1770000000,
            'trashed_at': 1770000000,
            'tags': <String>[],
          },
      ],
    });

http.Response _failure(int status, {String? requestId}) => http.Response(
  jsonEncode({'code': 'rejected', 'error': 'Request rejected.'}),
  status,
  headers: {'content-type': 'application/json', 'x-request-id': ?requestId},
);

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

final class _MemoryVault implements CredentialVault {
  @override
  Future<void> clear() async {}
  @override
  Future<StoredCredentials?> read() async => null;
  @override
  Future<void> save(StoredCredentials credentials) async {}
}
