import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_companion/api/suchi_client.dart';
import 'package:suchi_companion/auth/credential_vault.dart';
import 'package:suchi_companion/auth/session_controller.dart';
import 'package:suchi_companion/documents/document_list_mode.dart';
import 'package:suchi_companion/documents/jd_category_store.dart';
import 'package:suchi_companion/documents/thumbnail_cache.dart';
import 'package:suchi_companion/inbox/inbox_screen.dart';
import 'package:suchi_companion/theme/suchi_theme.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _origin = Uri.parse('https://suchi.example.com');
String _fixture(String name) =>
    File('test/fixtures/api/v1/$name').readAsStringSync();

void main() {
  for (final mode in DocumentListMode.values) {
    testWidgets('pages $mode Inbox while trash and Undo stay local', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final listMode = ValueNotifier(mode);
      final revision = ValueNotifier(0);
      addTearDown(listMode.dispose);
      addTearDown(revision.dispose);
      final requests = <http.Request>[];
      final transport = MockClient((request) async {
        requests.add(request);
        switch (request.url.path) {
          case '/api/handshake':
            return _json(_fixture('handshake.json'));
          case '/api/whoami':
            return _json(_fixture('whoami.json'));
          case '/api/jd/categories/':
            return _json(
              jsonEncode({
                'count': 1,
                'next': null,
                'previous': null,
                'results': [
                  {
                    'id': 9,
                    'code': 49,
                    'name': 'Inbox',
                    'description': 'Needs filing',
                    'area_code': 40,
                    'area_name': 'Inbox',
                    'system': true,
                  },
                ],
              }),
            );
          case '/api/documents/':
            final secondPage = request.url.queryParameters['page'] == '2';
            return _json(
              jsonEncode({
                'count': 9,
                'next': secondPage ? null : '/api/documents/?page=2',
                'previous': secondPage ? '/api/documents/?page=1' : null,
                'results': secondPage
                    ? [
                        {
                          ..._documentSummary,
                          'id': 25,
                          'title': 'Second letter',
                        },
                      ]
                    : List.generate(
                        8,
                        (index) => {
                          ..._documentSummary,
                          'id': 17 + index,
                          'title': index == 0
                              ? 'Restricted letter'
                              : 'Inbox item ${index + 1}',
                        },
                      ),
              }),
            );
          case '/api/documents/17':
            if (request.method == 'DELETE') return http.Response('', 204);
            if (request.method == 'POST') return _json('{}');
            return http.Response('', 405);
          case '/api/documents/17/restore':
            return _json('{}');
          default:
            return http.Response('', 404);
        }
      });
      final session = SessionController(
        vault: _MemoryVault(),
        clientFactory: (origin, token) =>
            SuchiClient(origin: origin, token: token, httpClient: transport),
      );
      await session.pairWithToken(
        serverAddress: _origin.toString(),
        token: _token,
      );
      final categories = JdCategoryStore(
        client: session.client!,
        onUnauthorized: session.expire,
      );
      addTearDown(categories.dispose);
      addTearDown(session.dispose);
      final cache = ThumbnailMemoryCache();
      await tester.pumpWidget(
        MaterialApp(
          theme: SuchiTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: Listenable.merge([listMode, revision]),
              builder: (context, _) => InboxScreen(
                client: session.client!,
                session: session,
                cache: cache,
                categories: categories,
                listMode: listMode.value,
                refreshRevision: revision.value,
                onOpenDocument: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Restricted letter'), findsOneWidget);
      expect(
        requests.where((request) => request.url.path == '/api/documents/'),
        hasLength(1),
      );

      final list = find.byType(ListView);
      await tester.fling(list, const Offset(0, -2000), 3000);
      await tester.pumpAndSettle();

      expect(
        requests.where(
          (request) =>
              request.url.path == '/api/documents/' &&
              request.url.queryParameters['page'] == '2',
        ),
        hasLength(1),
      );
      expect(find.text('Second letter'), findsOneWidget);

      final scroll = tester.widget<ListView>(list).controller!;
      scroll.jumpTo(50);
      await tester.pumpAndSettle();
      final listRequestCount = requests
          .where((request) => request.url.path == '/api/documents/')
          .length;
      for (final value in DocumentListMode.values) {
        listMode.value = value;
        await tester.pumpAndSettle();
        expect(scroll.offset, 50);
        expect(
          requests.where((request) => request.url.path == '/api/documents/'),
          hasLength(listRequestCount),
        );
        expect(tester.takeException(), isNull);
      }
      listMode.value = mode;
      await tester.pumpAndSettle();

      await tester.fling(list, const Offset(0, 2000), 3000);
      await tester.pumpAndSettle();

      await tester.drag(find.text('Restricted letter'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('Restricted letter'), findsNothing);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Restricted letter'), findsOneWidget);
      expect(
        requests.where(
          (request) =>
              request.url.path == '/api/documents/17' &&
              request.method == 'DELETE',
        ),
        hasLength(1),
      );
      expect(
        requests.where(
          (request) => request.url.path == '/api/documents/17/restore',
        ),
        hasLength(1),
      );
      revision.value++;
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(
        requests.where((request) => request.url.path == '/api/documents/'),
        hasLength(listRequestCount + 1),
      );
      expect(
        requests
            .lastWhere((request) => request.url.path == '/api/documents/')
            .url
            .queryParameters['page'],
        '1',
      );
      expect(find.text('Restricted letter'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

final _documentSummary = {
  'id': 17,
  'title': 'Restricted letter',
  'mime_type': 'application/pdf',
  'original_size': 1200,
  'jd_category_id': 9,
  'jd_category_code': 49,
  'jd_category_name': 'Inbox',
  'jd_area_name': 'Inbox',
  'sensitivity': 'restricted',
  'thumb_sha': 'abc',
  'split_origin_id': null,
  'split_index': null,
  'created_at': 1770000000,
  'updated_at': 1770000000,
  'trashed_at': null,
  'tags': <String>[],
  'correspondents': <String>[],
};

http.Response _json(String body) =>
    http.Response(body, 200, headers: {'content-type': 'application/json'});

final class _MemoryVault implements CredentialVault {
  @override
  Future<void> clear() async {}

  @override
  Future<StoredCredentials?> read() async => null;

  @override
  Future<void> save(StoredCredentials credentials) async {}
}
