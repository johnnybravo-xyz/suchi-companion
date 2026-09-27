import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../auth/account_identity.dart';

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'scan_database.dart';
import 'intake_limits.dart';
import 'scan_queue_store.dart';
import 'native_capture_store.dart';
import 'scanner_bridge.dart';

enum ScanCaptureState {
  idle,
  capturing,
  processingPages,
  composingPdf,
  staging,
  complete,
  failed,
}

enum _PendingCapturePhase { recognizing, resolvingPdf, staging }

final class ScanCaptureController extends ChangeNotifier {
  ScanCaptureController({
    required this._scanner,
    required this._queue,
    required this._currentIdentity,
    this._nativeCaptures,
    bool Function()? deviceOcrEnabled,
    DateTime Function()? now,
  }) : _deviceOcrEnabled = deviceOcrEnabled ?? (() => true),
       _now = now ?? (() => DateTime.now().toUtc());

  final DocumentScanner _scanner;
  final ScanQueueStore _queue;
  final AccountIdentity? Function() _currentIdentity;
  final NativeCaptureStore? _nativeCaptures;
  final bool Function() _deviceOcrEnabled;
  final DateTime Function() _now;

  ScanCaptureState _state = ScanCaptureState.idle;
  CaptureResult? _pendingCapture;
  File? _pendingPdf;
  DeviceOcrInput? _pendingOcr;
  AccountIdentity? _pendingIdentity;
  String? _pendingCaptureReceiptId;
  _PendingCapturePhase? _pendingPhase;
  int? _sourceMtime;
  ScanUpload? _staged;
  String? _errorCode;
  String? _errorMessage;
  String? _warningMessage;
  bool _canOpenSettings = false;
  bool _pendingRetryable = true;
  bool _recovering = false;
  bool _concealAfterCurrentOperation = false;
  bool _disposed = false;

  ScanCaptureState get state => _state;
  ScanUpload? get staged => _staged;
  String? get errorCode => _errorCode;
  String? get errorMessage => _errorMessage;
  String? get warningMessage => _warningMessage;
  bool get canOpenSettings => _canOpenSettings;
  bool get hasPendingCapture => _pendingCapture != null;
  bool get canRetryPending => hasPendingCapture && _pendingRetryable;
  bool get isBusy => switch (_state) {
    ScanCaptureState.capturing ||
    ScanCaptureState.processingPages ||
    ScanCaptureState.composingPdf ||
    ScanCaptureState.staging => true,
    _ => false,
  };

  Future<int> recoverPending() async {
    final store = _nativeCaptures;
    if (store == null || isBusy || _pendingCapture != null || _recovering) {
      return 0;
    }
    _recovering = true;
    try {
      return await _recoverPending(store);
    } finally {
      _recovering = false;
    }
  }

  Future<int> _recoverPending(NativeCaptureStore store) async {
    final List<PendingNativeCapture> pending;
    try {
      pending = await store.recoverAll();
    } on FileSystemException catch (_) {
      _fail(
        'capture_recovery_failed',
        'Saved camera captures could not be recovered safely.',
      );
      return 0;
    }
    var recovered = 0;
    for (final item in pending) {
      if (isBusy || _pendingCapture != null) break;
      _resetMessages();
      _staged = null;
      final String receiptId;
      try {
        receiptId = await _captureReceiptId(item.capture);
      } on FileSystemException {
        _fail(
          'capture_recovery_failed',
          'A saved camera capture could not be read safely.',
        );
        break;
      }
      if (await _queue.hasCaptureReceipt(receiptId)) {
        try {
          await _scanner.discardCapture(item.capture);
        } on ScannerFailure {
          _warningMessage = 'A queued scan is safe, but temporary camera files still need cleanup.';
          _setState(ScanCaptureState.complete);
          break;
        }
        continue;
      }
      if (isBusy || _pendingCapture != null) break;
      _pendingCapture = item.capture;
      _pendingIdentity = null;
      _pendingCaptureReceiptId = receiptId;
      _pendingPhase = _PendingCapturePhase.recognizing;
      _sourceMtime = item.createdAt.millisecondsSinceEpoch ~/ 1000;
      try {
        await _resumePending();
        recovered++;
      } on ScannerFailure catch (error) {
        _fail(
          error.code,
          error.message,
          retryable: error.retryable,
          openSettings: error.openSettings,
        );
        break;
      } on QueueStageException catch (error) {
        _fail(
          error.code,
          error.message,
          retryable: error.code != 'payload_too_large',
        );
        break;
      } on FileSystemException catch (_) {
        _fail(
          'capture_recovery_failed',
          'A saved camera capture could not be prepared safely.',
        );
        break;
      } on Exception catch (_) {
        _fail(
          'capture_recovery_failed',
          'A saved camera capture could not be recovered.',
        );
        break;
      }
    }
    return recovered;
  }

