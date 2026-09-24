import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';
import 'package:suchi_mobile/auth/session_controller.dart';
import 'package:suchi_mobile/detail/document_files.dart';
import 'package:suchi_mobile/documents/document_list_mode.dart';
import 'package:suchi_mobile/documents/documents_screen.dart';
import 'package:suchi_mobile/documents/jd_category_store.dart';
import 'package:suchi_mobile/documents/thumbnail_cache.dart';
import 'package:suchi_mobile/offline/offline_document_store.dart';
import 'package:suchi_mobile/scan/storage_protection.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture fixture;
  setUp(() async => fixture = await _Fixture.open());
  tearDown(() async => fixture.close());

  testWidgets(
    'right swipe reveals an operable offline action; left swipe does not',
    (tester) async {
      _phoneViewport(tester);
      final opened = <int>[];
      await fixture.show(tester, onOpen: opened.add);
      final rowY = tester.getCenter(find.text('Receipt')).dy;
      await tester.tap(find.text('Receipt'));
      expect(opened, [91]);
      final action = find.text('Make available offline').hitTestable();
      expect(action, findsNothing);
      await tester.drag(find.text('Receipt'), const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(action, findsNothing);
      expect(fixture.detailRequests, 0);
      expect(fixture.downloadRequests, 0);
      await tester.drag(find.text('Receipt'), const Offset(220, 0));
      await tester.pumpAndSettle();
      expect(action, findsOneWidget);
      expect(fixture.detailRequests, 0);
      expect(fixture.downloadRequests, 0);
      await tester.tapAt(Offset(340, rowY));
      expect(opened, [91, 91]);
      await tester.tap(action);
      await _waitForCopy(tester, fixture, downloads: 1);
      final entry = fixture.store.find(fixture.session.identity, 91);
      expect(entry?.document.title, 'Authoritative receipt');
      expect(
        await tester.runAsync(entry!.payload.readAsBytes),
        utf8.encode('%PDF-saved'),
      );
      expect(fixture.detailRequests, 1);
      expect(fixture.downloadRequests, 1);
      expect(find.text('Update offline copy'), findsOneWidget);
      await tester.tap(find.text('Update offline copy'));
      await _waitForCopy(tester, fixture, downloads: 2);
      expect(fixture.store.entriesFor(fixture.session.identity), hasLength(1));
      expect(fixture.detailRequests, 2);
      expect(fixture.downloadRequests, 2);
      expect(opened, [91, 91]);
    },
  );

  testWidgets('offline action remains tappable with large phone text', (
    tester,
  ) async {
    _phoneViewport(tester);
    await fixture.show(tester, textScaler: const TextScaler.linear(2));
    await tester.drag(find.text('Receipt'), const Offset(220, 0));
    await tester.pumpAndSettle();
    final action = find.text('Save offline').hitTestable();
    expect(action, findsOneWidget);
    expect(fixture.detailRequests, 0);
    await tester.tap(action);
    await _waitForCopy(tester, fixture, downloads: 1);
    expect(fixture.store.entriesFor(fixture.session.identity), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fresh sensitive detail needs consent; refusal never downloads', (
    tester,
  ) async {
    fixture.sensitivity = 'confidential';
    await fixture.show(tester);
    await tester.drag(find.text('Receipt'), const Offset(220, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make available offline'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Keep sensitive document offline?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fixture.detailRequests, 1);
    expect(fixture.downloadRequests, 0);
    expect(fixture.store.entriesFor(fixture.session.identity), isEmpty);
    expect(find.text('Document is available offline.'), findsNothing);
  });

  testWidgets('a failed download never publishes a copy or success', (
    tester,
  ) async {
    fixture.failDownload = true;
    await fixture.show(tester);
    await tester.drag(find.text('Receipt'), const Offset(220, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make available offline'));
    await _waitForCopy(tester, fixture, downloads: 1);
    expect(fixture.detailRequests, 1);
    expect(fixture.downloadRequests, 1);
    expect(fixture.store.entriesFor(fixture.session.identity), isEmpty);
    expect(find.text('Document is available offline.'), findsNothing);
    expect(find.text('Make available offline'), findsOneWidget);
  });

  testWidgets(
    'late detail response after account change cannot start a download',
    (tester) async {
      final detail = Completer<http.Response>();
      fixture.delayedDetail = detail;
      await fixture.show(tester);
      final oldIdentity = fixture.session.identity!;
      await tester.drag(find.text('Receipt'), const Offset(220, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make available offline'));
      await tester.pump();
      expect(fixture.detailRequests, 1);
      expect(await fixture.session.signOut(), isTrue);
      await tester.pump();
      await fixture.session.pairWithToken(
        serverAddress: 'https://other.example.com',
        token: 'b' * 64,
      );
      await tester.pump();
      detail.complete(fixture.detailResponse());
      await tester.pumpAndSettle();
      expect(fixture.downloadRequests, 0);
      expect(fixture.store.entriesFor(oldIdentity), isEmpty);
      expect(fixture.store.entriesFor(fixture.session.identity), isEmpty);
      expect(find.text('Document is available offline.'), findsNothing);
    },
  );
}

void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _waitForCopy(
  WidgetTester tester,
  _Fixture fixture, {
  required int downloads,
}) async {
  await tester.pump();
  for (var attempt = 0; attempt < 500; attempt++) {
    if (fixture.downloadRequests >= downloads && !fixture.store.busy) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail(
    'Offline copy did not finish: detail=${fixture.detailRequests}, '
    'downloads=${fixture.downloadRequests}, busy=${fixture.store.busy}.',
  );
}

final class _Fixture {
  _Fixture(this.temporary, this.store, this.session);

  final Directory temporary;
  final OfflineDocumentStore store;
  final SessionController session;
  int detailRequests = 0;
  int downloadRequests = 0;
  bool failDownload = false;
  String sensitivity = '';
  Completer<http.Response>? delayedDetail;

  static Future<_Fixture> open() async {
    final temporary = await Directory.systemTemp.createTemp('suchi-swipe-');
    final store = await OfflineDocumentStore.open(
      files: DocumentFiles(
        root: await Directory('${temporary.path}/exports').create(),
      ),
      root: Directory('${temporary.path}/offline'),
      storageProtection: const _NoopProtection(),
    );
    late _Fixture fixture;
    final session = SessionController(
      vault: _MemoryVault(),
      clientFactory: (origin, token) => SuchiClient(
        origin: origin,
        token: token,
        httpClient: MockClient((request) => fixture.respond(request)),
      ),
    );
    fixture = _Fixture(temporary, store, session);
    await session.pairWithToken(
      serverAddress: 'https://suchi.example.com',
      token: 'a' * 64,
    );
    return fixture;
  }

  http.Response detailResponse() {
    final json = jsonDecode(
      File('test/fixtures/api/v1/document-detail.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    return http.Response(
      jsonEncode({
        ...json,
        'title': 'Authoritative receipt',
        'original_size': utf8.encode('%PDF-saved').length,
        'sensitivity': sensitivity,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  Future<http.Response> respond(http.Request request) async {
    switch (request.url.path) {
      case '/api/handshake':
        return _fixture('handshake.json');
      case '/api/whoami':
        return _fixture('whoami.json');
      case '/api/jd/categories/':
        return _fixture('jd-categories.json');
      case '/api/documents/':
        return http.Response(
          jsonEncode({
            'count': 1,
            'next': null,
            'results': [
              {
                'id': 91,
                'title': 'Receipt',
                'mime_type': 'application/pdf',
                'original_size': 100,
                'created_at': 1770000000,
                'updated_at': 1770000000,
                'tags': <String>[],
                'correspondents': <String>[],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      case '/api/documents/91':
        detailRequests++;
        return delayedDetail?.future ?? detailResponse();
      case '/api/documents/91/download':
        downloadRequests++;
        return http.Response.bytes(
          utf8.encode(failDownload ? 'bad' : '%PDF-saved'),
          200,
          headers: {'content-type': 'application/pdf'},
        );
      default:
        return http.Response('', 404);
    }
  }

  Future<void> show(
    WidgetTester tester, {
    ValueChanged<int>? onOpen,
    TextScaler? textScaler,
  }) async {
    final categories = JdCategoryStore(
      client: session.client!,
      onUnauthorized: session.expire,
    );
    addTearDown(categories.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: SuchiTheme.light,
        builder: textScaler == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child!,
              ),
        home: ListenableBuilder(
          listenable: session,
          builder: (context, _) => session.state == SessionState.signedIn
              ? DocumentsScreen(
                  client: session.client!,
                  session: session,
                  cache: ThumbnailMemoryCache(),
                  categories: categories,
                  listMode: DocumentListMode.standard,
                  offlineDocuments: store,
                  onOpenSearch: () {},
                  onOpenDocument: onOpen ?? (_) {},
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close() async {
    session.dispose();
    await store.close();
    await temporary.delete(recursive: true);
  }
}

http.Response _fixture(String name) => http.Response(
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

final class _NoopProtection implements StorageProtection {
  const _NoopProtection();
  @override
  Future<void> protectDirectory(String path) async {}
}
