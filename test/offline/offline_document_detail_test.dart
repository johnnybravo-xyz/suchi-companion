import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/api_models.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';
import 'package:suchi_mobile/auth/session_controller.dart';
import 'package:suchi_mobile/detail/document_detail_screen.dart';
import 'package:suchi_mobile/detail/document_files.dart';
import 'package:suchi_mobile/documents/jd_category_store.dart';
import 'package:suchi_mobile/documents/thumbnail_cache.dart';
import 'package:suchi_mobile/offline/offline_document_store.dart';
import 'package:suchi_mobile/scan/storage_protection.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporary;
  late DocumentFiles files;
  late OfflineDocumentStore store;
  late SessionController session;
  late List<http.Request> requests;
  late bool failDocumentMetadata;
  late bool sensitive;
  late String originalBlob;
  late List<MethodCall> handoffs;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('suchi-offline-detail-');
    files = DocumentFiles(
      root: await Directory('${temporary.path}/exports').create(),
    );
    var uuid = 0;
    store = await OfflineDocumentStore.open(
      files: files,
      root: Directory('${temporary.path}/offline'),
      storageProtection: const _NoopProtection(),
      newUuid: () {
        uuid++;
        return '00000000-0000-4000-8000-${uuid.toString().padLeft(12, '0')}';
      },
      now: () => DateTime.utc(2026, 9, 12),
    );
    requests = [];
    failDocumentMetadata = false;
    sensitive = false;
    originalBlob = 'b' * 64;
    session = SessionController(
      vault: _MemoryVault(),
      clientFactory: (origin, token) => SuchiClient(
        origin: origin,
        token: token,
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/api/handshake') {
            return _fixture('handshake.json');
          }
          if (request.url.path == '/api/whoami') {
            return _fixture('whoami.json');
          }
          if (request.url.path == '/api/jd/categories/') {
            if (failDocumentMetadata) throw const SocketException('offline');
            return _fixture('jd-categories.json');
          }
          if (request.url.path == '/api/documents/91') {
            if (failDocumentMetadata) throw const SocketException('offline');
            return http.Response(
              jsonEncode(
                _documentJson(sensitive: sensitive, blob: originalBlob),
              ),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/documents/91/download') {
            return http.Response.bytes(
              _payload,
              200,
              headers: {'content-type': 'application/pdf'},
            );
          }
          return http.Response(
            '{"code":"not_found","message":"not found"}',
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    await session.pairWithToken(
      serverAddress: 'https://suchi.example.com',
      token: 'a' * 64,
    );
    handoffs = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.suchi.page/documents'),
          (call) async {
            handoffs.add(call);
            return null;
          },
        );
  });

  tearDown(() async {
    await testerBindingCleanup();
    session.dispose();
    await store.close();
    await temporary.delete(recursive: true);
  });

  testWidgets(
    'sensitive documents require confirmation before an offline download',
    (tester) async {
      sensitive = true;
      await _pumpDetail(tester, session, files, store);

      await tester.scrollUntilVisible(
        find.text('Make available offline'),
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('Make available offline'));
      await tester.pumpAndSettle();
      expect(find.text('Keep sensitive document offline?'), findsOneWidget);
      expect(store.find(session.identity, 91), isNull);

      expect(
        requests.where(
          (request) => request.url.path == '/api/documents/91/download',
        ),
        isEmpty,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.find(session.identity, 91), isNull);
    },
  );

  testWidgets('detail reflects save, update, and remove states', (
    tester,
  ) async {
    await _pumpDetail(tester, session, files, store);

    await tester.scrollUntilVisible(
      find.text('Make available offline'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Make available offline'), findsOneWidget);

    await tester.runAsync(
      () => store.save(
        identity: session.identity!,
        document: DocumentDetail.fromJson(_documentJson(blob: 'b' * 64)),
        client: session.client!,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final saved = store.find(session.identity, 91);
    expect(saved, isNotNull);
    expect(await tester.runAsync(saved!.payload.readAsBytes), _payload);
    expect(find.text('Remove offline copy'), findsOneWidget);
    expect(find.text('Available offline'), findsOneWidget);

    originalBlob = 'c' * 64;
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpDetail(tester, session, files, store);
    await tester.scrollUntilVisible(
      find.text('Update offline copy'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Update offline copy'), findsOneWidget);

    await tester.runAsync(
      () => store.save(
        identity: session.identity!,
        document: DocumentDetail.fromJson(_documentJson(blob: 'c' * 64)),
        client: session.client!,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(store.find(session.identity, 91)?.document.originalBlob, 'c' * 64);
    expect(find.text('Update offline copy'), findsNothing);
    expect(find.text('Remove offline copy'), findsOneWidget);
    expect(find.text('Available offline'), findsOneWidget);

    await tester.tap(find.text('Remove offline copy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Remove offline copy?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(store.find(session.identity, 91), isNotNull);

    await tester.runAsync(() => store.remove(session.identity!, 91));
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.find(session.identity, 91), isNull);
    expect(find.text('Make available offline'), findsOneWidget);
  });

  testWidgets(
    'metadata network failure renders a read-only manifest fallback',
    (tester) async {
      await tester.runAsync(
        () => store.save(
          identity: session.identity!,
          document: DocumentDetail.fromJson(_documentJson()),
          client: session.client!,
        ),
      );
      requests.clear();
      failDocumentMetadata = true;

      await _pumpDetail(tester, session, files, store);

      expect(find.text('Showing offline copy'), findsOneWidget);
      expect(find.text('Preview unavailable offline'), findsOneWidget);
      expect(find.text('Quarterly report'), findsOneWidget);
      expect(
        requests.where((request) => request.url.path.contains('preview')),
        isEmpty,
      );
      expect(
        requests.where((request) => request.url.path.contains('thumbnail')),
        isEmpty,
      );

      await tester.ensureVisible(find.text('Open'));
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 20 && handoffs.isEmpty; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump(const Duration(milliseconds: 300));

      expect(handoffs, hasLength(1));
      expect(handoffs.single.method, 'open');
      expect(
        (handoffs.single.arguments as Map)['path'],
        store.find(session.identity, 91)!.payload.path,
      );
      expect(
        requests.where((request) => request.url.path.endsWith('/download')),
        isEmpty,
      );
      final edit = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.edit_outlined),
      );
      final trash = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline),
      );
      expect(edit.onPressed, isNull);
      expect(trash.onPressed, isNull);
    },
  );
}

const _payload = <int>[37, 80, 68, 70, 45, 111, 102, 102, 108, 105, 110, 101];

Future<void> _pumpDetail(
  WidgetTester tester,
  SessionController session,
  DocumentFiles files,
  OfflineDocumentStore store,
) async {
  final categories = JdCategoryStore(
    client: session.client!,
    onUnauthorized: session.expire,
  );
  addTearDown(categories.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: SuchiTheme.light,
      home: DocumentDetailScreen(
        documentId: 91,
        client: session.client!,
        session: session,
        cache: ThumbnailMemoryCache(),
        categories: categories,
        files: files,
        offlineDocuments: store,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

http.Response _fixture(String name) => http.Response(
  File('test/fixtures/api/v1/$name').readAsStringSync(),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _documentJson({bool sensitive = false, String? blob}) => {
  'id': 91,
  'title': 'Quarterly report',
  'mime_type': 'application/pdf',
  'original_size': _payload.length,
  'original_blob': blob ?? 'b' * 64,
  'jd_category_id': 31,
  'jd_category_code': 31,
  'jd_category_name': 'Utilities',
  'jd_area_name': 'Home',
  'sensitivity': sensitive ? 'restricted' : '',
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
};

Future<void> testerBindingCleanup() async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('app.suchi.page/documents'),
        null,
      );
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
