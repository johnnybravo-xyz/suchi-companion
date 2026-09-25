import 'dart:async';
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
  late List<http.BaseRequest> requests;
  late bool failDocumentMetadata;
  late bool sensitive;
  late String originalBlob;
  late StreamController<List<int>>? downloadChunks;
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
    downloadChunks = null;
    session = SessionController(
      vault: _MemoryVault(),
      clientFactory: (origin, token) => SuchiClient(
        origin: origin,
        token: token,
        httpClient: MockClient.streaming((request, _) async {
          requests.add(request);
          if (request.url.path == '/api/documents/91/download') {
            return http.StreamedResponse(
              downloadChunks?.stream ?? Stream.value(_payload),
              200,
              contentLength: _payload.length,
              headers: {'content-type': 'application/pdf'},
            );
          }
          if (failDocumentMetadata &&
              (request.url.path == '/api/jd/categories/' ||
                  request.url.path == '/api/documents/91')) {
            throw const SocketException('offline');
          }
          final response = switch (request.url.path) {
            '/api/handshake' => _fixture('handshake.json'),
            '/api/whoami' => _fixture('whoami.json'),
            '/api/jd/categories/' => _fixture('jd-categories.json'),
            '/api/documents/91' => http.Response(
              jsonEncode(
                _documentJson(sensitive: sensitive, blob: originalBlob),
              ),
              200,
              headers: {'content-type': 'application/json'},
            ),
            _ => http.Response(
              '{"code":"not_found","message":"not found"}',
              404,
              headers: {'content-type': 'application/json'},
            ),
          };
          return http.StreamedResponse(
            Stream.value(response.bodyBytes),
            response.statusCode,
            contentLength: response.bodyBytes.length,
            headers: response.headers,
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
          const MethodChannel('page.suchi.companion/documents'),
          (call) async {
            handoffs.add(call);
            return null;
          },
        );
  });

  tearDown(() async {
    if (downloadChunks != null && !downloadChunks!.isClosed) {
      await downloadChunks!.close();
    }
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
        find.text('Save offline'),
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('Save offline'));
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

  testWidgets('detail saves, updates, and removes through the caption menu', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpDetail(tester, session, files, store);

    final preview = find.byKey(const ValueKey('document-preview'));
    final save = find.widgetWithText(OutlinedButton, 'Save offline');
    final open = find.widgetWithText(FilledButton, 'Open');
    await tester.ensureVisible(save);
    expect(save, findsOneWidget);
    expect(find.byTooltip('Make available offline'), findsOneWidget);
    final saveBounds = tester.getRect(save);
    final openBounds = tester.getRect(open);
    expect(saveBounds.right, lessThan(openBounds.left));
    expect(saveBounds.width, closeTo(openBounds.width, 2));
    expect(saveBounds.height, closeTo(openBounds.height, 2));
    expect(saveBounds.height, greaterThanOrEqualTo(52));
    expect(
      tester
          .getRect(find.descendant(of: preview, matching: find.text('PDF')))
          .bottom,
      lessThan(saveBounds.top),
    );
    expect(
      tester
          .getRect(find.descendant(of: preview, matching: find.text('12 B')))
          .bottom,
      lessThan(saveBounds.top),
    );

    await tester.tap(save);
    await tester.pump();
    await _waitForCopy(tester, store, session, blob: 'b' * 64);
    final saved = store.find(session.identity, 91)!;
    expect(await tester.runAsync(saved.payload.readAsBytes), _payload);
    expect(handoffs, isEmpty);
    expect(find.text('Available offline'), findsOneWidget);
    expect(find.text('Save offline'), findsNothing);
    await tester.tap(find.byTooltip('Offline copy options'));
    await tester.pumpAndSettle();
    expect(find.text('Remove offline copy'), findsOneWidget);
    expect(find.text('Update offline copy'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    originalBlob = 'c' * 64;
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpDetail(tester, session, files, store);
    expect(find.text('Update needed'), findsOneWidget);
    await tester.tap(find.byTooltip('Offline copy options'));
    await tester.pumpAndSettle();
    expect(find.text('Update offline copy'), findsOneWidget);
    expect(find.text('Remove offline copy'), findsOneWidget);
    await tester.tap(find.text('Update offline copy'));
    await tester.pump();
    await _waitForCopy(tester, store, session, blob: 'c' * 64);
    expect(find.text('Available offline'), findsOneWidget);
    expect(find.text('Update needed'), findsNothing);

    await tester.tap(find.byTooltip('Offline copy options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove offline copy'));
    await tester.pumpAndSettle();
    expect(find.text('Remove offline copy?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.find(session.identity, 91), isNotNull);

    await tester.tap(find.byTooltip('Offline copy options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove offline copy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove', skipOffstage: false));
    for (
      var attempt = 0;
      attempt < 80 && (store.find(session.identity, 91) != null || store.busy);
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();
    expect(store.find(session.identity, 91), isNull);
    expect(find.text('Save offline'), findsOneWidget);
  });

  testWidgets('detail shows written-byte progress until the copy is verified', (
    tester,
  ) async {
    final listening = Completer<void>();
    final halfWritten = Completer<void>();
    final allWritten = Completer<void>();
    downloadChunks = StreamController<List<int>>.broadcast(
      onListen: listening.complete,
    );
    store.addListener(() {
      if (store.savingProgress == 0.5 && !halfWritten.isCompleted) {
        halfWritten.complete();
      }
      if (store.savingFinishing && !allWritten.isCompleted) {
        allWritten.complete();
      }
    });
    Future<void> advanceUntil(bool Function() ready) async {
      for (var attempt = 0; attempt < 80 && !ready(); attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        ready(),
        isTrue,
        reason:
            'requests=${requests.map((request) => request.url.path).toList()} '
            'saving=${store.savingIdentity} error=${store.errorMessage}',
      );
    }

    await _pumpDetail(tester, session, files, store);
    final save = find.widgetWithText(OutlinedButton, 'Save offline');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    await advanceUntil(() => listening.isCompleted);

    Finder progress() => find.byWidgetPredicate(
      (widget) =>
          widget is LinearProgressIndicator &&
          widget.semanticsLabel == 'Offline copy progress',
    );
    expect(tester.widget<LinearProgressIndicator>(progress()).value, 0);
    expect(store.find(session.identity, 91), isNull);

    downloadChunks!.add(_payload.sublist(0, 6));
    await advanceUntil(() => halfWritten.isCompleted);
    expect(tester.widget<LinearProgressIndicator>(progress()).value, 0.5);
    expect(find.textContaining('50% downloaded'), findsOneWidget);
    expect(store.find(session.identity, 91), isNull);

    downloadChunks!.add(_payload.sublist(6));
    await advanceUntil(() => allWritten.isCompleted);
    expect(find.text('Finishing offline copy…'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(progress()).value, isNull);
    expect(store.find(session.identity, 91), isNull);

    await downloadChunks!.close();
    await _waitForCopy(tester, store, session, blob: 'b' * 64);
    expect(progress(), findsNothing);
    expect(find.text('Available offline'), findsOneWidget);
  });

  testWidgets('narrow 200% detail stacks controls and keeps caption clear', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final dark in [false, true]) {
      await _pumpDetail(
        tester,
        session,
        files,
        store,
        textScale: 2,
        dark: dark,
      );

      final save = find.widgetWithText(OutlinedButton, 'Save offline');
      final open = find.widgetWithText(FilledButton, 'Open');
      final preview = find.byKey(const ValueKey('document-preview'));
      expect(tester.getRect(save).bottom, lessThan(tester.getRect(open).top));
      expect(tester.getRect(save).left, closeTo(tester.getRect(open).left, 2));
      expect(
        tester.getRect(save).right,
        closeTo(tester.getRect(open).right, 2),
      );
      expect(
        tester
            .getRect(find.descendant(of: preview, matching: find.text('PDF')))
            .bottom,
        lessThan(tester.getRect(save).top),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    await tester.runAsync(
      () => store.save(
        identity: session.identity!,
        document: DocumentDetail.fromJson(_documentJson()),
        client: session.client!,
      ),
    );
    for (final dark in [false, true]) {
      await _pumpDetail(
        tester,
        session,
        files,
        store,
        textScale: 2,
        dark: dark,
      );
      final preview = find.byKey(const ValueKey('document-preview'));
      final status = find.text('Available offline');
      final menu = find.byTooltip('Offline copy options');
      final open = find.widgetWithText(FilledButton, 'Open');
      expect(find.descendant(of: preview, matching: status), findsOneWidget);
      expect(tester.getRect(status).right, lessThan(tester.getRect(menu).left));
      expect(tester.getRect(menu).size, const Size(48, 48));
      expect(tester.getRect(menu).bottom, lessThan(tester.getRect(open).top));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'metadata network failure renders a read-only manifest fallback',
    (tester) async {
      sensitive = true;
      await tester.runAsync(
        () => store.save(
          identity: session.identity!,
          document: DocumentDetail.fromJson(_documentJson(sensitive: true)),
          client: session.client!,
          reveal: true,
        ),
      );
      requests.clear();
      failDocumentMetadata = true;

      await _pumpDetail(tester, session, files, store);

      expect(find.text('Showing offline copy'), findsOneWidget);
      expect(find.text('Preview unavailable offline'), findsOneWidget);
      expect(find.text('Available offline'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('12 B'), findsOneWidget);
      await tester.tap(find.byTooltip('Offline copy options'));
      await tester.pumpAndSettle();
      expect(find.text('Remove offline copy'), findsOneWidget);
      expect(find.text('Update offline copy'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
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
      expect(find.text('Open this document?'), findsOneWidget);
      expect(handoffs, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(handoffs, isEmpty);
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.tap(find.text('Open document'));
      await tester.pump();
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
  OfflineDocumentStore store, {
  double textScale = 1,
  bool dark = false,
}) async {
  final categories = JdCategoryStore(
    client: session.client!,
    onUnauthorized: session.expire,
  );
  addTearDown(categories.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? SuchiTheme.dark : SuchiTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
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

Future<void> _waitForCopy(
  WidgetTester tester,
  OfflineDocumentStore store,
  SessionController session, {
  required String blob,
}) async {
  for (
    var attempt = 0;
    attempt < 80 &&
        (store.find(session.identity, 91)?.document.originalBlob != blob ||
            store.busy);
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump();
  expect(
    store.find(session.identity, 91)?.document.originalBlob,
    blob,
    reason: 'busy=${store.busy} error=${store.errorMessage}',
  );
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
        const MethodChannel('page.suchi.companion/documents'),
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
