import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/api_models.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/auth/account_identity.dart';
import 'package:suchi_mobile/main.dart';
import 'package:suchi_mobile/scan/network_monitor.dart';
import 'package:suchi_mobile/scan/scan_database.dart';
import 'package:suchi_mobile/scan/scan_queue_screen.dart';
import 'package:suchi_mobile/scan/scan_queue_store.dart';
import 'package:suchi_mobile/scan/scanner_bridge.dart';
import 'package:suchi_mobile/share/share_bridge.dart';
import 'package:suchi_mobile/shell/shell.dart';

import '../support/mobile_app_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MobileAppHarness harness;
  late _Intake intake;
  late _Network network;
  late _Server server;
  late File pdf;
  late DateTime now;

  setUp(() async {
    harness = MobileAppHarness();
    intake = _Intake();
    network = _Network();
    server = _Server();
    now = DateTime.utc(2026, 9, 12);
    await harness.initialize(
      intake: intake,
      network: network,
      transportFactory: server.client,
      now: () => now,
    );
    // Large enough for multiple actual File.openRead payload chunks.
    final bytes = List<int>.filled(2 * 1024 * 1024, 32);
    bytes.setRange(0, 9, '%PDF-1.4\n'.codeUnits);
    pdf = await File('${harness.temporary.path}/shared.pdf')
        .writeAsBytes(bytes);
    server.size = bytes.length;
    server.digest = sha256.convert(bytes).toString();
  });

  tearDown(() async {
    intake.release();
    server.release();
    await harness.close();
    await network.close();
  });

  Future<void> mount(WidgetTester tester, {bool reducedMotion = false}) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    if (reducedMotion) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }
    await tester.pumpWidget(SuchiMobileApp(services: harness.services));
    await _frames(tester);
  }

  Future<ScanUpload> stage({
    String name = 'Shared invoice.pdf',
    AccountIdentity? identity,
    bool unassigned = false,
  }) => harness.services.queue.stage(
    StageDocumentInput(
      sourceFile: pdf,
      mimeType: 'application/pdf',
      filename: name,
      source: ScanSource.share,
      pageCount: 1,
      identity: unassigned ? null : identity ?? harness.identity,
    ),
  );

  testWidgets('offline activity shows bytes saved and Cancel abandons the copy', (
    tester,
  ) async {
    await mount(tester, reducedMotion: true);
    final listening = Completer<void>();
    final requestedPaths = <String>[];
    final chunks = StreamController<List<int>>.broadcast(
      onListen: listening.complete,
    );
    final downloadClient = SuchiClient(
      origin: harness.services.session.origin!,
      token: harness.services.session.client!.token,
      httpClient: MockClient.streaming((request, _) async {
        requestedPaths.add(request.url.path);
        return http.StreamedResponse(
          chunks.stream,
          200,
          contentLength: 16841,
          headers: {'content-type': 'application/pdf'},
        );
      }),
    );
    addTearDown(() async {
      if (!chunks.isClosed) await chunks.close();
      downloadClient.close();
    });
    final document = DocumentDetail.fromJson(
      jsonDecode(fixtureResponse('document-detail.json').body),
    );
    Object? saveFailure;
    final save = harness.services.offlineDocuments
        .save(
          identity: harness.identity!,
          document: document,
          client: downloadClient,
        )
        .then<bool>(
          (_) => true,
          onError: (Object error) {
            saveFailure = error;
            return false;
          },
        );
    await _until(
      tester,
      () => listening.isCompleted || !harness.services.offlineDocuments.busy,
    );
    expect(
      listening.isCompleted,
      isTrue,
      reason:
          'requests=$requestedPaths busy=${harness.services.offlineDocuments.busy} '
          'saving=${harness.services.offlineDocuments.savingIdentity} '
          'error=${harness.services.offlineDocuments.errorMessage} failure=$saveFailure',
    );
    expect(requestedPaths, ['/api/documents/91/download']);
    await _until(
      tester,
      () => find.text('Saving offline copy').evaluate().isNotEmpty,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(
      harness.services.offlineDocuments.find(harness.identity, 91),
      isNull,
    );

    chunks.add(List<int>.filled(8421, 32));
    await _until(
      tester,
      () => find.textContaining('50% downloaded').evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(8421 / 16841, 0.0001),
    );
    expect(
      harness.services.offlineDocuments.find(harness.identity, 91),
      isNull,
    );

    await tester.tap(find.text('Cancel'));
    await _until(
      tester,
      () => harness.services.offlineDocuments.savingIdentity == null,
    );
    await chunks.close();
    await _until(tester, () => !harness.services.offlineDocuments.busy);
    expect(await tester.runAsync(() => save), isFalse);
    expect(find.text('Saving offline copy'), findsNothing);
    expect(
      harness.services.offlineDocuments.find(harness.identity, 91),
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
  });

  testWidgets(
    'shared intake remains visible through real payload transfer, acceptance and processing; View never captures',
    (tester) async {
      final nativePending = Completer<List<SharedBatch>>();
      intake.pendingGate = nativePending;
      server.payloadGate = Completer<void>();
      server.responseGate = Completer<void>();
      server.tasksGate = Completer<void>();
      await tester.runAsync(() async {
        await harness.services.uploads.start();
        await harness.services.uploads.resume();
      });
      await mount(tester);
      expect(find.text('Checking for shared documents'), findsOneWidget);
      expect(find.text('March electricity bill'), findsOneWidget);
      expect(harness.captures, 0);
      final initialReads = server.archiveReads;

      nativePending.complete([
        SharedBatch(
          id: '11111111-1111-4111-8111-111111111111',
          createdAt: now,
          items: [
            SharedItem(
              index: 0,
              path: pdf.path,
              mime: 'application/pdf',
              name: 'Shared invoice.pdf',
              size: server.size,
              sha256: server.digest,
            ),
          ],
          rejectedCount: 0,
          complete: true,
        ),
      ]);
      // Do not run filesystem callbacks yet: the importer has announced local
      // preparation, but no durable payload can have been uploaded.
      await tester.pump();
      await tester.pump();
      expect(find.text('Preparing shared documents'), findsOneWidget);
      expect(find.text('Shared invoice.pdf'), findsNothing);
      await _until(tester, () => server.payloadStarted.isCompleted);
      await _until(
        tester,
        () => find.text('Uploading 1 document').evaluate().isNotEmpty,
      );
      final transferring = (await tester.runAsync(
        harness.services.queue.allUploads,
      ))!.single;
      expect(transferring.bytesSent, greaterThan(0));
      expect(transferring.bytesSent, lessThan(transferring.byteSize));
      final percent = (100 * transferring.bytesSent / transferring.byteSize)
          .floor();
      expect(find.textContaining('$percent%'), findsOneWidget);
      expect(server.archiveReads, initialReads);
      expect(intake.discarded, ['11111111-1111-4111-8111-111111111111']);
      expect(
        await tester.runAsync(
          () => harness.services.queue.hasShareReceipt(
            '11111111-1111-4111-8111-111111111111',
            0,
          ),
        ),
        isTrue,
      );

      await tester.tap(find.text('View'));
      await _frames(tester);
      expect(find.byType(ScanQueueScreen), findsOneWidget);
      expect(find.text('Shared invoice.pdf'), findsOneWidget);
      expect(harness.captures, 0);
      await tester.tap(find.byType(ScanDockButton));
      await _frames(tester);
      expect(harness.captures, 1);
      await tester.tap(find.text('Documents').last);
      await _frames(tester);
      expect(find.text('Uploading 1 document'), findsOneWidget);

      server.payloadGate!.complete();
      await _until(tester, () => server.bodyReceived.isCompleted);
      await _until(
        tester,
        () => find.text('Finishing upload').evaluate().isNotEmpty,
      );
      expect(
        find.textContaining('Waiting for Suchi to accept the file'),
        findsOneWidget,
      );
      expect(find.textContaining('100%'), findsNothing);
      expect(find.text('Newly uploaded invoice'), findsNothing);
      expect(server.archiveReads, initialReads);
      expect(server.receivedBytes, greaterThan(server.size));

      server.responseGate!.complete();
      await _until(
        tester,
        () => find.text('Processing 1 document').evaluate().isNotEmpty,
      );
      expect(
        find.textContaining('Uploaded · Processing in Suchi'),
        findsOneWidget,
      );
      expect(find.textContaining(RegExp(r'\d+%')), findsNothing);
      expect(find.text('Newly uploaded invoice'), findsNothing);
      now = now.add(const Duration(seconds: 3));
      unawaited(harness.services.uploads.processNow());
      await _until(tester, () => server.tasksStarted.isCompleted);
      expect(find.text('Processing 1 document'), findsOneWidget);
      expect(server.archiveReads, initialReads);
      server.tasksGate!.complete();
      await _until(
        tester,
        () => server.taskReads > 0 && !harness.services.uploads.isRunning,
      );
      expect(find.text('Processing 1 document'), findsOneWidget);
      expect(find.text('Newly uploaded invoice'), findsNothing);

      server.taskState = 'done';
      now = now.add(const Duration(seconds: 3));
      unawaited(harness.services.uploads.processNow());
      await _until(
        tester,
        () => find.text('Newly uploaded invoice').evaluate().isNotEmpty,
      );
      expect(find.text('View'), findsNothing);
      expect(server.archiveReads, initialReads + 2);
      await tester.tap(find.text('Inbox').last);
      await _frames(tester);
      expect(find.text('Newly uploaded invoice'), findsOneWidget);
      expect(harness.captures, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await _frames(tester);
    },
  );

  testWidgets(
    'retained failure survives an empty share check; Retry retains local bytes and processing Check again never uploads again',
    (tester) async {
      final upload = await tester.runAsync(stage);
      server.uploadStatus = 422;
      await tester.runAsync(harness.services.uploads.resume);
      await mount(tester, reducedMotion: true);
      expect(find.text('Uploads need attention'), findsOneWidget);
      expect(
        await tester.runAsync(
          () => harness.services.queue.payloadFile(upload!).exists(),
        ),
        isTrue,
      );
      await tester.runAsync(harness.services.shareImport.processPending);
      await _frames(tester);
      expect(find.text('Uploads need attention'), findsOneWidget);
      await tester.tap(find.text('View'));
      await _frames(tester);
      expect(find.text('Shared invoice.pdf'), findsOneWidget);
      expect(find.textContaining('Rejected by archive policy'), findsWidgets);
      network.online = false;
      await tester.ensureVisible(find.text('Retry').last);
      await tester.tap(find.text('Retry').last);
      await _frames(tester);
      expect(find.text('1 document queued'), findsOneWidget);
      expect(find.text('Connected'), findsNothing);
      expect(find.text('Offline'), findsNothing);
      expect(server.uploads, 1);
      await tester.runAsync(harness.services.uploads.pause);
      await _frames(tester);
      expect(find.text('Uploads paused'), findsOneWidget);

      server.uploadStatus = 503;
      network.online = true;
      server.taskStatus = 503;
      unawaited(harness.services.uploads.resume());
      await _until(tester, () => !harness.services.uploads.isRunning);
      await _frames(tester);
      expect(find.text('Waiting to retry'), findsWidgets);
      expect(
        await tester.runAsync(
          () => harness.services.queue.payloadFile(upload!).exists(),
        ),
        isTrue,
      );
      server.uploadStatus = 201;
      now = now.add(const Duration(minutes: 1));
      unawaited(harness.services.uploads.processNow());
      await _until(tester, () => !harness.services.uploads.isRunning);
      await _frames(tester);
      now = now.add(const Duration(seconds: 3));
      unawaited(harness.services.uploads.processNow());
      await _until(tester, () => !harness.services.uploads.isRunning);
      await _frames(tester);
      expect(find.text('Waiting to check processing'), findsOneWidget);
      expect(
        find.textContaining('File uploaded; status check will retry'),
        findsOneWidget,
      );
      expect(find.textContaining(RegExp(r'\d+%')), findsNothing);
      server.taskStatus = 200;
      server.taskState = 'dead';
      now = now.add(const Duration(minutes: 1));
      unawaited(harness.services.uploads.processNow());
      await _until(tester, () => !harness.services.uploads.isRunning);
      await _frames(tester);
      expect(find.text('Uploads need attention'), findsOneWidget);
      expect(find.textContaining('OCR failed'), findsWidgets);
      final attempts = server.uploads;
      server.taskState = 'done';
      await tester.ensureVisible(find.text('Check again'));
      await tester.tap(find.text('Check again'));
      await _until(tester, () => server.completed);
      await _frames(tester);
      expect(server.uploads, attempts);
      expect(find.text('View'), findsNothing);
      expect(harness.captures, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await _frames(tester);
    },
  );

  testWidgets(
    'automatic empty intake checks retain a warning until Scan dismissal without discarding queue files',
    (tester) async {
      final upload = await tester.runAsync(() => stage(unassigned: true));
      intake.batches = [
        SharedBatch(
          id: '22222222-2222-4222-8222-222222222222',
          createdAt: now,
          items: const [],
          rejectedCount: 1,
          complete: true,
        ),
      ];
      await mount(tester, reducedMotion: true);
      await _until(
        tester,
        () => find.text('Shared import needs attention').evaluate().isNotEmpty,
      );
      await tester.runAsync(harness.services.shareImport.processPending);
      await _frames(tester);
      expect(find.text('Shared import needs attention'), findsOneWidget);
      await tester.tap(find.text('View'));
      await _frames(tester);
      await tester.ensureVisible(find.text('Dismiss'));
      await tester.tap(find.text('Dismiss'));
      await _frames(tester);
      expect(find.text('Shared import needs attention'), findsNothing);
      expect(find.text('1 document needs an account'), findsOneWidget);
      expect(
        await tester.runAsync(() => harness.database.uploadById(upload!.id)),
        isNotNull,
      );
      expect(
        await tester.runAsync(
          () => harness.services.queue.payloadFile(upload!).exists(),
        ),
        isTrue,
      );
      expect(harness.captures, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await _frames(tester);
    },
  );

  testWidgets(
    'historical success does not refresh; foreign rows are excluded and unassigned files require explicit assignment',
    (tester) async {
      await tester.runAsync(() => stage(name: 'Historical invoice.pdf'));
      server.deduplicated = true;
      await tester.runAsync(harness.services.uploads.resume);
      final foreign = AccountIdentity(
        origin: harness.identity!.origin,
        userId: harness.identity!.userId,
        systemId: harness.identity!.systemId + 1,
      );
      final foreignUpload = await tester.runAsync(
        () => stage(name: 'Foreign secret.pdf', identity: foreign),
      );
      // The real coordinator must not even attempt this foreign row.
      await tester.runAsync(harness.services.uploads.processNow);
      expect(server.uploads, 1);
      await mount(tester);
      expect(find.text('View'), findsNothing);
      final reads = server.archiveReads;
      await _frames(tester);
      expect(server.archiveReads, reads);
      expect(find.text('Foreign secret.pdf'), findsNothing);
      unawaited(stage(name: 'Choose my account.pdf', unassigned: true));
      await _until(
        tester,
        () => find.text('1 document needs an account').evaluate().isNotEmpty,
      );
      expect(server.uploads, 1);
      await tester.tap(find.text('View'));
      await _frames(tester);
      expect(find.text('Choose my account.pdf'), findsOneWidget);
      expect(find.text('Upload here'), findsOneWidget);
      expect(find.text('Foreign secret.pdf'), findsNothing);
      expect(
        await tester.runAsync(
          () => harness.database.uploadById(foreignUpload!.id),
        ),
        isNotNull,
      );
      expect(harness.captures, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await _frames(tester);
    },
  );

  testWidgets(
    'changing origin during a held transfer conceals the previous queue and never rebinds its saved payload',
    (tester) async {
      await tester.runAsync(() => stage(name: 'Account A rejected.pdf'));
      server.uploadStatus = 422;
      await tester.runAsync(harness.services.uploads.resume);
      server.uploadStatus = 201;
      final upload = await tester.runAsync(
        () => stage(name: 'Account A private.pdf'),
      );
      final originalIdentity = harness.identity!;
      server.responseGate = Completer<void>();
      await mount(tester, reducedMotion: true);
      unawaited(harness.services.uploads.resume());
      await _until(
        tester,
        () => find.text('Finishing upload').evaluate().isNotEmpty,
      );
      expect(find.textContaining('1 item needs attention'), findsOneWidget);
      await tester.tap(find.text('View'));
      await _frames(tester);
      expect(find.text('Account A private.pdf'), findsOneWidget);
      await tester.runAsync(harness.services.session.signOut);
      await _frames(tester);
      expect(find.text('Account A private.pdf'), findsNothing);
      expect(find.text('Finishing upload'), findsNothing);
      await tester.runAsync(
        () => harness.services.session.pairWithToken(
          serverAddress: 'https://other.example.com',
          token: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        ),
      );
      await _frames(tester);
      expect(find.byType(SuchiShell), findsOneWidget);
      expect(find.text('View'), findsNothing);
      expect(find.text('Account A private.pdf'), findsNothing);
      expect(find.text('Account A rejected.pdf'), findsNothing);
      expect(find.text('Uploads need attention'), findsNothing);
      expect(server.uploads, 2);
      final retained = await tester.runAsync(
        () => harness.database.uploadById(upload!.id),
      );
      expect(retained!.identityOrigin, originalIdentity.origin.toString());
      expect(retained.identityUserId, originalIdentity.userId);
      expect(
        await tester.runAsync(
          () => harness.services.queue.payloadFile(retained).exists(),
        ),
        isTrue,
      );
      expect(harness.captures, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await _frames(tester);
    },
  );
  testWidgets(
    'upload activity leaves failed capture Settings, Retry and Discard usable at large text',
    (tester) async {
      await tester.runAsync(stage);
      final native = Directory('${harness.temporary.path}/native-capture');
      await tester.runAsync(() async {
        await native.create();
        await File('${native.path}/document.pdf').writeAsString('not a PDF');
        await File('${native.path}/page.png').writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3e8AAAAASUVORK5CYII=',
          ),
        );
      });
      var denied = true;
      var settingsOpened = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(scannerChannelName), (
            call,
          ) async {
            if (call.method == 'openSettings') {
              settingsOpened++;
            } else if (call.method == 'capture') {
              if (denied) {
                throw PlatformException(
                  code: 'camera_permission_denied',
                  message:
                      'Allow camera access in Settings to scan a document.',
                  details: {'retryable': true, 'open_settings': true},
                );
              }
              return {
                'cancelled': false,
                'page_count': 1,
                'pdf_path': '${native.path}/document.pdf',
                'pages': [
                  {'path': '${native.path}/page.png'},
                ],
              };
            } else if (call.method == 'recognizeText') {
              return <Object>[];
            } else if (call.method == 'discardCapture') {
              await native.delete(recursive: true);
            }
            return null;
          });
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      server.responseGate = Completer<void>();
      await mount(tester, reducedMotion: true);
      unawaited(harness.services.uploads.resume());
      await _until(
        tester,
        () => find.text('Finishing upload').evaluate().isNotEmpty,
      );
      await tester.tap(find.byType(ScanDockButton));
      await _until(
        tester,
        () => find.text('Open Settings').evaluate().isNotEmpty,
      );
      await tester.ensureVisible(find.text('Open Settings'));
      await _frames(tester);
      await tester.tap(find.text('Open Settings'));
      await _frames(tester);
      expect(settingsOpened, 1);
      expect(find.text('Finishing upload'), findsOneWidget);
      denied = false;
      await tester.ensureVisible(find.text('Retry'));
      await _frames(tester);
      await tester.tap(find.text('Retry'));
      await _until(
        tester,
        () => find.text('Discard capture').evaluate().isNotEmpty,
      );
      expect(harness.services.capture.hasPendingCapture, isTrue);
      await tester.ensureVisible(find.text('Discard capture'));
      await _frames(tester);
      await tester.tap(find.text('Discard capture'));
      await _until(tester, () => !harness.services.capture.hasPendingCapture);
      expect(await tester.runAsync(native.exists), isFalse);
      expect(server.uploads, 1);
      expect(find.text('Finishing upload'), findsOneWidget);
      network.online = false;
      server.responseGate!.complete();
      await _until(tester, () => !harness.services.uploads.isRunning);
      await tester.pumpWidget(const SizedBox.shrink());
      await _frames(tester);
    },
  );
}

// Bounded pumps allow real filesystem/Drift callbacks without waiting for the
// deliberately running indeterminate progress indicators to settle.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150; i++) {
    if (ready()) {
      await _frames(tester);
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue, reason: 'Activity did not reach its expected state.');
}

final class _Intake implements ShareIntake {
  Completer<List<SharedBatch>>? pendingGate;
  Completer<List<SharedBatch>>? _activePending;
  List<SharedBatch> batches = [];
  final discarded = <String>[];
  @override
  Stream<void> get events => const Stream.empty();
  @override
  Future<List<SharedBatch>> pending() async {
    final gate = pendingGate;
    pendingGate = null;
    if (gate != null) {
      _activePending = gate;
      try {
        return await gate.future;
      } finally {
        _activePending = null;
      }
    }
    final result = batches;
    batches = [];
    return result;
  }

  @override
  Future<String?> pick(String source, String batchId) async => null;

  @override
  Future<void> discard(String batchId) async => discarded.add(batchId);
  void release() {
    for (final gate in [pendingGate, _activePending]) {
      if (gate != null && !gate.isCompleted) gate.complete([]);
    }
  }
}

final class _Network implements NetworkMonitor {
  bool online = true;
  final _changes = StreamController<bool>.broadcast();
  @override
  Stream<bool> get changes => _changes.stream;
  @override
  Future<bool> isOnline() async => online;
  Future<void> close() => _changes.close();
}

// Only native intake and the wire transport are simulated. Acceptance, retry,
// processing, receipts, payload deletion and list refresh use production code.
final class _Server {
  late int size;
  late String digest;
  int uploads = 0;
  int receivedBytes = 0;
  int archiveReads = 0;
  int taskReads = 0;
  int uploadStatus = 201;
  int taskStatus = 200;
  String taskState = 'pending';
  bool deduplicated = false;
  bool completed = false;
  Completer<void>? payloadGate;
  Completer<void>? responseGate;
  Completer<void>? tasksGate;
  final payloadStarted = Completer<void>();
  final bodyReceived = Completer<void>();
  final tasksStarted = Completer<void>();

  http.Client client() => MockClient.streaming((request, body) async {
    if (request.method == 'POST' && request.url.path == '/api/documents/') {
      uploads++;
      await for (final chunk in body) {
        receivedBytes += chunk.length;
        if (chunk.length > 8192 && !payloadStarted.isCompleted) {
          payloadStarted.complete();
          await payloadGate?.future;
        }
      }
      if (!bodyReceived.isCompleted) bodyReceived.complete();
      if (responseGate case final gate?) {
        await Future.any<void>([
          gate.future,
          if (request case http.Abortable(:final abortTrigger?))
            abortTrigger.then<void>(
              (_) => throw http.RequestAbortedException(request.url),
            ),
        ]);
      }
      if (uploadStatus != 201) {
        return _stream(
          http.Response(
            jsonEncode({
              'code': 'invalid_document',
              'message': 'Rejected by archive policy',
            }),
            uploadStatus,
            headers: {
              'content-type': 'application/json',
              'x-request-id': 'upload-rejection-1',
            },
          ),
        );
      }
      return _stream(
        http.Response(
          jsonEncode({
            'id': 93,
            'sha256': digest,
            'size': size,
            'mime_type': 'application/pdf',
            'title': 'Newly uploaded invoice',
            'deduplicated': deduplicated,
          }),
          deduplicated ? 200 : 201,
          headers: {
            'content-type': 'application/json',
            'location': '/api/documents/93',
          },
        ),
      );
    }
    await body.drain<void>();
    if (request.url.path == '/api/tasks/') {
      taskReads++;
      if (!tasksStarted.isCompleted) tasksStarted.complete();
      await tasksGate?.future;
      if (taskStatus != 200) {
        return _stream(
          jsonResponse({
            'code': 'temporarily_unavailable',
            'message': 'Try again later',
          }, status: taskStatus),
        );
      }
      return _stream(
        jsonResponse({
          'counts': {
            'pending': taskState == 'pending' ? 1 : 0,
            'running': 0,
            'done': taskState == 'done' ? 1 : 0,
            'dead': taskState == 'dead' ? 1 : 0,
          },
          'results': [
            {
              'id': 44,
              'kind': 'post-ingest',
              'state': taskState,
              'attempts': 1,
              'doc_id': 93,
              'created_at': 1,
              'updated_at': 2,
              if (taskState == 'dead') 'last_error': 'OCR failed',
            },
          ],
        }),
      );
    }
    if (request.url.path == '/api/documents/93') {
      completed = true;
      final detail = jsonDecode(
        fixtureResponse('document-detail.json').body,
      ) as Map<String, dynamic>;
      detail['id'] = 93;
      detail['title'] = 'Newly uploaded invoice';
      return _stream(jsonResponse(detail));
    }
    if (request.url.path == '/api/documents/') {
      if (request.url.queryParameters.containsKey('split_origin_id')) {
        return _stream(jsonResponse({'count': 0, 'results': <Object>[]}));
      }
      archiveReads++;
      final page = jsonDecode(
        fixtureResponse('documents-page.json').body,
      ) as Map<String, dynamic>;
      if (completed) {
        (page['results'] as List<dynamic>).insert(0, {
          'id': 93,
          'title': 'Newly uploaded invoice',
          'mime_type': 'application/pdf',
          'created_at': 1,
          'updated_at': 2,
          'tags': <String>[],
          'correspondents': <String>[],
        });
        page['count'] = (page['count'] as int) + 1;
      }
      return _stream(jsonResponse(page));
    }
    return _stream(archiveResponse(http.Request(request.method, request.url)));
  });

  void release() {
    for (final gate in [payloadGate, responseGate, tasksGate]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
  }
}

http.StreamedResponse _stream(http.Response response) => http.StreamedResponse(
  Stream.value(response.bodyBytes),
  response.statusCode,
  headers: response.headers,
);
