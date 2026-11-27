import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:workmanager/workmanager.dart';

import '../api/api_error.dart';
import '../api/suchi_client.dart';
import '../auth/account_identity.dart';
import '../auth/credential_vault.dart';
import '../more/app_settings_controller.dart';
import 'network_monitor.dart';
import 'scan_database.dart';
import 'scan_queue_store.dart';
import 'upload_coordinator.dart';

const backgroundUploadTaskName = 'suchi.background-upload';
const backgroundUploadProcessingTask =
    'page.suchi.companion.background-upload.processing';
const backgroundUploadContinuedTaskPrefix =
    'page.suchi.companion.background-upload.continued';

const _androidUploadWork = 'suchi-background-upload';
const _androidUploadTag = 'suchi-background-upload';
const _minimumRetryDelay = Duration(seconds: 10);
const _uploadPermitKey = 'background_upload_permit_v1';
const _permitPollInterval = Duration(milliseconds: 500);

enum BackgroundUploadPlatform { android, ios, unsupported }

BackgroundUploadPlatform get currentBackgroundUploadPlatform {
  if (Platform.isAndroid) return BackgroundUploadPlatform.android;
  if (Platform.isIOS) return BackgroundUploadPlatform.ios;
  return BackgroundUploadPlatform.unsupported;
}

abstract interface class BackgroundUploadTaskGateway {
  Future<void> initialize();

  Future<void> scheduleAndroid({required Duration delay});

  Future<void> scheduleIosProcessing({required Duration delay});

  Future<void> scheduleIosContinued({required String taskId});

  Future<void> cancelUploadTasks();
}

final class WorkmanagerBackgroundUploadTaskGateway
    implements BackgroundUploadTaskGateway {
  const WorkmanagerBackgroundUploadTaskGateway();

  @override
  Future<void> initialize() =>
      Workmanager().initialize(backgroundUploadCallbackDispatcher);

  @override
  Future<void> scheduleAndroid({required Duration delay}) =>
      Workmanager().registerOneOffTask(
        _androidUploadWork,
        backgroundUploadTaskName,
        initialDelay: delay,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.update,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: _minimumRetryDelay,
        tag: _androidUploadTag,
      );

  @override
  Future<void> scheduleIosProcessing({required Duration delay}) =>
      Workmanager().registerProcessingTask(
        backgroundUploadProcessingTask,
        backgroundUploadTaskName,
        initialDelay: delay,
        constraints: Constraints(networkType: NetworkType.connected),
      );

  @override
  Future<void> scheduleIosContinued({required String taskId}) =>
      Workmanager().registerContinuedProcessingTask(
        taskId,
        backgroundUploadTaskName,
        title: 'Uploading to Suchi',
        subtitle: 'Sending queued documents',
      );

  @override
  Future<void> cancelUploadTasks() async {
    await Workmanager().cancelByUniqueName(_androidUploadWork);
    await Workmanager().cancelByUniqueName(backgroundUploadProcessingTask);
  }
}

abstract interface class BackgroundUploadScheduling {
  Future<void> start();

  Future<void> resume(AccountIdentity identity);

  Future<void> pause();

  Future<void> onBackgrounded();

  Future<void> onForegrounded();

  Future<void> close();
}

final class BackgroundUploadScheduler implements BackgroundUploadScheduling {
  factory BackgroundUploadScheduler({
    required ScanQueueStore queue,
    BackgroundUploadTaskGateway gateway =
        const WorkmanagerBackgroundUploadTaskGateway(),
    BackgroundUploadPlatform? platform,
    DateTime Function()? now,
  }) => BackgroundUploadScheduler._(
    queue,
    gateway,
    platform ?? currentBackgroundUploadPlatform,
    now ?? (() => DateTime.now().toUtc()),
  );

  BackgroundUploadScheduler._(
    this._queue,
    this._gateway,
    this._platform,
    this._now,
  );

  final ScanQueueStore _queue;
  final BackgroundUploadTaskGateway _gateway;
  final BackgroundUploadPlatform _platform;
  final DateTime Function() _now;

  StreamSubscription<List<ScanUpload>>? _queueSubscription;
  AccountIdentity? _identity;
  Future<void> _tail = Future<void>.value();
  bool _backgrounded = false;
  bool _closed = false;
  final Set<String> _continuedTaskIds = {};

