import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/app/app_services.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';
import 'package:suchi_mobile/auth/session_controller.dart';
import 'package:suchi_mobile/detail/document_detail_screen.dart';
import 'package:suchi_mobile/detail/document_files.dart';
import 'package:suchi_mobile/documents/document_list_mode.dart';
import 'package:suchi_mobile/documents/documents_screen.dart';
import 'package:suchi_mobile/documents/thumbnail_cache.dart';
import 'package:suchi_mobile/inbox/inbox_screen.dart';
import 'package:suchi_mobile/more/app_settings_controller.dart';
import 'package:suchi_mobile/scan/network_monitor.dart';
import 'package:suchi_mobile/scan/scan_capture_controller.dart';
import 'package:suchi_mobile/scan/scan_database.dart';
import 'package:suchi_mobile/scan/scan_queue_screen.dart';
import 'package:suchi_mobile/scan/scan_queue_store.dart';
import 'package:suchi_mobile/scan/scanner_bridge.dart';
import 'package:suchi_mobile/scan/storage_protection.dart';
import 'package:suchi_mobile/scan/upload_coordinator.dart';
import 'package:suchi_mobile/share/share_bridge.dart';
import 'package:suchi_mobile/share/share_import_controller.dart';
import 'package:suchi_mobile/shell/shell.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporary;
  late ScanDatabase database;
  late AppServices services;
  late _Archive archive;
  late int scannerCalls;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    archive = _Archive();
    scannerCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(scannerChannelName), (
          _,
        ) async {
          scannerCalls++;
          return {'cancelled': true, 'page_count': 0, 'pages': <Object>[]};
        });
    temporary = await Directory.systemTemp.createTemp('suchi-navigation-');
    database = ScanDatabase(NativeDatabase.memory());
    final queue = await ScanQueueStore.open(
      database: database,
      root: Directory('${temporary.path}/queue'),
      storageProtection: const _NoopProtection(),
    );
    final session = SessionController(
      vault: _MemoryVault(),
      clientFactory: (origin, token) => SuchiClient(
        origin: origin,
        token: token,
        httpClient: MockClient(archive.handle),
      ),
    );
    await session.pairWithToken(
      serverAddress: 'https://suchi.example.com',
      token: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    final shareBridge = ShareBridge();
    final files = Directory('${temporary.path}/exports');
    await files.create();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.suchi.page/documents'),
          (_) async => null,
        );
    services = AppServices(
      queue: queue,
      session: session,
      settings: AppSettingsController(database),
      uploads: UploadCoordinator(
        store: queue,
        network: _OfflineNetwork(),
        currentClient: () => session.client,
        currentIdentity: () => session.identity,
        deviceOcrEnabled: () => false,
        onUnauthorized: session.expire,
      ),
      capture: ScanCaptureController(
        scanner: ScannerBridge(),
        queue: queue,
        currentIdentity: () => session.identity,
      ),
      shareBridge: shareBridge,
      shareImport: ShareImportController(
        intake: shareBridge,
        queue: queue,
        currentIdentity: () => session.identity,
      ),
      thumbnails: ThumbnailMemoryCache(),
      documentFiles: DocumentFiles(root: files),
    );
    await services.settings.initialize();
  });

  tearDown(() async {
    await services.close();
    await database.close();
    await temporary.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(scannerChannelName),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.suchi.page/documents'),
          null,
        );
  });

  void testNavigation(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        // Drift schedules stream cleanup when the shell unmounts.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }

  Future<void> showShell(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.android,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: SuchiTheme.light.copyWith(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ListenableBuilder(
          listenable: services.session,
          builder: (context, _) =>
              services.session.state == SessionState.signedIn
              ? SuchiShell(services: services)
              : const Scaffold(body: Text('Signed out')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> retainUpload(
    WidgetTester tester, {
    String id = 'accepted-upload',
    String state = 'filed',
    int? documentId = 35,
    bool restored = false,
    bool split = false,
    String? splitIds,
    bool foreign = false,
  }) async {
    await tester.runAsync(() async {
      await database
          .into(database.scanUploads)
          .insert(
            ScanUploadsCompanion.insert(
              id: id,
              payloadPath: '$id.pdf',
              sha256: 'a' * 64,
              byteSize: 9,
              mimeType: 'application/pdf',
              filename: '$id.pdf',
              source: 'share',
              pageCount: 1,
              state: state,
              identityUserId: drift.Value(
                state == 'unassigned' ? null : services.session.user!.userId,
              ),
              identityOrigin: drift.Value(
                state == 'unassigned'
                    ? null
                    : foreign
                    ? 'https://another.example.com'
                    : services.session.origin.toString(),
              ),
              identitySystemId: drift.Value(
                state == 'unassigned' ? null : services.session.user!.systemId,
              ),
              serverDocumentId: drift.Value(documentId),
              restored: drift.Value(restored),
              split: drift.Value(split),
              splitOriginId: drift.Value(split ? 35 : null),
              splitDocumentIds: drift.Value(splitIds),
              createdAtMs: 1,
              updatedAtMs: 1,
            ),
          );
    });
  }

  Future<void> showQueue(WidgetTester tester) async {
    // A retained unassigned item exposes View even with historical successes.
    await retainUpload(
      tester,
      id: 'local-upload',
      state: 'unassigned',
      documentId: null,
    );
    await showShell(tester);
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.byType(ScanQueueScreen), findsOneWidget);
    expect(scannerCalls, 0);
  }

  Future<void> openRetained(
    WidgetTester tester, {
    String id = 'accepted-upload',
  }) async {
    await _scrollTo(tester, ScanQueueScreen, '$id.pdf');
    await tester.tap(find.text('$id.pdf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final acceptance in [
    (state: 'filed', restored: false),
    (state: 'filed', restored: true),
    (state: 'duplicate', restored: false),
    (state: 'processingServer', restored: false),
    (state: 'processingFailed', restored: false),
  ]) {
    testNavigation(
      'accepted ${acceptance.state} restored=${acceptance.restored} opens detail and Back stays in Scan',
      (tester) async {
        await retainUpload(
          tester,
          state: acceptance.state,
          restored: acceptance.restored,
        );
        await showQueue(tester);
        await openRetained(tester);
        await tester.pumpAndSettle();
        expect(find.byType(DocumentDetailScreen), findsOneWidget);
        expect(find.text('Receipt 035'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('accepted-upload.pdf').hitTestable(), findsOneWidget);
        expect(scannerCalls, 0);
      },
    );
  }

  testNavigation('local-only and foreign queue documents cannot navigate', (
    tester,
  ) async {
    for (final state in ['queued', 'uploading', 'uploadFailed']) {
      await retainUpload(tester, id: state, state: state, documentId: null);
    }
    await retainUpload(tester, id: 'foreign', foreign: true);
    await showQueue(tester);
    for (final id in ['local-upload', 'queued', 'uploading', 'uploadFailed']) {
      await openRetained(tester, id: id);
      expect(find.byType(DocumentDetailScreen), findsNothing);
    }
    expect(find.text('foreign.pdf'), findsNothing);
    expect(
      archive.requests.where(
        (request) => RegExp(r'^/api/documents/\d+$').hasMatch(request.url.path),
      ),
      isEmpty,
    );
    expect(scannerCalls, 0);
  });

  testNavigation(
    'split upload shows actual ordered titles and opens only chosen child',
    (tester) async {
      await retainUpload(tester, split: true, splitIds: '[101,102,101]');
      archive.splitResults = [
        {...archive.documents[101], 'split_origin_id': 35, 'split_index': 1},
        {...archive.documents[100], 'split_origin_id': 35, 'split_index': 0},
        {...archive.documents[102], 'split_origin_id': 35, 'split_index': 2},
      ];
      await showQueue(tester);
      await openRetained(tester);
      await tester.pumpAndSettle();
      expect(find.text('Documents from this upload'), findsOneWidget);
      expect(find.text('Receipt 103'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Receipt 101')).dy,
        lessThan(tester.getTopLeft(find.text('Receipt 102')).dy),
      );
      expect(find.text('Part 1'), findsOneWidget);
      await tester.tap(find.text('Receipt 102'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentDetailScreen), findsOneWidget);
      expect(find.text('Receipt 102'), findsOneWidget);
      expect(
        archive.requests.any(
          (request) => request.url.path == '/api/documents/35',
        ),
        isFalse,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('accepted-upload.pdf'), findsOneWidget);
      expect(scannerCalls, 0);
    },
  );

  testNavigation(
    'one distinct split child opens directly without loading a picker',
    (tester) async {
      await retainUpload(tester, split: true, splitIds: '[102,102]');
      await showQueue(tester);
      await openRetained(tester);
      await tester.pumpAndSettle();
      expect(find.text('Receipt 102'), findsOneWidget);
      expect(find.text('Documents from this upload'), findsNothing);
      expect(
        archive.listRequests.where(
          (request) =>
              request.url.queryParameters.containsKey('split_origin_id'),
        ),
        isEmpty,
      );
      expect(
        archive.requests.any(
          (request) => request.url.path == '/api/documents/35',
        ),
        isFalse,
      );
    },
  );

  testNavigation(
    'split load failure retries and later refresh failure retains usable children',
    (tester) async {
      await retainUpload(tester, split: true, splitIds: '[101,102]');
      archive.failSplit = true;
      archive.splitResults = [
        {...archive.documents[101], 'split_origin_id': 35, 'split_index': 1},
      ];
      await showQueue(tester);
      await openRetained(tester);
      await tester.pumpAndSettle();
      expect(find.text('Split lookup unavailable.'), findsOneWidget);
      expect(find.text('Request split-request'), findsOneWidget);
      archive.failSplit = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Receipt 102'), findsOneWidget);
      expect(
        find.text('Some documents from this upload are no longer available.'),
        findsOneWidget,
      );
      archive.failSplit = true;
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Split lookup unavailable.'), findsOneWidget);
      await tester.tap(find.text('Receipt 102'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentDetailScreen), findsOneWidget);
      expect(find.text('Receipt 102'), findsOneWidget);
    },
  );

  testNavigation(
    'missing split children show unavailable without opening the parent',
    (tester) async {
      await retainUpload(tester, split: true, splitIds: '[101,102]');
      await showQueue(tester);
      await openRetained(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('These split documents are no longer available.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentDetailScreen), findsNothing);
      expect(find.text('accepted-upload.pdf'), findsOneWidget);
    },
  );

  for (final ids in ['invalid', '[]', '[0,102]', '["101",102]', '[35,102]']) {
    testNavigation('malformed split IDs $ids never fall back to parent', (
      tester,
    ) async {
      await retainUpload(tester, split: true, splitIds: ids);
      await showQueue(tester);
      await openRetained(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('Documents from this upload could not be identified.'),
        findsOneWidget,
      );
      expect(find.byType(DocumentDetailScreen), findsNothing);
      expect(
        archive.listRequests.where(
          (request) =>
              request.url.queryParameters.containsKey('split_origin_id'),
        ),
        isEmpty,
      );
    });
  }

  for (final changeOrigin in [false, true]) {
    testNavigation(
      'account transition changeOrigin=$changeOrigin removes only owned picker and rejects late children',
      (tester) async {
        await retainUpload(tester, split: true, splitIds: '[101,102]');
        final pending = Completer<http.Response>();
        archive.pendingSplit = pending;
        await showQueue(tester);
        await openRetained(tester);
        expect(find.text('Documents from this upload'), findsOneWidget);
        unawaited(
          showDialog<void>(
            context: tester.element(find.text('Documents from this upload')),
            builder: (context) => AlertDialog(
              title: const Text('Unrelated dialog'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Dismiss dialog'),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (changeOrigin) {
          await services.session.pairWithToken(
            serverAddress: 'https://another.example.com',
            token: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          );
        } else {
          await services.session.signOut();
        }
        await tester.pump();
        expect(
          find.text('Documents from this upload', skipOffstage: false),
          findsNothing,
        );
        expect(find.text('Unrelated dialog'), findsOneWidget);
        pending.complete(
          _json({
            'count': 1,
            'results': [
              {
                ...archive.documents[101],
                'split_origin_id': 35,
                'split_index': 1,
              },
            ],
          }),
        );
        await tester.pumpAndSettle();
        expect(find.text('Receipt 102', skipOffstage: false), findsNothing);
        await tester.tap(find.text('Dismiss dialog'));
        await tester.pumpAndSettle();
        if (changeOrigin) {
          expect(
            services.session.origin,
            Uri.parse('https://another.example.com'),
          );
          expect(find.byType(SuchiShell), findsOneWidget);
        } else {
          expect(find.text('Signed out'), findsOneWidget);
        }
        expect(find.byType(DocumentDetailScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testNavigation(
    'queue recovery actions do not navigate and discard cancellation retains row',
    (tester) async {
      await retainUpload(tester, state: 'processingFailed');
      await retainUpload(
        tester,
        id: 'failed-upload',
        state: 'uploadFailed',
        documentId: null,
      );
      await showQueue(tester);
      await _scrollTo(tester, ScanQueueScreen, 'accepted-upload.pdf');
      await tester.tap(find.text('Check again'));
      await _pumpQueueWork(tester);
      expect(find.byType(DocumentDetailScreen), findsNothing);
      expect(find.text('Check again'), findsNothing);
      await _scrollTo(tester, ScanQueueScreen, 'failed-upload.pdf');
      final failedRow = find.byKey(const ValueKey('failed-upload'));
      await tester.tap(
        find.descendant(of: failedRow, matching: find.text('Discard')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('failed-upload.pdf'), findsOneWidget);
      expect(find.byType(DocumentDetailScreen), findsNothing);
      await tester.tap(
        find.descendant(of: failedRow, matching: find.text('Retry')),
      );
      await _pumpQueueWork(tester);
      expect(find.byType(DocumentDetailScreen), findsNothing);
      expect(
        find.descendant(of: failedRow, matching: find.text('Retry')),
        findsNothing,
      );
      expect(
        archive.requests.any((request) => request.method == 'POST'),
        isFalse,
      );
      expect(scannerCalls, 0);
    },
  );

  testNavigation('iOS left-edge back preserves the filtered document archive', (
    tester,
  ) async {
    await showShell(tester, platform: TargetPlatform.iOS);
    await tester.tap(find.text('Documents').last);
    await tester.pumpAndSettle();
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
    await _scrollTo(tester, DocumentsScreen, 'Receipt 035');
    final offset = _listOffset(tester, DocumentsScreen);
    final rowPosition = tester.getTopLeft(find.text('Receipt 035'));
    final requestsBefore = archive.listRequests.length;

    await tester.tap(find.text('Receipt 035'));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentDetailScreen), findsOneWidget);

    await tester.dragFrom(const Offset(195, 420), const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentDetailScreen), findsOneWidget);

    await tester.dragFrom(const Offset(5, 420), const Offset(370, 0));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentDetailScreen), findsNothing);
    expect(find.text('Receipt 035').hitTestable(), findsOneWidget);
    expect(_listOffset(tester, DocumentsScreen), closeTo(offset, 0.1));
    expect(tester.getTopLeft(find.text('Receipt 035')), rowPosition);
    expect(find.text('31 Utilities'), findsOneWidget);
    expect(archive.listRequests, hasLength(requestsBefore));
    expect(
      tester
          .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
          .initialValue,
      'title',
    );
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final textScale in [1.0, 2.0]) {
      testNavigation(
        'back preserves paged documents, category and sort on $platform at $textScale text',
        (tester) async {
          await showShell(tester, platform: platform, textScale: textScale);
          await tester.tap(find.text('Documents').last);
          await tester.pumpAndSettle();
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
          await _scrollTo(tester, DocumentsScreen, 'Receipt 035');
          expect(archive.listRequests.last.url.queryParameters, {
            'page': '2',
            'page_size': '30',
            'ordering': 'title',
            'jd_category_id': '31',
          });
          final offset = _listOffset(tester, DocumentsScreen);
          final rowPosition = tester.getTopLeft(find.text('Receipt 035'));
          final requestsBefore = archive.listRequests.length;
          expect(offset, greaterThan(0));

          for (final systemBack in [false, true]) {
            await tester.tap(find.text('Receipt 035'));
            await tester.pumpAndSettle();
            expect(find.byType(DocumentDetailScreen), findsOneWidget);
            if (systemBack) {
              await tester.binding.handlePopRoute();
            } else {
              await tester.pageBack();
            }
            await tester.pumpAndSettle();

            expect(find.text('Receipt 035').hitTestable(), findsOneWidget);
            expect(_listOffset(tester, DocumentsScreen), closeTo(offset, 0.1));
            expect(tester.getTopLeft(find.text('Receipt 035')), rowPosition);
            expect(find.text('31 Utilities'), findsOneWidget);
            expect(archive.listRequests, hasLength(requestsBefore));
            expect(
              tester
                  .widget<PopupMenuButton<String>>(
                    find.byType(PopupMenuButton<String>),
                  )
                  .initialValue,
              'title',
            );
          }
          await _scrollTo(tester, DocumentsScreen, 'Receipt 063');
          expect(archive.listRequests.last.url.queryParameters['page'], '3');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testNavigation('back preserves the paged Inbox', (tester) async {
    await showShell(tester);
    await _scrollTo(tester, InboxScreen, 'Receipt 100');
    final offset = _listOffset(tester, InboxScreen);
    final requestsBefore = archive.listRequests.length;
    await tester.tap(find.text('Receipt 100'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Receipt 100').hitTestable(), findsOneWidget);
    expect(_listOffset(tester, InboxScreen), closeTo(offset, 0.1));
    expect(archive.listRequests, hasLength(requestsBefore));
  });

  testNavigation(
    'More changes both document views without refetching or losing browsing state',
    (tester) async {
      await showShell(tester);
      await _scrollTo(tester, InboxScreen, 'Receipt 100');
      final inboxOffset = _listOffset(tester, InboxScreen);
      await tester.tap(find.text('Documents').last);
      await tester.pumpAndSettle();
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
      await _scrollTo(tester, DocumentsScreen, 'Receipt 035');
      final documentsOffset = _listOffset(tester, DocumentsScreen);
      final requestsBefore = archive.listRequests.length;
      for (final entry in {
        'Compact': DocumentListMode.compact,
        'Detailed': DocumentListMode.detailed,
        'Standard': DocumentListMode.standard,
      }.entries) {
        await tester.tap(find.text('More').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Document view'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.key).last);
        await tester.pumpAndSettle();
        expect(services.settings.documentListMode, entry.value);
        await tester.tap(find.text('Documents').last);
        await tester.pumpAndSettle();
        expect(
          _listOffset(tester, DocumentsScreen),
          closeTo(documentsOffset, 0.1),
        );
        expect(find.text('31 Utilities'), findsOneWidget);
        await tester.tap(find.text('Inbox').last);
        await tester.pumpAndSettle();
        expect(_listOffset(tester, InboxScreen), closeTo(inboxOffset, 0.1));
        expect(archive.listRequests, hasLength(requestsBefore));
      }
      await tester.tap(find.text('Receipt 100'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(_listOffset(tester, InboxScreen), closeTo(inboxOffset, 0.1));
    },
  );

  testNavigation(
    'detail retry and a refused edit preserve the list on return',
    (tester) async {
      await showShell(tester);
      await tester.tap(find.text('Documents').last);
      await tester.pumpAndSettle();
      await _scrollTo(tester, DocumentsScreen, 'Receipt 035');
      final offset = _listOffset(tester, DocumentsScreen);
      final requestsBefore = archive.listRequests.length;
      archive.failDetail = true;
      await tester.tap(find.text('Receipt 035'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      archive.failDetail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit document'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Refused title');
      archive.refuseEdit = true;
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('This edit is not allowed.'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Receipt 035').hitTestable(), findsOneWidget);
      expect(_listOffset(tester, DocumentsScreen), closeTo(offset, 0.1));
      expect(archive.listRequests, hasLength(requestsBefore));
    },
  );

  testNavigation('a successful edit refreshes the archive on return', (
    tester,
  ) async {
    await showShell(tester);
    await tester.tap(find.text('Documents').last);
    await tester.pumpAndSettle();
    final requestsBefore = archive.listRequests.length;
    await tester.tap(find.text('Receipt 001'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit document'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Renamed receipt');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Renamed receipt'), findsOneWidget);
    expect(find.text('Receipt 001'), findsNothing);
    expect(archive.listRequests.length, greaterThan(requestsBefore));
  });

  testNavigation('filing from detail refreshes the Inbox', (tester) async {
    await showShell(tester);
    await tester.tap(find.text('Receipt 066'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('File under'));
    await tester.tap(find.text('File under'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Utilities'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Receipt 066'), findsNothing);
    expect(find.text('Receipt 067'), findsOneWidget);
  });

  testNavigation('Trash and Undo refresh the archive', (tester) async {
    await showShell(tester);
    await tester.tap(find.text('Documents').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receipt 001'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move to Trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Move to Trash'));
    await tester.pumpAndSettle();

    expect(find.byType(DocumentDetailScreen), findsNothing);
    expect(find.text('Receipt 001'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt 001'), findsOneWidget);
  });

  testNavigation('a late Undo cannot refresh a signed-out archive', (
    tester,
  ) async {
    await showShell(tester);
    await tester.tap(find.text('Documents').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receipt 001'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move to Trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Move to Trash'));
    await tester.pumpAndSettle();

    final pending = Completer<http.Response>();
    archive.pendingRestore = pending;
    await tester.tap(find.text('Undo'));
    await tester.pump();
    final requestsBefore = archive.listRequests.length;
    await services.session.signOut();
    await tester.pumpAndSettle();
    pending.complete(_json({}));
    await tester.pumpAndSettle();

    expect(find.text('Signed out'), findsOneWidget);
    expect(find.byType(DocumentsScreen), findsNothing);
    expect(archive.listRequests, hasLength(requestsBefore));
    expect(tester.takeException(), isNull);
  });

  testNavigation('a late detail response cannot restore a signed-out list', (
    tester,
  ) async {
    await showShell(tester);
    await tester.tap(find.text('Documents').last);
    await tester.pumpAndSettle();
    await _scrollTo(tester, DocumentsScreen, 'Receipt 035');
    final requestsBefore = archive.listRequests.length;
    final pending = Completer<http.Response>();
    archive.pendingDetail = pending;
    await tester.tap(find.text('Receipt 035'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await services.session.signOut();
    await tester.pumpAndSettle();
    pending.complete(_json(archive.document(35)));
    await tester.pumpAndSettle();

    expect(find.text('Signed out'), findsOneWidget);
    expect(find.text('Receipt 035'), findsNothing);
    expect(find.byType(DocumentsScreen), findsNothing);
    expect(archive.listRequests, hasLength(requestsBefore));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpQueueWork(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _scrollTo(WidgetTester tester, Type screen, String title) async {
  await tester.scrollUntilVisible(
    find.text(title),
    500,
    scrollable: find.descendant(
      of: find.byType(screen),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            (widget.axisDirection == AxisDirection.down ||
                widget.axisDirection == AxisDirection.up),
      ),
    ),
    maxScrolls: 60,
  );
  await tester.pumpAndSettle();
}

double _listOffset(WidgetTester tester, Type screen) => tester
    .widget<ListView>(
      find.descendant(of: find.byType(screen), matching: find.byType(ListView)),
    )
    .controller!
    .offset;

final class _Archive {
  final requests = <http.Request>[];
  final documents = <Map<String, Object?>>[
    for (var id = 1; id <= 130; id++)
      {
        'id': id,
        'title': 'Receipt ${id.toString().padLeft(3, '0')}',
        'mime_type': 'application/pdf',
        'original_size': 1200,
        'created_at': 1770000000,
        'updated_at': 1770000000,
        'jd_category_id': id <= 65 ? 31 : 49,
        'sensitivity': 'restricted',
        'tags': <String>[],
        'correspondents': <String>[],
      },
  ];
  final trashed = <int>{};
  bool failDetail = false;
  bool refuseEdit = false;
  Completer<http.Response>? pendingDetail;
  Completer<http.Response>? pendingRestore;
  List<Map<String, Object?>> splitResults = [];
  bool failSplit = false;
  Completer<http.Response>? pendingSplit;

  List<http.Request> get listRequests => requests
      .where((request) => request.url.path == '/api/documents/')
      .toList();

  Map<String, Object?> document(int id) => {
    ...jsonDecode(
      File('test/fixtures/api/v1/document-detail.json').readAsStringSync(),
    ) as Map<String, dynamic>,
    ...documents.singleWhere((document) => document['id'] == id),
  };

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    switch (path) {
      case '/api/handshake':
        return _fixture('handshake.json');
      case '/api/whoami':
        return _fixture('whoami.json');
      case '/api/jd/categories/':
        return _fixture('jd-categories.json');
      case '/api/documents/':
        final query = request.url.queryParameters;
        if (query.containsKey('split_origin_id')) {
          if (pendingSplit != null) return pendingSplit!.future;
          if (failSplit) {
            return http.Response(
              jsonEncode({'message': 'Split lookup unavailable.'}),
              503,
              headers: {
                'content-type': 'application/json',
                'x-request-id': 'split-request',
              },
            );
          }
          return _json({'count': splitResults.length, 'results': splitResults});
        }
        final category = int.tryParse(query['jd_category_id'] ?? '');
        final page = int.parse(query['page']!);
        final pageSize = int.parse(query['page_size']!);
        final results = documents
            .where(
              (document) =>
                  !trashed.contains(document['id']) &&
                  (category == null || document['jd_category_id'] == category),
            )
            .toList();
        return _json({
          'count': results.length,
          'next': page * pageSize < results.length
              ? '/api/documents/?page=${page + 1}'
              : null,
          'results': results
              .skip((page - 1) * pageSize)
              .take(pageSize)
              .toList(),
        });
    }
    final match = RegExp(r'^/api/documents/(\d+)(/restore)?$').firstMatch(path);
    if (match == null) return http.Response('', 404);
    final id = int.parse(match.group(1)!);
    if (match.group(2) != null) {
      if (pendingRestore != null) return pendingRestore!.future;
      trashed.remove(id);
      return _json({});
    }
    if (request.method == 'DELETE') {
      trashed.add(id);
      return http.Response('', 204);
    }
    if (request.method == 'PATCH') {
      if (refuseEdit) {
        return _json({'message': 'This edit is not allowed.'}, status: 409);
      }
      documents
          .singleWhere((document) => document['id'] == id)
          .addAll(jsonDecode(request.body) as Map<String, dynamic>);
      return _json({'id': id});
    }
    if (pendingDetail != null) return pendingDetail!.future;
    if (failDetail) return _json({'message': 'Try later.'}, status: 503);
    return _json(document(id));
  }
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

final class _OfflineNetwork implements NetworkMonitor {
  @override
  Stream<bool> get changes => const Stream.empty();

  @override
  Future<bool> isOnline() async => false;
}