  Future<ScanUpload?> captureAndStage({
    CaptureMode mode = CaptureMode.scanner,
  }) async {
    if (isBusy || _pendingCapture != null) return null;
    final captureIdentity = _currentIdentity();
    _resetMessages();
    _staged = null;
    _sourceMtime = _now().millisecondsSinceEpoch ~/ 1000;
    _setState(ScanCaptureState.capturing);
    try {
      final capture = await _scanner.capture(mode: mode);
      if (capture.cancelled) {
        _clearPending();
        _concealAfterCurrentOperation = false;
        _setState(ScanCaptureState.idle);
        return null;
      }
      final receiptId = await _captureReceiptId(capture);
      _pendingCapture = capture;
      _pendingIdentity = captureIdentity;
      _pendingCaptureReceiptId = receiptId;
      _pendingPhase = _PendingCapturePhase.recognizing;
      return await _resumePending();
    } on ScannerFailure catch (error) {
      _fail(
        error.code,
        error.message,
        retryable: error.retryable,
        openSettings: error.openSettings,
      );
    } on QueueStageException catch (error) {
      _fail(
        error.code,
        error.message,
        retryable: error.code != 'payload_too_large',
      );
    } on FileSystemException catch (_) {
      _fail(
        'scan_storage_failed',
        'The scanned document could not be prepared safely.',
      );
    } on Exception catch (_) {
      _fail('scan_failed', 'The scanned document could not be prepared.');
    }
    return null;
  }

  Future<ScanUpload?> retryPending() async {
    if (isBusy ||
        !canRetryPending ||
        _pendingCapture == null ||
        _pendingCaptureReceiptId == null ||
        _pendingPhase == null ||
        _sourceMtime == null) {
      return null;
    }
    _resetMessages();
    try {
      return await _resumePending();
    } on ScannerFailure catch (error) {
      _fail(
        error.code,
        error.message,
        retryable: error.retryable,
        openSettings: error.openSettings,
      );
    } on QueueStageException catch (error) {
      _fail(
        error.code,
        error.message,
        retryable: error.code != 'payload_too_large',
      );
    } on FileSystemException catch (_) {
      _fail('scan_storage_failed', 'The scan could not be stored safely.');
    }
    return null;
  }

  Future<void> discardPending() async {
    final capture = _pendingCapture;
    if (capture == null || isBusy) return;
    try {
      await _scanner.discardCapture(capture);
    } on ScannerFailure catch (error) {
      _fail(error.code, error.message, retryable: false);
      return;
    }
    _clearPending();
    _setState(ScanCaptureState.idle);
  }

  Future<void> openSettings() => _scanner.openSettings();

  void concealForIdentityTransition() {
    if (_disposed) return;
    _staged = null;
    _resetMessages();
    if (isBusy) {
      _concealAfterCurrentOperation = true;
      notifyListeners();
      return;
    }
    _clearPending();
    _concealAfterCurrentOperation = false;
    _setState(ScanCaptureState.idle);
  }

  Future<ScanUpload> _resumePending() async {
    final capture = _pendingCapture!;
    await _validateCaptureSize(capture);
    if (_pendingPhase == _PendingCapturePhase.recognizing) {
      _setState(ScanCaptureState.processingPages);
      _pendingOcr = await _recognize(capture);
      _pendingPhase = _PendingCapturePhase.resolvingPdf;
    }
    if (_pendingPhase == _PendingCapturePhase.resolvingPdf) {
      _pendingPdf = await _resolvePdf(capture);
      _pendingPhase = _PendingCapturePhase.staging;
    }
    return _stagePending();
  }

