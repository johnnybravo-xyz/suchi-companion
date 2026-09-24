import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/api_models.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';
import 'package:suchi_mobile/auth/session_controller.dart';
import 'package:suchi_mobile/documents/document_list_mode.dart';
import 'package:suchi_mobile/documents/documents_screen.dart';
import 'package:suchi_mobile/documents/jd_category_store.dart';
import 'package:suchi_mobile/documents/jd_index.dart';
import 'package:suchi_mobile/documents/thumbnail_cache.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('sorts the selected category with 200% text on $platform', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final requests = <Uri>[];
      await _showDocuments(
        tester,
        (request) async {
          requests.add(request.url);
          return _page([]);
        },
        platform: platform,
        textScale: 2,
      );
      expect(requests.single.queryParameters['ordering'], '-created_at');
      await tester.tap(find.byTooltip('Open JD Index'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Utilities'));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['jd_category_id'], '31');
      for (final entry in const {
        'Oldest first': 'created_at',
        'Title A–Z': 'title',
        'Recently updated': '-updated_at',
        'Newest first': '-created_at',
      }.entries) {
        await tester.tap(find.byTooltip('Sort documents'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(CheckedPopupMenuItem<String>, entry.key),
        );
        await tester.pumpAndSettle();
        expect(requests.last.queryParameters, {
          'page': '1',
          'page_size': '30',
          'ordering': entry.value,
          'jd_category_id': '31',
        });
        expect(find.text('No documents here'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets(
    'changing sort resets pagination and ignores a late previous page',
    (tester) async {
      final requests = <Uri>[];
      final previousPage = Completer<http.Response>();
      await _showDocuments(tester, (request) async {
        requests.add(request.url);
        if (request.url.queryParameters['ordering'] == 'title') {
          return _page([_document(101, 'Alphabetical receipt')]);
        }
        if (request.url.queryParameters['page'] == '2') {
          return previousPage.future;
        }
        return _page(
          List.generate(
            8,
            (index) => _document(index + 1, 'Receipt ${index + 1}'),
          ),
          hasMore: true,
        );
      });
      await tester.fling(find.byType(ListView), const Offset(0, -2000), 3000);
      await tester.pump(const Duration(milliseconds: 500));
      expect(requests.last.queryParameters['page'], '2');
      await tester.tap(find.byTooltip('Sort documents'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'Title A–Z'),
      );
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['page'], '1');
      expect(requests.last.queryParameters['ordering'], 'title');
      expect(find.text('Alphabetical receipt'), findsOneWidget);
      previousPage.complete(_page([_document(99, 'Stale receipt')]));
      await tester.pumpAndSettle();
      expect(find.text('Stale receipt'), findsNothing);
      expect(find.text('Alphabetical receipt'), findsOneWidget);
    },
  );

  testWidgets('view changes retain browsing state and revisions reload it', (
    tester,
  ) async {
    final mode = ValueNotifier(DocumentListMode.standard);
    final revision = ValueNotifier(0);
    addTearDown(mode.dispose);
    addTearDown(revision.dispose);
    final requests = <Uri>[];
    final previousPage = Completer<http.Response>();
    await _showDocuments(
      tester,
      (request) async {
        requests.add(request.url);
        if (request.url.queryParameters['page'] == '2') {
          if (revision.value == 0) return previousPage.future;
          return _page([_document(101, 'New page receipt')]);
        }
        return _page(
          List.generate(
            30,
            (index) => _document(index + 1, 'Receipt ${index + 1}'),
          ),
          hasMore: true,
        );
      },
      listMode: mode,
      refreshRevision: revision,
    );
    await tester.tap(find.byTooltip('Open JD Index'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Utilities'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sort documents'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<String>, 'Title A–Z'),
    );
    await tester.pumpAndSettle();

    final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
    scroll.jumpTo(200);
    await tester.pumpAndSettle();
    final requestCount = requests.length;
    for (final value in DocumentListMode.values) {
      mode.value = value;
      await tester.pumpAndSettle();
      expect(scroll.offset, 200);
      expect(requests, hasLength(requestCount));
    }

    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(requests.last.queryParameters['page'], '2');
    revision.value++;
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters, {
      'page': '1',
      'page_size': '30',
      'ordering': 'title',
      'jd_category_id': '31',
    });
    expect(scroll.offset, 0);
    previousPage.complete(_page([_document(99, 'Stale receipt')]));
    await tester.pumpAndSettle();
    expect(find.text('Stale receipt'), findsNothing);

    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['page'], '2');
    expect(find.text('New page receipt'), findsOneWidget);
  });

  testWidgets('opens a Saved View with its exact document scope', (
    tester,
  ) async {
    final requests = <Uri>[];
    final view = SavedView.fromJson({
      'id': 7,
      'name': 'Quarterly tax',
      'filter_json': '{"q":"quarterly tax","tags__id__in":[2,4],"document_ids":[17,42],"ordering":"title"}',
      'display': 'list',
      'position': 0,
      'created_at': 1,
      'updated_at': 1,
    });

    await _showDocuments(tester, (request) async {
      requests.add(request.url);
      return _page([]);
    }, savedView: view);

    expect(requests.single.queryParameters, {
      'page': '1',
      'page_size': '30',
      'ordering': 'title',
      'q': 'quarterly tax',
      'tags__id__in': '2,4',
      'document_ids': '17,42',
    });
    expect(find.text('Quarterly tax'), findsOneWidget);
    expect(find.byTooltip('Saved View controls sorting'), findsOneWidget);
  });

  testWidgets('refuses an unsupported Saved View without a document request', (
    tester,
  ) async {
    var requests = 0;
    final view = SavedView.fromJson({
      'id': 8,
      'name': 'Future scope',
      'filter_json': '{"future_filter":"value"}',
      'display': 'list',
      'position': 0,
      'created_at': 1,
      'updated_at': 1,
    });

    await _showDocuments(tester, (request) async {
      requests++;
      return _page([]);
    }, savedView: view);

    expect(requests, 0);
    expect(find.text('Future scope'), findsOneWidget);
    expect(
      find.textContaining('cannot be opened in this app version'),
      findsOneWidget,
    );
  });

  testWidgets(
    'filing sheet keeps retry, category selection and Close usable above the keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var fail = true;
      final client = SuchiClient(
        origin: Uri.parse('https://suchi.example.com'),
        token: 'a' * 64,
        httpClient: MockClient(
          (request) async => request.url.path == '/api/handshake'
              ? _fixtureResponse('handshake.json')
              : fail
              ? http.Response(
                  '{"error":{"message":"The category index is temporarily unavailable. Your document has not been changed."}}',
                  503,
                  headers: {
                    'content-type': 'application/json',
                    'x-request-id': 'jd-retry',
                  },
                )
              : _fixtureResponse('jd-categories.json'),
        ),
      );
      final store = JdCategoryStore(client: client, onUnauthorized: (_) {});
      addTearDown(store.dispose);
      addTearDown(client.close);
      int? selected;
      const title =
          'File the very long household insurance document with all supporting pages under a category';
      await tester.pumpWidget(
        MaterialApp(
          theme: SuchiTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = (await showJdCategorySheet(
                    context,
                    store: store,
                    title: title,
                  ))?.id;
                },
                child: const Text('File document'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('File document'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(tester.takeException(), isNull);
      fail = false;
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'no such category');
      await tester.pumpAndSettle();
      expect(find.text('No matching category'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'Utilities');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ListTile, 'Utilities'));
      await tester.tap(find.widgetWithText(ListTile, 'Utilities'));
      await tester.pumpAndSettle();
      expect(selected, 31);
      await tester.tap(find.text('File document'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _showDocuments(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) documents, {
  TargetPlatform platform = TargetPlatform.android,
  double textScale = 1,
  ValueNotifier<DocumentListMode>? listMode,
  ValueNotifier<int>? refreshRevision,
  SavedView? savedView,
}) async {
  final transport = MockClient((request) async {
    switch (request.url.path) {
      case '/api/handshake':
        return _fixtureResponse('handshake.json');
      case '/api/whoami':
        return _fixtureResponse('whoami.json');
      case '/api/jd/categories/':
        return _fixtureResponse('jd-categories.json');
      case '/api/documents/':
        return documents(request);
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
    serverAddress: 'https://suchi.example.com',
    token: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
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
      theme: SuchiTheme.light.copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ListenableBuilder(
        listenable: Listenable.merge([listMode, refreshRevision]),
        builder: (context, _) => DocumentsScreen(
          client: session.client!,
          session: session,
          cache: cache,
          categories: categories,
          listMode: listMode?.value ?? DocumentListMode.standard,
          refreshRevision: refreshRevision?.value ?? 0,
          savedView: savedView,
          onOpenSearch: () {},
          onOpenDocument: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, Object?> _document(int id, String title) => {
  'id': id,
  'title': title,
  'mime_type': 'application/pdf',
  'original_size': 1200,
  'created_at': 1770000000,
  'updated_at': 1770000000,
  'tags': <String>[],
  'correspondents': <String>[],
};
http.Response _page(
  List<Map<String, Object?>> documents, {
  bool hasMore = false,
}) => http.Response(
  jsonEncode({
    'count': documents.length + (hasMore ? 1 : 0),
    'next': hasMore ? '/api/documents/?page=2' : null,
    'results': documents,
  }),
  200,
  headers: {'content-type': 'application/json'},
);
http.Response _fixtureResponse(String name) => http.Response(
  File('test/fixtures/api/v1/$name').readAsStringSync(),
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