  @override
  Future<void> start() async {
    if (_closed || _queueSubscription != null) return;
    _queueSubscription = _queue.watchUploads().listen((uploads) {
      if (_identity != null &&
          (_backgrounded || _platform == BackgroundUploadPlatform.ios)) {
        _enqueue(
          () => _schedulePending(
            uploads,
            allowContinued:
                !_backgrounded && _platform == BackgroundUploadPlatform.ios,
          ),
        );
      }
    });
  }

  @override
  Future<void> resume(AccountIdentity identity) => _serialize(() async {
    if (_closed) return;
    await _queue.database.setSetting(
      _uploadPermitKey,
      _encodeIdentity(identity),
    );
    _identity = identity;
  });

  @override
  Future<void> pause() => _serialize(() async {
    _continuedTaskIds.clear();
    _identity = null;
    _backgrounded = false;
    await _queue.database.deleteSetting(_uploadPermitKey);
    await _gateway.cancelUploadTasks();
  });

  @override
  Future<void> onBackgrounded() => _serialize(() async {
    if (_closed || _identity == null) return;
    await _schedulePending(
      await _queue.allUploads(),
      allowContinued: _platform == BackgroundUploadPlatform.ios,
    );
    _backgrounded = true;
  });

  @override
  Future<void> onForegrounded() => _serialize(() async {
    _backgrounded = false;
  });

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _queueSubscription?.cancel();
    _queueSubscription = null;
    await _tail;
  }

  Future<void> _schedulePending(
    List<ScanUpload> uploads, {
    required bool allowContinued,
  }) async {
    final identity = _identity;
    if (identity == null) return;
    final pending = pendingBackgroundUploads(uploads, identity);
    final uploading = uploads.any(
      (upload) =>
          upload.state == 'uploading' &&
          queueUploadBelongsToIdentity(upload, identity),
    );
    if (pending.isEmpty) {
      if (!uploading) {
        _continuedTaskIds.clear();
        await _gateway.cancelUploadTasks();
      }
      return;
    }
    final now = _now();
    final delay = backgroundUploadDelay(pending, now: now);
    switch (_platform) {
      case BackgroundUploadPlatform.android:
        await _gateway.scheduleAndroid(delay: delay);
      case BackgroundUploadPlatform.ios:
        await _gateway.scheduleIosProcessing(delay: delay);
        if (allowContinued) {
          final nowMs = now.millisecondsSinceEpoch;
          for (final upload in pending) {
            final due = upload.nextAttemptAtMs;
            if (upload.state != 'queued' || due != null && due > nowMs) {
              continue;
            }
            final taskId = backgroundUploadContinuedTaskIdentifier(upload.id);
            if (!_continuedTaskIds.add(taskId)) break;
            try {
              await _gateway.scheduleIosContinued(taskId: taskId);
            } catch (_) {
              _continuedTaskIds.remove(taskId);
              rethrow;
            }
            break;
          }
        }
      case BackgroundUploadPlatform.unsupported:
        return;
    }
  }

  void _enqueue(Future<void> Function() operation) {
    _tail = _tail.then((_) => operation()).catchError((_) {});
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final completer = Completer<void>();
    _tail = _tail
        .then((_) => operation())
        .then(
          (_) => completer.complete(),
          onError: (Object error, StackTrace stackTrace) {
            completer.completeError(error, stackTrace);
          },
        );
    return completer.future;
  }
}

final class NoopBackgroundUploadScheduler
    implements BackgroundUploadScheduling {
  const NoopBackgroundUploadScheduler();

  @override
  Future<void> start() async {}

  @override
  Future<void> resume(AccountIdentity identity) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> onBackgrounded() async {}

  @override
  Future<void> onForegrounded() async {}

  @override
  Future<void> close() async {}
}

List<ScanUpload> pendingBackgroundUploads(
  Iterable<ScanUpload> uploads,
  AccountIdentity identity,
) => uploads
    .where(
      (upload) =>
          (upload.state == 'queued' || upload.state == 'processingServer') &&
          upload.lastErrorCode != 'unauthorized' &&
          queueUploadBelongsToIdentity(upload, identity),
    )
    .toList(growable: false);

