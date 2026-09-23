import 'dart:async';

import '../auth/credential_vault.dart';
import '../auth/account_identity.dart';
import '../auth/session_controller.dart';
import '../documents/thumbnail_cache.dart';
import '../detail/document_files.dart';
import '../more/app_settings_controller.dart';
import '../scan/network_monitor.dart';
import '../scan/scan_capture_controller.dart';
import '../scan/native_capture_store.dart';
import '../scan/scan_queue_store.dart';
import '../scan/scanner_bridge.dart';
import '../scan/upload_coordinator.dart';
import '../share/share_bridge.dart';
import '../share/share_import_controller.dart';

final class AppServices {
  AppServices({
    required this.queue,
    required this.settings,
    required this.session,
    required this.uploads,
    required this.capture,
    required this.shareBridge,
    required this.shareImport,
    required this.thumbnails,
    required this.documentFiles,
  });

  final ScanQueueStore queue;
  final AppSettingsController settings;
  final SessionController session;
  final UploadCoordinator uploads;
  final ScanCaptureController capture;
  final ShareBridge shareBridge;
  final ShareImportController shareImport;
  final ThumbnailMemoryCache thumbnails;
  final DocumentFiles documentFiles;
  bool _closed = false;

  static Future<AppServices> create() async {
    final queue = await ScanQueueStore.open();
    AppServices? services;
    try {
      final settings = AppSettingsController(queue.database);
      await settings.initialize();
      final thumbnails = ThumbnailMemoryCache();
      final documentFiles = await DocumentFiles.open();
      late final SessionController session;
      late final UploadCoordinator uploads;
      late final ScanCaptureController capture;
      late final ShareImportController shareImport;

      AccountIdentity? currentIdentity() => session.identity;

      session = SessionController(
        vault: SecureCredentialVault(),
        onPauseUploads: () async {
          await uploads.pause();
          await documentFiles.clear();
        },
        onClearMemoryCaches: () {
          thumbnails.clear();
          capture.concealForIdentityTransition();
          shareImport.concealForIdentityTransition();
        },
        onResumeUploads: () => uploads.resume(),
      );
      final nativeCaptures = await NativeCaptureStore.open();
      uploads = UploadCoordinator(
        store: queue,
        network: ConnectivityNetworkMonitor(),
        currentClient: () => session.client,
        currentIdentity: currentIdentity,
        deviceOcrEnabled: () => !settings.serverOcrOnly,
        onUnauthorized: session.expire,
      );
      capture = ScanCaptureController(
        nativeCaptures: nativeCaptures,
        scanner: ScannerBridge(),
        queue: queue,
        currentIdentity: currentIdentity,
        deviceOcrEnabled: () => !settings.serverOcrOnly,
      );
      final shareBridge = ShareBridge();
      shareImport = ShareImportController(
        intake: shareBridge,
        queue: queue,
        currentIdentity: currentIdentity,
      );
      services = AppServices(
        queue: queue,
        settings: settings,
        session: session,
        uploads: uploads,
        capture: capture,
        shareBridge: shareBridge,
        shareImport: shareImport,
        thumbnails: thumbnails,
        documentFiles: documentFiles,
      );
      await uploads.start();
      await session.initialize();
      unawaited(capture.recoverPending());
      return services;
    } catch (_) {
      if (services == null) {
        await queue.close();
      } else {
        await services.close();
      }
      rethrow;
    }
  }

  Future<void> onAppResumed() async {
    await shareImport.processPending();
    await capture.recoverPending();
    await uploads.processNow();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await uploads.pause();
    await documentFiles.clear();
    capture.dispose();
    await shareImport.close();
    uploads.dispose();
    session.dispose();
    settings.dispose();
    thumbnails.clear();
    await shareBridge.close();
    await queue.close();
  }
}
