import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

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
  Future<void>? _pickerRun;
  Future<void>? _closeFuture;
  bool _pendingRun = false;
  bool _closing = false;
  bool _disposed = false;
  bool _claimsReconciled = false;
  int _presentationGeneration = 0;
  ShareImportPhase _phase = ShareImportPhase.idle;
  ShareImportSummary? _lastSummary;
  String? _errorMessage;

  bool get isPicking => _pickerRun != null;
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

  Future<void> pick(String source) {
    if (_pickerRun case final running?) return running;
    if (_closing || (source != 'files' && source != 'photos')) {
      return Future.error(
        const FormatException('Share picker is unavailable.'),
      );
    }
    final identity = _currentIdentity();
    if (identity == null) {
      return Future.error(const FormatException('Sign in before importing.'));
    }
    final completion = Completer<void>();
    _pickerRun = completion.future;
    _notify();
    unawaited(_pick(source, identity, completion));
    return completion.future;
  }

  Future<void> _pick(
    String source,
    AccountIdentity identity,
    Completer<void> completion,
  ) async {
    final batchId = const Uuid().v4();
    try {
      await _queue.claimShareBatch(batchId, identity);
      final result = await _intake.pick(source, batchId);
      if (result == null) {
        await _queue.removeShareBatchClaim(batchId);
      } else if (result == batchId) {
        await processPending();
      } else {
        throw const FormatException('Share picker returned an invalid batch.');
      }
    } catch (_) {
      // Claims survive native/storage errors so a later pending manifest
      // cannot be imported under a different account.
      if (_currentIdentity() == identity && !_closing) {
        _errorMessage = _importError;
        _notify();
      }
    } finally {
      _pickerRun = null;
      completion.complete();
      _notify();
    }
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
      final sameIdentity = _currentIdentity() == result.identity;
      if (_canPublish(generation) &&
          sameIdentity &&
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

  Future<
    ({ShareImportSummary summary, String? error, AccountIdentity? identity})
  >
  _processPass(int generation) async {
    var staged = 0;
    var alreadyStaged = 0;
    var rejected = 0;
    var failed = 0;
    String? errorMessage;
    final identity = _currentIdentity();
    try {
      // OS shares use the account at lookup start. Picker batches use the
      // durable owner claim, even after a process restart.
      _setPhase(ShareImportPhase.checking, generation);
      final batches = await _intake.pending();
      if (!_claimsReconciled) {
        try {
          await _queue.reconcileShareBatchClaims(
            batches.map((batch) => batch.id).toSet(),
          );
          _claimsReconciled = true;
        } catch (_) {
          errorMessage = _importError;
        }
      }
      for (final batch in batches) {
        final AccountIdentity? owner;
        try {
          owner = await _queue.shareBatchClaim(batch.id);
        } catch (_) {
          errorMessage = _importError;
          continue; // Never interpret a corrupt owner claim as an OS share.
        }
        if (owner != null && _currentIdentity() != owner) continue;
        if (owner != null &&
            (batch.items.length + batch.rejectedCount > maxSharedItems ||
                batch.items.any((item) => item.index >= maxSharedItems))) {
          errorMessage = _importError;
          continue;
        }
        if (!batch.complete) continue;
        final batchIdentity = owner ?? identity;
        rejected += batch.rejectedCount;
        var batchFailed = false;
        var ownerChanged = false;
        for (final item in batch.items.take(maxSharedItems)) {
          if (owner != null && _currentIdentity() != owner) {
            ownerChanged = true;
            break;
          }
          if (await _queue.hasShareReceipt(batch.id, item.index)) {
            alreadyStaged++;
            continue;
          }
          if (owner != null && _currentIdentity() != owner) {
            ownerChanged = true;
            break;
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
                identity: batchIdentity,
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
            if (owner != null && _currentIdentity() != owner) {
              ownerChanged = true;
              break;
            }
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
        if (!batchFailed &&
            !ownerChanged &&
            (owner == null || _currentIdentity() == owner)) {
          final allDurable = await Future.wait(
            batch.items.map(
              (item) => _queue.hasShareReceipt(batch.id, item.index),
            ),
          );
          if (allDurable.every((value) => value) &&
              (owner == null || _currentIdentity() == owner)) {
            try {
              await _intake.discard(batch.id);
              if (owner != null) {
                await _queue.removeShareBatchClaim(batch.id);
              }
            } catch (_) {
              errorMessage = _importError;
            }
          }
        }
      }
    } catch (_) {
      // Native/plugin/storage exceptions can contain protected paths.
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
      identity: identity,
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
