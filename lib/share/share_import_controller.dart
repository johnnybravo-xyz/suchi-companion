import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../auth/account_identity.dart';
import '../scan/scan_queue_store.dart';
import 'share_bridge.dart';

enum ShareImportPhase { idle, checking, staging }

final class ShareImportSummary {
  const ShareImportSummary({
    required this.staged,
    required this.alreadyStaged,
    required this.rejected,
    required this.failed,
  });

  final int staged;
  final int alreadyStaged;
  final int rejected;
  final int failed;
}

final class ShareImportController extends ChangeNotifier {
  ShareImportController({
    required this._intake,
    required this._queue,
    required this._currentIdentity,
  });

  static const _emptySummary = ShareImportSummary(
    staged: 0,
    alreadyStaged: 0,
    rejected: 0,
    failed: 0,
  );
  static const _importError =
      'Shared documents could not be imported. Try again.';

  final ShareIntake _intake;
  final ScanQueueStore _queue;
  final AccountIdentity? Function() _currentIdentity;

  StreamSubscription<void>? _subscription;
  Future<ShareImportSummary>? _inFlight;
  Future<void>? _closeFuture;
  bool _pendingRun = false;
  bool _closing = false;
  bool _disposed = false;
  int _presentationGeneration = 0;
  ShareImportPhase _phase = ShareImportPhase.idle;
  ShareImportSummary? _lastSummary;
  String? _errorMessage;

  bool get isRunning => _inFlight != null;
  ShareImportPhase get phase => _phase;
  ShareImportSummary? get lastSummary => _lastSummary;
  String? get errorMessage => _errorMessage;

  Future<void> start() async {
    if (_closing || _subscription != null) return;
    try {
      _subscription = _intake.events.listen(
        (_) => unawaited(processPending()),
        onError: (Object error, StackTrace stackTrace) {
          if (_closing) return;
          _errorMessage = _importError;
          _notify();
        },
      );
    } catch (_) {
      _errorMessage = _importError;
      _notify();
      return;
    }
    await processPending();
  }

  Future<ShareImportSummary> processPending() {
    if (_inFlight case final running?) {
      if (!_closing) _pendingRun = true;
      return running;
    }
    if (_closing) return Future.value(_emptySummary);

    // Install before publishing checking: listeners may synchronously reenter.
    final completion = Completer<ShareImportSummary>();
    _inFlight = completion.future;
    unawaited(_drain(completion));
    return completion.future;
  }

  Future<void> _drain(Completer<ShareImportSummary> completion) async {
    var summary = _emptySummary;
    var generation = _presentationGeneration;
    do {
      _pendingRun = false;
      generation = _presentationGeneration;
      final result = await _processPass(generation);
      summary = result.summary;
      if (_canPublish(generation) &&
          (summary.staged != 0 ||
              summary.alreadyStaged != 0 ||
              summary.rejected != 0 ||
              summary.failed != 0 ||
              result.error != null)) {
        _lastSummary = summary;
        _errorMessage = result.error;
        _notify();
      }
    } while (_pendingRun && !_closing);

    _inFlight = null;
    completion.complete(summary);
    if (_canPublish(generation)) {
      _phase = ShareImportPhase.idle;
      _notify();
    }
  }

  Future<({ShareImportSummary summary, String? error})> _processPass(
    int generation,
  ) async {
    var staged = 0;
    var alreadyStaged = 0;
    var rejected = 0;
    var failed = 0;
    String? errorMessage;
    try {
      // Native pending may copy files asynchronously. Every batch in this pass
      // belongs to the identity at lookup start, not the identity at completion.
      final identity = _currentIdentity();
      _setPhase(ShareImportPhase.checking, generation);
      final batches = await _intake.pending();
      for (final batch in batches) {
        if (!batch.complete) continue;
        rejected += batch.rejectedCount;
        var batchFailed = false;
        for (final item in batch.items.take(maxSharedItems)) {
          if (await _queue.hasShareReceipt(batch.id, item.index)) {
            alreadyStaged++;
            continue;
          }
          _setPhase(ShareImportPhase.staging, generation);
          try {
            await _queue.stage(
              StageDocumentInput(
                sourceFile: File(item.path),
                mimeType: item.mime,
                filename: item.name,
                source: ScanSource.share,
                pageCount: 1,
                identity: identity,
                expectedSize: item.size,
                expectedSha256: item.sha256,
              ),
              shareReceipt: ShareReceiptInput(
                batchId: batch.id,
                itemIndex: item.index,
              ),
            );
            staged++;
          } on QueueStageException catch (error) {
            if (error.code == 'share_already_staged') {
              alreadyStaged++;
            } else if (terminalShareRejectionCodes.contains(error.code)) {
              try {
                await _queue.recordRejectedShareItem(
                  receipt: ShareReceiptInput(
                    batchId: batch.id,
                    itemIndex: item.index,
                  ),
                  sha256: item.sha256,
                  byteSize: item.size,
                  mimeType: item.mime,
                  errorCode: error.code,
                );
                rejected++;
              } catch (_) {
                failed++;
                batchFailed = true;
                errorMessage = _importError;
              }
            } else {
              failed++;
              batchFailed = true;
              errorMessage = _importError;
            }
          } catch (_) {
            failed++;
            batchFailed = true;
            errorMessage = _importError;
          }
        }
        if (!batchFailed) {
          final allDurable = await Future.wait(
            batch.items.map(
              (item) => _queue.hasShareReceipt(batch.id, item.index),
            ),
          );
          if (allDurable.every((value) => value)) {
            try {
              await _intake.discard(batch.id);
            } catch (_) {
              errorMessage = _importError;
            }
          }
        }
      }
    } catch (_) {
      // Native/plugin/storage exceptions can contain protected paths. Keep all
      // unacknowledged native files and publish only a safe corrective message.
      errorMessage = _importError;
    }
    return (
      summary: ShareImportSummary(
        staged: staged,
        alreadyStaged: alreadyStaged,
        rejected: rejected,
        failed: failed,
      ),
      error: errorMessage,
    );
  }

  void concealForIdentityTransition() {
    if (_closing) return;
    _presentationGeneration++;
    _phase = ShareImportPhase.idle;
    _lastSummary = null;
    _errorMessage = null;
    _notify();
  }

  void dismissResult() {
    if (_closing) return;
    _lastSummary = null;
    _errorMessage = null;
    _notify();
  }

  bool _canPublish(int generation) =>
      !_closing && !_disposed && generation == _presentationGeneration;

  void _setPhase(ShareImportPhase phase, int generation) {
    if (!_canPublish(generation) || _phase == phase) return;
    _phase = phase;
    _notify();
  }

  void _notify() {
    if (!_closing && !_disposed) notifyListeners();
  }

  Future<void> close() {
    if (_closeFuture case final closing?) return closing;
    _closing = true;
    _pendingRun = false;
    final completion = Completer<void>();
    _closeFuture = completion.future;
    unawaited(_finishClose(completion));
    return completion.future;
  }

  Future<void> _finishClose(Completer<void> completion) async {
    try {
      try {
        await _subscription?.cancel();
      } finally {
        _subscription = null;
        await _inFlight;
      }
      completion.complete();
    } catch (error, stackTrace) {
      completion.completeError(error, stackTrace);
    } finally {
      dispose();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}
