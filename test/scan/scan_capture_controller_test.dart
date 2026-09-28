import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:suchi_companion/auth/account_identity.dart';
import 'package:suchi_companion/scan/intake_limits.dart';
import 'package:suchi_companion/scan/scan_capture_controller.dart';
import 'package:suchi_companion/scan/scan_database.dart';
import 'package:suchi_companion/scan/native_capture_store.dart';
import 'package:suchi_companion/scan/scan_queue_store.dart';
import 'package:suchi_companion/scan/scanner_bridge.dart';
import 'package:suchi_companion/scan/storage_protection.dart';

final _origin = Uri.parse('https://suchi.example.com');
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  late Directory temporary;
  late ScanDatabase database;
  late ScanQueueStore queue;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('suchi-capture-test-');
    database = ScanDatabase(NativeDatabase.memory());
    queue = await ScanQueueStore.open(
      database: database,
      root: Directory(path.join(temporary.path, 'queue')),
      storageProtection: const _NoopProtection(),
      storageCapacity: const _NoopProtection(),
    );
  });

  tearDown(() async {
    await queue.close();
    await database.close();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('composes pages, freezes OCR, stages, then discards capture', () async {
    final captureDirectory = Directory(
      path.join(temporary.path, 'native', 'one'),
    );
    await captureDirectory.create(recursive: true);
    final first = File(path.join(captureDirectory.path, 'page-000.png'));
    final second = File(path.join(captureDirectory.path, 'page-001.png'));
    await first.writeAsBytes(_png, flush: true);
    await second.writeAsBytes(_png, flush: true);
    final scanner = _FakeScanner(
      CaptureResult(
        cancelled: false,
        pageCount: 2,
        pages: [
          CapturedPage(path: first.path),
          CapturedPage(path: second.path),
        ],
        pdfPath: null,
      ),
      recognized: [
        RecognizedPage(
          path: first.path,
          text: 'First page',
          confidence: 0.9,
          language: 'en-US',
          errorCode: null,
        ),
        RecognizedPage(
          path: second.path,
          text: 'Second page',
          confidence: 0.8,
          language: 'en-US',
          errorCode: null,
        ),
      ],
    );
    final controller = ScanCaptureController(
      scanner: scanner,
      queue: queue,
      currentIdentity: () =>
          AccountIdentity(origin: _origin, userId: 7, systemId: 1),
      now: () => DateTime(2026, 6, 2, 15, 4, 5),
    );

    final staged = await controller.captureAndStage();

    expect(controller.state, ScanCaptureState.complete);
    expect(staged?.state, 'queued');
    expect(staged?.source, 'camera');
    expect(staged?.pageCount, 2);
    expect(staged?.filename, 'Scan 2026-06-02 15-04.pdf');
    expect(staged?.ocrConfidence, closeTo(0.847619, 0.000001));
    expect(await queue.readOcr(staged!), 'First page\n\nSecond page');
    final payload = await queue.payloadFile(staged).readAsBytes();
    expect(payload.take(4), '%PDF'.codeUnits);
    expect(scanner.discarded, isTrue);
    expect(await captureDirectory.exists(), isFalse);
    controller.dispose();
  });

  test('retries a failed capture only for its original identity', () async {
    final captureDirectory = Directory(
      path.join(temporary.path, 'native', 'two'),
    );
    await captureDirectory.create(recursive: true);
    final pdf = File(path.join(captureDirectory.path, 'document.pdf'));
    final page = File(path.join(captureDirectory.path, 'page-000.png'));
    await pdf.writeAsString('not a pdf', flush: true);
    await page.writeAsBytes(_png, flush: true);
    var deviceOcrEnabled = true;
    final scanner = _FakeScanner(
      CaptureResult(
        cancelled: false,
        pageCount: 1,
        pages: [CapturedPage(path: page.path)],
        pdfPath: pdf.path,
      ),
      recognized: [
        RecognizedPage(
          path: page.path,
          text: 'Do not retain after the setting changes',
          confidence: 0.9,
          language: 'en-US',
        ),
      ],
    );
    var identity = AccountIdentity(origin: _origin, userId: 7, systemId: 1);
    final controller = ScanCaptureController(
      scanner: scanner,
      queue: queue,
      currentIdentity: () => identity,
      deviceOcrEnabled: () => deviceOcrEnabled,
    );

    expect(await controller.captureAndStage(mode: CaptureMode.photo), isNull);
    expect(scanner.captureMode, CaptureMode.photo);
    expect(controller.state, ScanCaptureState.failed);
    expect(controller.hasPendingCapture, isTrue);
    expect(scanner.discarded, isFalse);

    deviceOcrEnabled = false;
    identity = AccountIdentity(origin: _origin, userId: 7, systemId: 2);
    await pdf.writeAsBytes('%PDF-1.4\n'.codeUnits, flush: true);
    final staged = await controller.retryPending();

    expect(staged?.state, 'queued');
    expect(staged?.identityUserId, 7);
    expect(staged?.identitySystemId, 1);
    expect(staged?.ocrContentPath, isNull);
    expect(scanner.recognitionCalls, 1);
    expect(controller.state, ScanCaptureState.complete);
    expect(scanner.discarded, isTrue);
    controller.dispose();
  });

  test('clears a failed capture presentation when identity changes', () async {
    final captureDirectory = Directory(
      path.join(temporary.path, 'native', 'identity-change'),
    );
    await captureDirectory.create(recursive: true);
    final pdf = File(path.join(captureDirectory.path, 'document.pdf'));
    await pdf.writeAsString('not a pdf', flush: true);
    final scanner = _FakeScanner(
      CaptureResult(
        cancelled: false,
        pageCount: 1,
        pages: const [],
        pdfPath: pdf.path,
      ),
    );
    final controller = ScanCaptureController(
      scanner: scanner,
      queue: queue,
      currentIdentity: () =>
          AccountIdentity(origin: _origin, userId: 7, systemId: 1),
      deviceOcrEnabled: () => false,
    );

    expect(await controller.captureAndStage(), isNull);
    expect(controller.hasPendingCapture, isTrue);

    controller.concealForIdentityTransition();

    expect(controller.state, ScanCaptureState.idle);
    expect(controller.hasPendingCapture, isFalse);
    expect(controller.staged, isNull);
    expect(await captureDirectory.exists(), isTrue);
    controller.dispose();
  });

  test(
    'retries the failed capture phase without replacing native files',
    () async {
      final captureDirectory = Directory(
        path.join(temporary.path, 'native', 'phase-retry'),
      );
      await captureDirectory.create(recursive: true);
      final pdf = File(path.join(captureDirectory.path, 'document.pdf'));
      final page = File(path.join(captureDirectory.path, 'page-000.png'));
      await pdf.writeAsBytes('%PDF-1.4\n'.codeUnits, flush: true);
      await page.writeAsBytes(_png, flush: true);
      final scanner = _FakeScanner(
        CaptureResult(
          cancelled: false,
          pageCount: 1,
          pages: [CapturedPage(path: page.path)],
          pdfPath: pdf.path,
        ),
        recognized: [
          RecognizedPage(
            path: page.path,
            text: 'Recovered text',
            confidence: 0.9,
            language: 'en-US',
          ),
        ],
        recognitionFailures: 1,
      );
      final controller = ScanCaptureController(
        scanner: scanner,
        queue: queue,
        currentIdentity: () => null,
      );

      expect(await controller.captureAndStage(), isNull);
      expect(controller.state, ScanCaptureState.failed);
      expect(controller.hasPendingCapture, isTrue);
      expect(scanner.captureCalls, 1);

      expect(await controller.captureAndStage(), isNull);
      expect(scanner.captureCalls, 1);

      final staged = await controller.retryPending();

      expect(staged, isNotNull);
      expect(scanner.recognitionCalls, 2);
      expect(await queue.readOcr(staged!), 'Recovered text');
      expect(scanner.discarded, isTrue);
      controller.dispose();
    },
  );

  test('omits OCR that Android reports as unavailable', () async {
    final captureDirectory = Directory(
      path.join(temporary.path, 'native', 'android'),
    );
    await captureDirectory.create(recursive: true);
    final pdf = File(path.join(captureDirectory.path, 'document.pdf'));
    final page = File(path.join(captureDirectory.path, 'page-000.png'));
    await pdf.writeAsBytes('%PDF-1.4\n'.codeUnits, flush: true);
    await page.writeAsBytes(_png, flush: true);
    final scanner = _FakeScanner(
      CaptureResult(
        cancelled: false,
        pageCount: 1,
        pages: [CapturedPage(path: page.path)],
        pdfPath: pdf.path,
      ),
      recognized: [
        RecognizedPage(
          path: page.path,
          text: 'Android text',
          confidence: null,
          language: null,
          errorCode: 'recognition_unavailable',
        ),
      ],
    );
    final controller = ScanCaptureController(
      scanner: scanner,
      queue: queue,
      currentIdentity: () => null,
    );

    final staged = await controller.captureAndStage();

    expect(staged?.ocrContentPath, isNull);
    expect(staged?.ocrConfidence, isNull);
    expect(scanner.recognitionCalls, 1);
    controller.dispose();
  });

  test('server-only OCR mode skips device recognition', () async {
    final captureDirectory = Directory(
      path.join(temporary.path, 'native', 'server-only'),
    );
    await captureDirectory.create(recursive: true);
    final pdf = File(path.join(captureDirectory.path, 'document.pdf'));
    final page = File(path.join(captureDirectory.path, 'page-000.png'));
    await pdf.writeAsBytes('%PDF-1.4\n'.codeUnits, flush: true);
    await page.writeAsBytes(_png, flush: true);
    final scanner = _FakeScanner(
      CaptureResult(
        cancelled: false,
        pageCount: 1,
        pages: [CapturedPage(path: page.path)],
        pdfPath: pdf.path,
      ),
    );
    final controller = ScanCaptureController(
      scanner: scanner,
      queue: queue,
      currentIdentity: () => null,
      deviceOcrEnabled: () => false,
    );

    final staged = await controller.captureAndStage();

    expect(staged?.ocrContentPath, isNull);
    expect(scanner.recognitionCalls, 0);
    controller.dispose();
  });

  test(
    'recovers a native capture into the durable queue after restart',
    () async {
      final nativeRoot = Directory(
        path.join(temporary.path, 'native-recovery'),
      );
      final captureDirectory = Directory(path.join(nativeRoot.path, 'capture'));
      await captureDirectory.create(recursive: true);
      final pdf = File(path.join(captureDirectory.path, 'document.pdf'));
      await pdf.writeAsBytes('%PDF-1.4\n'.codeUnits, flush: true);
      final createdAt = DateTime.utc(2026, 9, 2, 12, 30);
      await File(path.join(captureDirectory.path, nativeCaptureManifestName))
          .writeAsString(
            jsonEncode({
              'version': nativeCaptureManifestVersion,
              'created_at': createdAt.millisecondsSinceEpoch,
              'page_count': 1,
              'pdf_path': 'document.pdf',
              'pages': <String>[],
            }),
            flush: true,
          );
      final capture = CaptureResult(
        cancelled: false,
        pageCount: 1,
        pages: const [],
        pdfPath: pdf.path,
      );
      final scanner = _FakeScanner(capture);
      final controller = ScanCaptureController(
        scanner: scanner,
        queue: queue,
        nativeCaptures: NativeCaptureStore(nativeRoot),
        currentIdentity: () =>
            AccountIdentity(origin: _origin, userId: 7, systemId: 1),
      );

      final recovery = controller.recoverPending();
      expect(await controller.recoverPending(), 0);
      expect(await recovery, 1);

      final uploads = await queue.allUploads();
      expect(uploads, hasLength(1));
      expect(
        uploads.single.sourceMtime,
        createdAt.millisecondsSinceEpoch ~/ 1000,
      );
      expect(uploads.single.state, 'unassigned');
      expect(await captureDirectory.exists(), isFalse);
      controller.dispose();
    },
  );

  for (final spelling in ['native path', 'resolved path', 'directory alias']) {
    test(
      'a committed $spelling capture receipt prevents duplicate restart staging',
      () async {
        final nativeRoot = Directory(
          path.join(temporary.path, 'native-receipt'),
        );
        final captureDirectory = Directory(
          path.join(nativeRoot.path, 'capture'),
        );
        await captureDirectory.create(recursive: true);
        final pdf = File(path.join(captureDirectory.path, 'document.pdf'));
        await pdf.writeAsBytes('%PDF-1.4\n'.codeUnits, flush: true);
        var nativePdfPath = pdf.path;
        if (spelling == 'resolved path') {
          nativePdfPath = await pdf.resolveSymbolicLinks();
        } else if (spelling == 'directory alias') {
          final alias = Link(path.join(temporary.path, 'native-alias'));
          await alias.create(await nativeRoot.resolveSymbolicLinks());
          nativePdfPath = path.join(alias.path, 'capture', 'document.pdf');
        }
        await File(path.join(captureDirectory.path, nativeCaptureManifestName))
            .writeAsString(
              jsonEncode({
                'version': nativeCaptureManifestVersion,
                'created_at': DateTime.now().millisecondsSinceEpoch,
                'page_count': 1,
                'pdf_path': 'document.pdf',
                'pages': <String>[],
              }),
              flush: true,
            );
        final capture = CaptureResult(
          cancelled: false,
          pageCount: 1,
          pages: const [],
          pdfPath: nativePdfPath,
        );
        final firstScanner = _FakeScanner(capture, discardFailures: 1);
        final firstController = ScanCaptureController(
          scanner: firstScanner,
          queue: queue,
          currentIdentity: () => null,
        );

        final staged = await firstController.captureAndStage();

        expect(staged, isNotNull);
        expect(firstController.warningMessage, isNotNull);
        expect(await captureDirectory.exists(), isTrue);
        expect(await queue.allUploads(), hasLength(1));
        firstController.dispose();

        final recoveryScanner = _FakeScanner(capture);
        final recoveryController = ScanCaptureController(
          scanner: recoveryScanner,
          queue: queue,
          nativeCaptures: NativeCaptureStore(nativeRoot),
          currentIdentity: () => null,
        );

        expect(await recoveryController.recoverPending(), 0);
        expect(await queue.allUploads(), hasLength(1));
        expect(await captureDirectory.exists(), isFalse);
        expect(recoveryScanner.discarded, isTrue);
        recoveryController.dispose();
      },
    );
  }

  test(
    'receipt validation refuses a linked file without touching its target',
    () async {
      final captureDirectory = Directory(
        path.join(temporary.path, 'linked-capture'),
      );
      await captureDirectory.create();
      final outside = File(path.join(temporary.path, 'outside.pdf'));
      await outside.writeAsBytes('%PDF-1.4\n'.codeUnits, flush: true);
      final linkedPdf = Link(path.join(captureDirectory.path, 'document.pdf'));
      await linkedPdf.create(outside.path);
      final scanner = _FakeScanner(
        CaptureResult(
          cancelled: false,
          pageCount: 1,
          pages: const [],
          pdfPath: linkedPdf.path,
        ),
      );
      final controller = ScanCaptureController(
        scanner: scanner,
        queue: queue,
        currentIdentity: () => null,
      );
      addTearDown(controller.dispose);

      expect(await controller.captureAndStage(), isNull);
      expect(controller.errorCode, 'scan_storage_failed');
      expect(controller.hasPendingCapture, isFalse);
      expect(await queue.allUploads(), isEmpty);
      expect(scanner.discarded, isFalse);
      expect(await outside.readAsString(), '%PDF-1.4\n');
    },
  );

  test('returns to idle without staging when capture is cancelled', () async {
    final scanner = _FakeScanner(
      const CaptureResult(
        cancelled: true,
        pageCount: 0,
        pages: [],
        pdfPath: null,
      ),
    );
    final controller = ScanCaptureController(
      scanner: scanner,
      queue: queue,
      currentIdentity: () => null,
    );

    expect(await controller.captureAndStage(), isNull);
    expect(controller.state, ScanCaptureState.idle);
    expect((await database.allUploads()), isEmpty);
    expect(scanner.discarded, isFalse);
    controller.dispose();
  });

  test('rejects an oversized native PDF before queue staging', () async {
    final captureDirectory = Directory(
      path.join(temporary.path, 'native', 'oversized'),
    );
    await captureDirectory.create(recursive: true);
    final pdf = File(path.join(captureDirectory.path, 'document.pdf'));
    final handle = await pdf.open(mode: FileMode.writeOnly);
    await handle.writeFrom('%PDF-1.4\n'.codeUnits);
    await handle.truncate(maximumDocumentBytes + 1);
    await handle.close();
    final scanner = _FakeScanner(
      CaptureResult(
        cancelled: false,
        pageCount: 1,
        pages: const [],
        pdfPath: pdf.path,
      ),
    );
    final controller = ScanCaptureController(
      scanner: scanner,
      queue: queue,
      currentIdentity: () => null,
      deviceOcrEnabled: () => false,
    );

    expect(await controller.captureAndStage(), isNull);
    expect(controller.errorCode, 'capture_too_large');
    expect(controller.hasPendingCapture, isTrue);
    expect(controller.canRetryPending, isFalse);
    expect(await controller.retryPending(), isNull);
    expect(await queue.allUploads(), isEmpty);
    controller.dispose();
  });
}

final class _FakeScanner implements DocumentScanner {
  _FakeScanner(
    this.result, {
    this.recognized = const [],
    this.recognitionFailures = 0,
    this.discardFailures = 0,
  });

  final CaptureResult result;
  final List<RecognizedPage> recognized;
  int recognitionFailures;
  int discardFailures;
  bool discarded = false;
  int captureCalls = 0;
  CaptureMode? captureMode;
  int recognitionCalls = 0;

  @override
  Future<CaptureResult> capture({
    CaptureMode mode = CaptureMode.scanner,
  }) async {
    captureCalls++;
    captureMode = mode;
    return result;
  }

  @override
  Future<void> discardCapture(CaptureResult capture) async {
    if (discardFailures > 0) {
      discardFailures--;
      throw const ScannerFailure(
        code: 'capture_cleanup_failed',
        message: 'Captured files could not be removed.',
        retryable: true,
      );
    }
    discarded = true;
    final firstPath = capture.pages.firstOrNull?.path ?? capture.pdfPath;
    if (firstPath != null) {
      final directory = File(firstPath).parent;
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  @override
  Future<void> openSettings() async {}

  @override
  Future<List<RecognizedPage>> recognizeText(List<String> paths) async {
    recognitionCalls++;
    if (recognitionFailures > 0) {
      recognitionFailures--;
      throw const ScannerFailure(
        code: 'recognition_failed',
        message: 'Text recognition failed.',
        retryable: true,
      );
    }
    return recognized;
  }
}

final class _NoopProtection implements StorageProtection, StorageCapacity {
  const _NoopProtection();

  @override
  Future<int> availableBytes(String absolutePath) async => 1 << 60;

  @override
  Future<void> protectDirectory(String absolutePath) async {}
}
