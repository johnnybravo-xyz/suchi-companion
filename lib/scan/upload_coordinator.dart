import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../auth/account_identity.dart';
import 'network_monitor.dart';
import 'scan_database.dart';
import 'scan_queue_store.dart';

final class UploadCoordinator extends ChangeNotifier {
  UploadCoordinator({
    required this._store,
    required this._network,
    required this._currentClient,
    required this._currentIdentity,
    required this._deviceOcrEnabled,
    required this._onUnauthorized,
    DateTime Function()? now,
    this.pollInterval = const Duration(seconds: 2),
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final ScanQueueStore _store;
  final NetworkMonitor _network;
  final SuchiClient? Function() _currentClient;
  final AccountIdentity? Function() _currentIdentity;
  final bool Function() _deviceOcrEnabled;
  final Future<void> Function(ApiException error) _onUnauthorized;
  final DateTime Function() _now;
  final Duration pollInterval;

  StreamSubscription<List<ScanUpload>>? _queueSubscription;
  StreamSubscription<bool>? _networkSubscription;
  Timer? _timer;
  Completer<void>? _abortUpload;
  Completer<void>? _idle;
  bool _active = false;
  bool _running = false;
  bool _rerun = false;
  bool _disposed = false;
  String? _activeUploadId;

  bool get isActive => _active;
  bool get isRunning => _running;
  String? get activeUploadId => _activeUploadId;

  Future<void> start() async {
    if (_queueSubscription != null) return;
    _queueSubscription = _store.watchUploads().listen(
      (_) => unawaited(processNow()),
    );
    _networkSubscription = _network.changes.listen((online) {
      if (online) unawaited(processNow());
    });
  }

  Future<void> resume() async {
    if (_disposed) return;
    _active = true;
    notifyListeners();
    await processNow();
  }

  Future<void> pause() async {
    _active = false;
    _timer?.cancel();
    _timer = null;
    final abort = _abortUpload;
    if (abort != null && !abort.isCompleted) abort.complete();
    notifyListeners();
    await _idle?.future;
  }

  Future<void> processNow() async {
    if (_disposed || !_active) return;
    _timer?.cancel();
    _timer = null;
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    _idle = Completer<void>();
    notifyListeners();
    try {
      do {
        _rerun = false;
        await _drainReady();
      } while (_rerun && _active && !_disposed);
    } finally {
      _running = false;
      _activeUploadId = null;
      _idle?.complete();
      _idle = null;
      notifyListeners();
    }
  }

  Future<void> retry(String id) async {
    final upload = await _store.database.uploadById(id);
    if (upload == null ||
        upload.state != 'uploadFailed' && upload.state != 'processingFailed') {
      return;
    }
    final retryState = upload.state == 'processingFailed'
        ? 'processingServer'
        : 'queued';
    final now = _now().millisecondsSinceEpoch;
    await (_store.database.update(
      _store.database.scanUploads,
    )..where((row) => row.id.equals(id))).write(
      ScanUploadsCompanion(
        state: Value(retryState),
        bytesSent: const Value(0),
        nextAttemptAtMs: const Value(null),
        lastErrorCode: const Value(null),
        lastErrorMessage: const Value(null),
        requestId: const Value(null),
        completedAtMs: const Value(null),
        updatedAtMs: Value(now),
      ),
    );
    await processNow();
  }

  Future<ScanUpload> restageConflict(String id) async {
    final identity = _currentIdentity();
    if (identity == null) {
      throw const QueueStageException(
        'signed_out',
        'Pair this device before staging the upload again.',
      );
    }
    final replacement = await _store.restageConflict(id, identity: identity);
    await processNow();
    return replacement;
  }

  Future<void> _drainReady() async {
    if (!_active || !await _network.isOnline()) return;
    final client = _currentClient();
    final identity = _currentIdentity();
    if (client == null || identity == null) return;

    while (_active && !_disposed) {
      final uploads = await _store.allUploads();
      final candidates = uploads
          .where(
            (upload) =>
                (upload.state == 'queued' ||
                    upload.state == 'processingServer') &&
                queueUploadBelongsToIdentity(upload, identity),
          )
          .toList(growable: false);
      final nowMs = _now().millisecondsSinceEpoch;
      ScanUpload? ready;
      int? nextWake;
      for (final upload in candidates) {
        final due = upload.nextAttemptAtMs;
        if (due == null || due <= nowMs) {
          ready = upload;
          break;
        }
        if (nextWake == null || due < nextWake) nextWake = due;
      }
      if (ready == null) {
        if (nextWake != null) _schedule(nextWake - nowMs);
        return;
      }
      if (ready.state == 'queued') {
        await _upload(client, ready);
      } else {
        await _pollProcessing(client, ready);
      }
      if (!await _network.isOnline()) return;
    }
  }

  Future<void> _upload(SuchiClient client, ScanUpload upload) async {
    _activeUploadId = upload.id;
    notifyListeners();
    if (!await _store.verifyPayload(upload)) {
      await _terminalFailure(
        upload,
        state: 'uploadFailed',
        code: 'payload_missing_or_changed',
        message: 'The staged document is missing or changed.',
      );
      return;
    }

    String? storedOcr;
    if (_deviceOcrEnabled()) {
      try {
        storedOcr = await _store.readOcr(upload);
      } on QueueStageException catch (error) {
        await _terminalFailure(
          upload,
          state: 'uploadFailed',
          code: error.code,
          message: error.message,
        );
        return;
      }
    }
    final attempt = upload.attemptCount + 1;
    final nowMs = _now().millisecondsSinceEpoch;
    await (_store.database.update(
      _store.database.scanUploads,
    )..where((row) => row.id.equals(upload.id))).write(
      ScanUploadsCompanion(
        state: const Value('uploading'),
        attemptCount: Value(attempt),
        bytesSent: const Value(0),
        nextAttemptAtMs: const Value(null),
        lastErrorCode: const Value(null),
        lastErrorMessage: const Value(null),
        requestId: const Value(null),
        completedAtMs: const Value(null),
        updatedAtMs: Value(nowMs),
      ),
    );

    // Re-check immediately before constructing the request so queued OCR is
    // not sent after the privacy setting changes while an item is offline.
    final ocr = _deviceOcrEnabled() ? storedOcr : null;
    final abort = Completer<void>();
    _abortUpload = abort;
    final progress = _ProgressWriter(
      database: _store.database,
      uploadId: upload.id,
      totalBytes: upload.byteSize,
      now: _now,
    );
    try {
      final result = await client.uploadDocument(
        file: _store.payloadFile(upload),
        byteSize: upload.byteSize,
        sha256Hex: upload.sha256,
        mimeType: upload.mimeType,
        filename: upload.filename,
        idempotencyKey: upload.id,
        sourceMtime: upload.sourceMtime,
        ocrContent: ocr,
        ocrConfidence: ocr == null ? null : upload.ocrConfidence,
        ocrLanguage: ocr == null ? null : upload.ocrLanguage,
        onProgress: progress.record,
        abortTrigger: abort.future,
      );
      await progress.flush();
      await _acceptUpload(upload, result);
    } on ApiException catch (error) {
      await _flushProgress(progress);
      await _handleApiFailure(upload, error, uploadAttempt: attempt);
    } catch (_) {
      await _flushProgress(progress);
      await _scheduleRetry(
        upload,
        uploadAttempt: attempt,
        code: 'unexpected_upload_failure',
        message: 'The upload stopped unexpectedly and will be tried again.',
      );
    } finally {
      if (identical(_abortUpload, abort)) _abortUpload = null;
    }
  }

  Future<void> _acceptUpload(ScanUpload upload, UploadResult result) async {
    final nowMs = _now().millisecondsSinceEpoch;
    final terminal = result.deduplicated || result.restored;
    final state = result.deduplicated
        ? 'duplicate'
        : result.restored
        ? 'filed'
        : 'processingServer';
    await (_store.database.update(
      _store.database.scanUploads,
    )..where((row) => row.id.equals(upload.id))).write(
      ScanUploadsCompanion(
        state: Value(state),
        bytesSent: Value(upload.byteSize),
        nextAttemptAtMs: Value(
          terminal ? null : nowMs + pollInterval.inMilliseconds,
        ),
        serverDocumentId: Value(result.id),
        splitOriginId: Value(result.id),
        deduplicated: Value(result.deduplicated),
        restored: Value(result.restored),
        lastErrorCode: const Value(null),
        lastErrorMessage: const Value(null),
        requestId: const Value(null),
        completedAtMs: Value(terminal ? nowMs : null),
        updatedAtMs: Value(nowMs),
      ),
    );
    await _store.deletePayloads(upload);
    if (terminal) await _store.cleanupCompleted(now: _now());
  }

  Future<void> _pollProcessing(SuchiClient client, ScanUpload upload) async {
    final documentId = upload.serverDocumentId;
    if (documentId == null) {
      await _terminalFailure(
        upload,
        state: 'processingFailed',
        code: 'missing_server_document',
        message: 'The accepted upload is missing its Suchi document id.',
      );
      return;
    }
    try {
      final tasks = await client.tasksForDocument(documentId);
      final relevant = tasks.results
          .where(
            (task) =>
                task.documentId == documentId &&
                task.kind.startsWith('post-ingest'),
          )
          .toList(growable: false);
      final dead = relevant.where((task) => task.state == 'dead').firstOrNull;
      if (dead != null) {
        await _terminalFailure(
          upload,
          state: 'processingFailed',
          code: 'server_processing_failed',
          message: dead.lastError ?? 'Suchi could not process the document.',
          serverTaskId: dead.id,
        );
        return;
      }
      final active = relevant
          .where((task) => task.state == 'pending' || task.state == 'running')
          .firstOrNull;
      if (active != null) {
        await _scheduleProcessing(upload, serverTaskId: active.id);
        return;
      }

      final children = await client.splitDocuments(documentId);
      if (children.isNotEmpty) {
        for (final child in children) {
          final childTasks = await client.tasksForDocument(child.id);
          final childDead = childTasks.results
              .where((task) => task.state == 'dead')
              .firstOrNull;
          if (childDead != null) {
            await _terminalFailure(
              upload,
              state: 'processingFailed',
              code: 'split_processing_failed',
              message:
                  childDead.lastError ??
                  'Suchi could not process a split document.',
              serverTaskId: childDead.id,
            );
            return;
          }
          if (childTasks.results.any(
            (task) => task.state == 'pending' || task.state == 'running',
          )) {
            await _scheduleProcessing(upload);
            return;
          }
        }
        await _completeProcessing(
          upload,
          splitDocumentIds: children.map((child) => child.id).toList(),
        );
        return;
      }

      final detail = await client.document(documentId);
      if (detail.trashedAt != null) {
        await _terminalFailure(
          upload,
          state: 'processingFailed',
          code: 'split_documents_missing',
          message: 'The split documents are no longer available.',
        );
        return;
      }
      await _completeProcessing(upload);
    } on ApiException catch (error) {
      await _handleApiFailure(
        upload,
        error,
        uploadAttempt: upload.attemptCount,
      );
    } catch (_) {
      await _scheduleRetry(
        upload,
        uploadAttempt: upload.attemptCount,
        code: 'unexpected_processing_failure',
        message: 'The server status check stopped unexpectedly and will retry.',
      );
    }
  }

  Future<void> _scheduleProcessing(
    ScanUpload upload, {
    int? serverTaskId,
  }) async {
    final nowMs = _now().millisecondsSinceEpoch;
    await (_store.database.update(
      _store.database.scanUploads,
    )..where((row) => row.id.equals(upload.id))).write(
      ScanUploadsCompanion(
        state: const Value('processingServer'),
        serverTaskId: Value(serverTaskId),
        nextAttemptAtMs: Value(nowMs + pollInterval.inMilliseconds),
        updatedAtMs: Value(nowMs),
      ),
    );
  }

  Future<void> _completeProcessing(
    ScanUpload upload, {
    List<int> splitDocumentIds = const [],
  }) async {
    final nowMs = _now().millisecondsSinceEpoch;
    await (_store.database.update(
      _store.database.scanUploads,
    )..where((row) => row.id.equals(upload.id))).write(
      ScanUploadsCompanion(
        state: const Value('filed'),
        split: Value(splitDocumentIds.isNotEmpty),
        splitDocumentIds: Value(
          splitDocumentIds.isEmpty ? null : jsonEncode(splitDocumentIds),
        ),
        nextAttemptAtMs: const Value(null),
        lastErrorCode: const Value(null),
        lastErrorMessage: const Value(null),
        completedAtMs: Value(nowMs),
        updatedAtMs: Value(nowMs),
      ),
    );
    await _store.cleanupCompleted(now: _now());
  }

  Future<void> _handleApiFailure(
    ScanUpload upload,
    ApiException error, {
    required int uploadAttempt,
  }) async {
    if (error.kind == ApiFailureKind.cancelled) {
      final nowMs = _now().millisecondsSinceEpoch;
      await (_store.database.update(
        _store.database.scanUploads,
      )..where((row) => row.id.equals(upload.id))).write(
        ScanUploadsCompanion(
          state: Value(
            upload.state == 'processingServer' ? 'processingServer' : 'queued',
          ),
          bytesSent: const Value(0),
          nextAttemptAtMs: const Value(null),
          updatedAtMs: Value(nowMs),
        ),
      );
      return;
    }
    if (error.expiresSession) {
      final nowMs = _now().millisecondsSinceEpoch;
      await (_store.database.update(
        _store.database.scanUploads,
      )..where((row) => row.id.equals(upload.id))).write(
        ScanUploadsCompanion(
          state: Value(
            upload.state == 'processingServer' ? 'processingServer' : 'queued',
          ),
          bytesSent: const Value(0),
          nextAttemptAtMs: const Value(null),
          lastErrorCode: Value(error.code ?? 'unauthorized'),
          lastErrorMessage: const Value('Pair this device to continue.'),
          requestId: Value(error.requestId),
          updatedAtMs: Value(nowMs),
        ),
      );
      unawaited(_onUnauthorized(error).onError((_, _) {}));
      return;
    }
    if (_isRetryable(error)) {
      await _scheduleRetry(
        upload,
        uploadAttempt: uploadAttempt,
        code: error.code ?? error.kind.name,
        message: error.message,
        requestId: error.requestId,
        retryAfter: error.retryAfter,
      );
      return;
    }
    await _terminalFailure(
      upload,
      state: upload.state == 'processingServer'
          ? 'processingFailed'
          : 'uploadFailed',
      code: error.code ?? error.kind.name,
      message: error.kind == ApiFailureKind.conflict
          ? 'This request key conflicts with an earlier upload. Stage it again to create a new key.'
          : error.message,
      requestId: error.requestId,
    );
  }

  Future<void> _scheduleRetry(
    ScanUpload upload, {
    required int uploadAttempt,
    required String code,
    required String message,
    String? requestId,
    Duration? retryAfter,
  }) async {
    final delay = _retryDelay(uploadAttempt, retryAfter);
    final nowMs = _now().millisecondsSinceEpoch;
    await (_store.database.update(
      _store.database.scanUploads,
    )..where((row) => row.id.equals(upload.id))).write(
      ScanUploadsCompanion(
        state: Value(
          upload.state == 'processingServer' ? 'processingServer' : 'queued',
        ),
        bytesSent: const Value(0),
        nextAttemptAtMs: Value(nowMs + delay.inMilliseconds),
        lastErrorCode: Value(code),
        lastErrorMessage: Value(message),
        requestId: Value(requestId),
        updatedAtMs: Value(nowMs),
      ),
    );
  }

  Future<void> _flushProgress(_ProgressWriter progress) async {
    try {
      await progress.flush();
    } catch (_) {
      // The retry state is authoritative; stale progress is disposable.
    }
  }

  Future<void> _terminalFailure(
    ScanUpload upload, {
    required String state,
    required String code,
    required String message,
    String? requestId,
    int? serverTaskId,
  }) async {
    final nowMs = _now().millisecondsSinceEpoch;
    await (_store.database.update(
      _store.database.scanUploads,
    )..where((row) => row.id.equals(upload.id))).write(
      ScanUploadsCompanion(
        state: Value(state),
        bytesSent: const Value(0),
        nextAttemptAtMs: const Value(null),
        lastErrorCode: Value(code),
        lastErrorMessage: Value(message),
        requestId: Value(requestId),
        serverTaskId: Value(serverTaskId),
        completedAtMs: Value(nowMs),
        updatedAtMs: Value(nowMs),
      ),
    );
    await _store.cleanupCompleted(now: _now());
  }

  void _schedule(int delayMilliseconds) {
    if (!_active || _disposed) return;
    final delay = Duration(milliseconds: delayMilliseconds.clamp(1, 1 << 31));
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(processNow()));
  }

  static bool _isRetryable(ApiException error) =>
      error.kind == ApiFailureKind.network ||
      error.kind == ApiFailureKind.timeout ||
      error.kind == ApiFailureKind.server ||
      error.statusCode == 408 ||
      error.statusCode == 429;

  static Duration _retryDelay(int attempt, Duration? retryAfter) {
    if (retryAfter != null) {
      const maximum = Duration(days: 1);
      if (retryAfter > maximum) return maximum;
      return retryAfter;
    }
    const delays = [
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(minutes: 1),
      Duration(minutes: 5),
      Duration(minutes: 15),
      Duration(hours: 1),
    ];
    final index = (attempt - 1).clamp(0, delays.length - 1);
    return delays[index];
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _timer?.cancel();
    final abort = _abortUpload;
    if (abort != null && !abort.isCompleted) abort.complete();
    unawaited(_queueSubscription?.cancel());
    unawaited(_networkSubscription?.cancel());
    super.dispose();
  }
}

final class _ProgressWriter {
  _ProgressWriter({
    required this.database,
    required this.uploadId,
    required this.totalBytes,
    required this.now,
  });

  final ScanDatabase database;
  final String uploadId;
  final int totalBytes;
  final DateTime Function() now;

  Future<void> _tail = Future<void>.value();
  int _pendingBytes = 0;
  int _writtenBytes = 0;
  int _lastWriteMs = 0;

  void record(int bytes) {
    _pendingBytes = bytes;
    final nowMs = now().millisecondsSinceEpoch;
    if (bytes < totalBytes && nowMs - _lastWriteMs < 250) return;
    _enqueue(bytes, nowMs);
  }

  Future<void> flush() {
    if (_pendingBytes != _writtenBytes) {
      _enqueue(_pendingBytes, now().millisecondsSinceEpoch);
    }
    return _tail;
  }

  void _enqueue(int bytes, int nowMs) {
    if (bytes == _writtenBytes) return;
    _writtenBytes = bytes;
    _lastWriteMs = nowMs;
    _tail = _tail.then((_) async {
      await (database.update(database.scanUploads)..where(
            (row) => row.id.equals(uploadId) & row.state.equals('uploading'),
          ))
          .write(
            ScanUploadsCompanion(
              bytesSent: Value(bytes),
              updatedAtMs: Value(nowMs),
            ),
          );
    });
  }
}