Duration backgroundUploadDelay(
  Iterable<ScanUpload> uploads, {
  required DateTime now,
}) {
  final nowMs = now.toUtc().millisecondsSinceEpoch;
  int? earliest;
  for (final upload in uploads) {
    final due = upload.nextAttemptAtMs ?? nowMs;
    if (earliest == null || due < earliest) earliest = due;
  }
  if (earliest == null || earliest <= nowMs) return Duration.zero;
  return Duration(milliseconds: earliest - nowMs);
}

String backgroundUploadContinuedTaskIdentifier(String uploadId) =>
    '$backgroundUploadContinuedTaskPrefix.$uploadId';

bool isBackgroundUploadTask(String task) =>
    task == backgroundUploadTaskName ||
    task == backgroundUploadProcessingTask ||
    task.startsWith('$backgroundUploadContinuedTaskPrefix.');

@pragma('vm:entry-point')
void backgroundUploadCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (!isBackgroundUploadTask(task)) {
      return true;
    }
    final platform = currentBackgroundUploadPlatform;
    const gateway = WorkmanagerBackgroundUploadTaskGateway();
    try {
      return await BackgroundUploadRunner(
        gateway: gateway,
        platform: platform,
      ).run(
        waitForForegroundTransfer: task.startsWith(
          '$backgroundUploadContinuedTaskPrefix.',
        ),
      );
    } catch (_) {
      try {
        await _scheduleRetry(gateway, platform);
      } catch (_) {
        // The OS retry result remains authoritative when rescheduling fails.
      }
      return false;
    }
  });
}

final class BackgroundUploadRunner {
  factory BackgroundUploadRunner({
    BackgroundUploadTaskGateway gateway =
        const WorkmanagerBackgroundUploadTaskGateway(),
    BackgroundUploadPlatform? platform,
    CredentialVault? vault,
    Future<ScanQueueStore> Function()? openQueue,
    SuchiClient Function(Uri origin, String? token)? clientFactory,
    DateTime Function()? now,
  }) => BackgroundUploadRunner._(
    gateway,
    platform ?? currentBackgroundUploadPlatform,
    vault ?? SecureCredentialVault(),
    openQueue ?? ScanQueueStore.open,
    clientFactory ??
        ((origin, token) => SuchiClient(origin: origin, token: token)),
    now ?? (() => DateTime.now().toUtc()),
  );

  BackgroundUploadRunner._(
    this._gateway,
    this._platform,
    this._vault,
    this._openQueue,
    this._clientFactory,
    this._now,
  );

  final BackgroundUploadTaskGateway _gateway;
  final BackgroundUploadPlatform _platform;
  final CredentialVault _vault;
  final Future<ScanQueueStore> Function() _openQueue;
  final SuchiClient Function(Uri origin, String? token) _clientFactory;
  final DateTime Function() _now;

