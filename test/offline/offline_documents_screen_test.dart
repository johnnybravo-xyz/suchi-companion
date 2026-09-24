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
import 'package:suchi_mobile/detail/document_files.dart';
import 'package:suchi_mobile/documents/document_list_mode.dart';
import 'package:suchi_mobile/documents/jd_category_store.dart';
import 'package:suchi_mobile/documents/documents_screen.dart';
import 'package:suchi_mobile/documents/thumbnail_cache.dart';
import 'package:suchi_mobile/offline/offline_document_store.dart';
import 'package:suchi_mobile/scan/network_monitor.dart';
import 'package:suchi_mobile/scan/storage_protection.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporary;
  late OfflineDocumentStore store;
  late SessionController session;
  late _Network network;
  late SuchiClient client;
  late int listRequests;
  late List<http.Request> apiRequests;
  late bool listFails;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('suchi-offline-screen-');
    final files = DocumentFiles(
      root: await Directory('${temporary.path}/exports').create(),
    );
    store = await OfflineDocumentStore.open(
      files: files,
      root: Directory('${temporary.path}/offline'),
      storageProtection: const _NoopProtection(),
      newUuid: () => '00000000-0000-4000-8000-000000000001',
      now: () => DateTime.utc(2026, 9, 12),
    );
    session = SessionController(
      vault: _MemoryVault(),
      clientFactory: (origin, token) => SuchiClient(
        origin: origin,
        token: token,
        httpClient: MockClient(_sessionResponse),
      ),
    );
    await session.pairWithToken(
      serverAddress: 'https://suchi.example.com',
      token: 'a' * 64,
    );
    final bytes = utf8.encode('%PDF-offline');
    await store.save(
      identity: session.identity!,
      document: _document(bytes.length),
      client: SuchiClient(
        origin: session.origin!,
        token: 'a' * 64,
        httpClient: MockClient(
          (_) async => http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'application/pdf'},
          ),
        ),
      ),
    );
    listRequests = 0;
    apiRequests = [];
    listFails = true;
    network = _Network(false);
    client = SuchiClient(
      origin: session.origin!,
      token: 'a' * 64,
      httpClient: MockClient((request) async {
        apiRequests.add(request);
        if (request.url.path == '/api/documents/') {
          listRequests++;
          if (listFails) throw const SocketException('offline');
          return _fixture('documents-page.json');
        }
        if (request.url.path == '/api/jd/categories/') {
          return _fixture('jd-categories.json');
        }
        return http.Response(
          '{"code":"not_found","message":"not found"}',
          404,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  tearDown(() async {
    await network.close();
    session.dispose();
    await store.close();
    await temporary.delete(recursive: true);
  });

  testWidgets('known no-connectivity starts Offline without an HTTP request', (
    tester,
  ) async {
    int? openedDocument;
    OfflineDocument? handedOff;
    await _pumpDocuments(
      tester,
      session: session,
      client: client,
      store: store,
      network: network,
      onOpenDocument: (id) => openedDocument = id,
      onOpenOffline: (entry) => handedOff = entry,
    );

    expect(find.text('Offline'), findsWidgets);
    expect(find.text('Quarterly report'), findsOneWidget);
    expect(listRequests, 0);

    await tester.tap(find.text('Quarterly report'));
    expect(openedDocument, 91);
    expect(handedOff, isNull);

    network.setOnline(true);
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsWidgets);
    expect(find.text('Quarterly report'), findsOneWidget);
    expect(listRequests, 0);
  });

  testWidgets(
    'a document-list network failure switches to Offline and stays there',
    (tester) async {
      network.online = true;
      await _pumpDocuments(
        tester,
        session: session,
        client: client,
        store: store,
        network: network,
      );

      expect(listRequests, 1);
      expect(find.text('Offline'), findsWidgets);
      expect(find.text('Quarterly report'), findsOneWidget);

      network.setOnline(true);
      await tester.pumpAndSettle();
      expect(listRequests, 1);
      expect(find.text('Offline'), findsWidgets);
    },
  );

  testWidgets('online selector opens Offline without requesting previews', (
    tester,
  ) async {
    listFails = false;
    network.online = true;
    final categories = JdCategoryStore(
      client: client,
      onUnauthorized: session.expire,
    );
    addTearDown(categories.dispose);
    int? openedDocument;
    await _pumpDocuments(
      tester,
      session: session,
      client: client,
      store: store,
      network: network,
      categories: categories,
      onOpenDocument: (id) => openedDocument = id,
    );

    expect(find.text('All documents'), findsOneWidget);
    expect(listRequests, 1);
    await tester.tap(find.byTooltip('Open JD Index'));
    await tester.pumpAndSettle();
    final beforeOffline = apiRequests.length;
    await tester.tap(find.text('Offline').last);
    await tester.pumpAndSettle();

    expect(find.text('Quarterly report'), findsOneWidget);
    expect(apiRequests, hasLength(beforeOffline));
    await tester.tap(find.text('Quarterly report'));
    expect(openedDocument, 91);
  });

  testWidgets('local-only Documents hands the protected payload off directly', (
    tester,
  ) async {
    OfflineDocument? handedOff;
    await _pumpDocuments(
      tester,
      session: session,
      client: null,
      store: store,
      network: network,
      onOpenOffline: (entry) => handedOff = entry,
    );

    expect(find.text('Quarterly report'), findsOneWidget);
    expect(apiRequests, isEmpty);
    await tester.tap(find.text('Quarterly report'));
    expect(handedOff?.document.id, 91);
  });
}

Future<void> _pumpDocuments(
  WidgetTester tester, {
  required SessionController session,
  required SuchiClient? client,
  required OfflineDocumentStore store,
  required NetworkMonitor network,
  JdCategoryStore? categories,
  ValueChanged<int>? onOpenDocument,
  ValueChanged<OfflineDocument>? onOpenOffline,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: SuchiTheme.light,
      home: DocumentsScreen(
        client: client,
        session: session,
        cache: ThumbnailMemoryCache(),
        categories: categories,
        offlineDocuments: store,
        network: network,
        onOpenSearch: () {},
        onOpenDocument: onOpenDocument ?? (_) {},
        onOpenOfflineDocument: onOpenOffline ?? (_) {},
        listMode: DocumentListMode.standard,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

http.Response _fixture(String name) => http.Response(
  File('test/fixtures/api/v1/$name').readAsStringSync(),
  200,
  headers: {'content-type': 'application/json'},
);

Future<http.Response> _sessionResponse(http.Request request) async =>
    http.Response(
      File(
        request.url.path == '/api/handshake'
            ? 'test/fixtures/api/v1/handshake.json'
            : 'test/fixtures/api/v1/whoami.json',
      ).readAsStringSync(),
      200,
      headers: {'content-type': 'application/json'},
    );

DocumentDetail _document(int size) => DocumentDetail.fromJson({
  'id': 91,
  'title': 'Quarterly report',
  'mime_type': 'application/pdf',
  'original_size': size,
  'original_blob': 'b' * 64,
  'jd_category_id': 31,
  'jd_category_code': 31,
  'jd_category_name': 'Utilities',
  'jd_area_name': 'Home',
  'sensitivity': '',
  'created_at': 100,
  'added_at': 110,
  'updated_at': 120,
  'source_mtime': null,
  'trashed_at': null,
  'sources': const [],
  'tags': const ['tax'],
  'correspondents': const [],
  'languages': 'eng',
  'languages_locked': false,
  'content': '',
});

final class _Network implements NetworkMonitor {
  _Network(this.online);

  bool online;
  final _changes = StreamController<bool>.broadcast();

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  Future<bool> isOnline() async => online;

  void setOnline(bool value) {
    online = value;
    _changes.add(value);
  }

  Future<void> close() => _changes.close();
}

final class _MemoryVault implements CredentialVault {
  @override
  Future<void> clear() async {}

  @override
  Future<StoredCredentials?> read() async => null;

  @override
  Future<void> save(StoredCredentials credentials) async {}
}

final class _NoopProtection implements StorageProtection {
  const _NoopProtection();

  @override
  Future<void> protectDirectory(String path) async {}
}