  Future<ScanUpload> _stagePending() async {
    final capture = _pendingCapture!;
    final pdf = _pendingPdf!;
    if (!_deviceOcrEnabled()) _pendingOcr = null;
    _setState(ScanCaptureState.staging);
    final capturedAt = DateTime.fromMillisecondsSinceEpoch(
      _sourceMtime! * 1000,
      isUtc: true,
    ).toLocal();
    final upload = await _queue.stage(
      StageDocumentInput(
        sourceFile: pdf,
        mimeType: 'application/pdf',
        filename:
            'Scan ${DateFormat('yyyy-MM-dd HH-mm').format(capturedAt)}.pdf',
        source: ScanSource.camera,
        pageCount: capture.pageCount,
        sourceMtime: _sourceMtime,
        ocr: _pendingOcr,
        identity: _pendingIdentity,
      ),
      captureReceiptId: _pendingCaptureReceiptId,
    );
    _staged = upload;
    try {
      await _scanner.discardCapture(capture);
    } on ScannerFailure catch (_) {
      _warningMessage =
          'The scan is queued, but temporary camera files need cleanup.';
    }
    _clearPending();
    if (_concealAfterCurrentOperation) {
      _concealAfterCurrentOperation = false;
      _staged = null;
      _resetMessages();
      _setState(ScanCaptureState.idle);
    } else {
      _setState(ScanCaptureState.complete);
    }
    return upload;
  }

  Future<DeviceOcrInput?> _recognize(CaptureResult capture) async {
    if (!_deviceOcrEnabled()) return null;
    final paths = capture.pages
        .map((page) => page.path)
        .toList(growable: false);
    if (paths.isEmpty) return null;
    final recognized = await _scanner.recognizeText(paths);
    final useful = recognized
        .where((page) => page.errorCode == null && page.text.trim().isNotEmpty)
        .toList(growable: false);
    if (useful.isEmpty) return null;
    if (useful.any((page) => page.confidence == null)) return null;
    final content = useful.map((page) => page.text.trim()).join('\n\n');
    if (utf8.encode(content).length > 1024 * 1024) return null;
    var weightedConfidence = 0.0;
    var characters = 0;
    for (final page in useful) {
      final length = page.text.runes.length;
      weightedConfidence += page.confidence! * length;
      characters += length;
    }
    final language = useful
        .map((page) => page.language)
        .whereType<String>()
        .where(
          (value) => RegExp(r'^[a-z]{2,3}(?:[-_][A-Z]{2})?$').hasMatch(value),
        )
        .firstOrNull;
    return DeviceOcrInput(
      content: content,
      confidence: characters == 0 ? 0 : weightedConfidence / characters,
      language: language ?? 'und',
    );
  }

  Future<File> _resolvePdf(CaptureResult capture) async {
    if (capture.pdfPath case final pdfPath?) {
      final pdf = File(pdfPath);
      if (await FileSystemEntity.type(pdf.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FileSystemException('Scanner PDF is not a regular file.');
      }
      return pdf;
    }
    if (capture.pages.isEmpty) {
      throw const FileSystemException('Scanner returned no pages.');
    }
    _setState(ScanCaptureState.composingPdf);
    final first = File(capture.pages.first.path);
    final directory = first.parent;
    final document = pw.Document(compress: true);
    var sourceBytes = 0;
    for (final page in capture.pages) {
      final imageFile = File(page.path);
      if (imageFile.parent.absolute.path != directory.absolute.path ||
          await FileSystemEntity.type(imageFile.path, followLinks: false) !=
              FileSystemEntityType.file) {
        throw const FileSystemException('Scanner page path is invalid.');
      }
      final bytes = await _readBounded(imageFile, maximumCapturePageBytes);
      sourceBytes += bytes.length;
      if (sourceBytes > maximumCaptureSourceBytes) {
        throw const ScannerFailure(
          code: 'capture_too_large',
          message: captureLimitMessage,
          retryable: false,
        );
      }
      final image = pw.MemoryImage(bytes);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) =>
              pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }
    final part = File(path.join(directory.path, 'composed.pdf.part'));
    final output = File(path.join(directory.path, 'composed.pdf'));
    final bytes = await document.save();
    if (bytes.length > maximumDocumentBytes) {
      throw const ScannerFailure(
        code: 'capture_too_large',
        message: captureLimitMessage,
        retryable: false,
      );
    }
    await _queue.ensureWritableCapacity(bytes.length);
    final handle = await part.open(mode: FileMode.writeOnly);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
    await part.rename(output.path);
    return output;
  }