  Future<bool> run({bool waitForForegroundTransfer = false}) async {
    ScanQueueStore? queue;
    SuchiClient? probe;
    SuchiClient? client;
    UploadCoordinator? coordinator;
    Timer? permitTimer;
    var checkingPermit = false;
    try {
      queue = await _openQueue();
      final credentials = await _vault.read();
      final snapshot = credentials?.userSnapshot;
      if (credentials == null || snapshot == null) return true;
      final storedIdentity = AccountIdentity(
        origin: credentials.origin,
        userId: snapshot.userId,
        systemId: snapshot.systemId,
      );
      final permit = _encodeIdentity(storedIdentity);
      if (await queue.database.setting(_uploadPermitKey) != permit) return true;
      final uploads = await queue.allUploads();
      final before = pendingBackgroundUploads(uploads, storedIdentity);
      final uploading = uploads.any(
        (upload) =>
            upload.state == 'uploading' &&
            queueUploadBelongsToIdentity(upload, storedIdentity),
      );
      if (before.isEmpty && (!waitForForegroundTransfer || !uploading)) {
        if (uploading) {
          await _scheduleRetry(_gateway, _platform);
        }
        return true;
      }

      probe = _clientFactory(credentials.origin, null);
      await probe.handshake();
      probe.close();
      probe = null;

      client = _clientFactory(credentials.origin, credentials.token);
      final verified = await client.whoAmI();
      if (!verified.hasMobileScopes ||
          verified.userId != storedIdentity.userId ||
          verified.systemId != storedIdentity.systemId) {
        return true;
      }

      final serverOcrOnly =
          await queue.database.setting(serverOcrOnlySettingKey) == 'true';
      var unauthorized = false;
      coordinator = UploadCoordinator(
        store: queue,
        network: const _TaskNetworkMonitor(),
        currentClient: () => client,
        currentIdentity: () => storedIdentity,
        deviceOcrEnabled: () => !serverOcrOnly,
        onUnauthorized: (ApiException error) async {
          unauthorized = true;
        },
        now: _now,
      );
      await coordinator.start();
      permitTimer = Timer.periodic(_permitPollInterval, (_) {
        if (checkingPermit) return;
        checkingPermit = true;
        queue!.database
            .setting(_uploadPermitKey)
            .then((stored) {
              if (stored != permit) unawaited(coordinator!.pause());
            })
            .whenComplete(() => checkingPermit = false);
      });
      await coordinator.resume();
      if (waitForForegroundTransfer) {
        while (await _hasDueOrUploadingTransfer(
          queue,
          storedIdentity,
          now: _now(),
        )) {
          if (await queue.database.setting(_uploadPermitKey) != permit) break;
          await Future<void>.delayed(_permitPollInterval);
          if (await queue.database.setting(_uploadPermitKey) != permit) break;
          await coordinator.processNow();
        }
      }
      await coordinator.pause();

      final remaining = pendingBackgroundUploads(
        await queue.allUploads(),
        storedIdentity,
      );
      if (!unauthorized && remaining.isNotEmpty) {
        await _scheduleForPending(_gateway, _platform, remaining, now: _now());
      }
      return true;
    } finally {
      permitTimer?.cancel();
      if (coordinator != null) {
        try {
          await coordinator.pause();
        } catch (_) {
          // Queue reconciliation will recover an interrupted upload.
        }
        coordinator.dispose();
      }
      client?.close();
      probe?.close();
      await queue?.close();
    }
  }
}

Future<bool> _hasDueOrUploadingTransfer(
  ScanQueueStore queue,
  AccountIdentity identity, {
  required DateTime now,
}) async {
  final nowMs = now.millisecondsSinceEpoch;
  for (final upload in await queue.allUploads()) {
    if (!queueUploadBelongsToIdentity(upload, identity)) continue;
    if (upload.state == 'uploading') return true;
    if (upload.state == 'queued' &&
        upload.lastErrorCode != 'unauthorized' &&
        (upload.nextAttemptAtMs == null || upload.nextAttemptAtMs! <= nowMs)) {
      return true;
    }
  }
  return false;
}

final class _TaskNetworkMonitor implements NetworkMonitor {
  const _TaskNetworkMonitor();

  @override
  Stream<bool> get changes => const Stream<bool>.empty();

  @override
  Future<bool> isOnline() async => true;
}

Future<void> _scheduleRetry(
  BackgroundUploadTaskGateway gateway,
  BackgroundUploadPlatform platform,
) => switch (platform) {
  BackgroundUploadPlatform.android => gateway.scheduleAndroid(
    delay: _minimumRetryDelay,
  ),
  BackgroundUploadPlatform.ios => gateway.scheduleIosProcessing(
    delay: _minimumRetryDelay,
  ),
  BackgroundUploadPlatform.unsupported => Future<void>.value(),
};

Future<void> _scheduleForPending(
  BackgroundUploadTaskGateway gateway,
  BackgroundUploadPlatform platform,
  List<ScanUpload> uploads, {
  required DateTime now,
}) {
  final delay = backgroundUploadDelay(uploads, now: now);
  return switch (platform) {
    BackgroundUploadPlatform.android => gateway.scheduleAndroid(delay: delay),
    BackgroundUploadPlatform.ios => gateway.scheduleIosProcessing(delay: delay),
    BackgroundUploadPlatform.unsupported => Future<void>.value(),
  };
}

String _encodeIdentity(AccountIdentity identity) => jsonEncode({
  'origin': identity.origin.toString(),
  'user_id': identity.userId,
  'system_id': identity.systemId,
});