  Future<void> _validateCaptureSize(CaptureResult capture) async {
    if (capture.pageCount > maximumCapturePages ||
        capture.pages.length > maximumCapturePages) {
      throw const ScannerFailure(
        code: 'capture_too_large',
        message: captureLimitMessage,
        retryable: false,
      );
    }
    if (capture.pdfPath case final pdfPath?) {
      final pdf = File(pdfPath);
      if (await FileSystemEntity.type(pdf.path, followLinks: false) ==
              FileSystemEntityType.file &&
          await pdf.length() > maximumDocumentBytes) {
        throw const ScannerFailure(
          code: 'capture_too_large',
          message: captureLimitMessage,
          retryable: false,
        );
      }
    }
    if (capture.pdfPath != null && !_deviceOcrEnabled()) return;

    var total = 0;
    for (final page in capture.pages) {
      final file = File(page.path);
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      final length = await file.length();
      total += length;
      if (length > maximumCapturePageBytes ||
          total > maximumCaptureSourceBytes) {
        throw const ScannerFailure(
          code: 'capture_too_large',
          message: captureLimitMessage,
          retryable: false,
        );
      }
    }
  }

  Future<Uint8List> _readBounded(File file, int maximumBytes) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > maximumBytes) {
        throw const ScannerFailure(
          code: 'capture_too_large',
          message: captureLimitMessage,
          retryable: false,
        );
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  void _fail(
    String code,
    String message, {
    bool retryable = true,
    bool openSettings = false,
  }) {
    if (_concealAfterCurrentOperation) {
      _concealAfterCurrentOperation = false;
      _clearPending();
      _staged = null;
      _resetMessages();
      _setState(ScanCaptureState.idle);
      return;
    }
    _errorCode = code;
    _errorMessage = message;
    _canOpenSettings = openSettings;
    _pendingRetryable = retryable;
    _setState(ScanCaptureState.failed);
  }

  void _resetMessages() {
    _errorCode = null;
    _errorMessage = null;
    _warningMessage = null;
    _canOpenSettings = false;
    _pendingRetryable = true;
  }

  void _clearPending() {
    _pendingCapture = null;
    _pendingPdf = null;
    _pendingOcr = null;
    _pendingIdentity = null;
    _pendingCaptureReceiptId = null;
    _pendingPhase = null;
    _sourceMtime = null;
    _pendingRetryable = true;
  }

  Future<String> _captureReceiptId(CaptureResult capture) async {
    final paths = <String>[
      ...capture.pages.map((page) => page.path),
      ?capture.pdfPath,
    ];
    if (paths.isEmpty) {
      throw const FileSystemException('Capture has no receipt path.');
    }
    // Native capture and restart recovery may spell the same system directory
    // differently (for example /var and /private/var on Apple platforms).
    final directory = await File(paths.first).parent.resolveSymbolicLinks();
    for (final value in paths) {
      if (await FileSystemEntity.type(value, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FileSystemException('Capture receipt file is unsafe.');
      }
      final resolved = await File(value).resolveSymbolicLinks();
      if (File(resolved).parent.path != directory) {
        throw const FileSystemException(
          'Capture files do not share a directory.',
        );
      }
    }
    return sha256.convert(utf8.encode(directory)).toString();
  }

  void _setState(ScanCaptureState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
