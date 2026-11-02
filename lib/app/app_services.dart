import 'dart:async';

import '../auth/credential_vault.dart';
import '../auth/account_identity.dart';
import '../auth/session_controller.dart';
import '../documents/thumbnail_cache.dart';
import '../detail/document_files.dart';
import '../more/app_settings_controller.dart';
import '../offline/offline_document_store.dart';
import '../scan/background_upload.dart';
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
    required this.backgroundUploads,
    required this.capture,
    required this.network,
    required this.offlineDocuments,
    required this.shareBridge,
    required this.shareImport,
    required this.thumbnails,
    required this.documentFiles,
  });

  final ScanQueueStore queue;
  final AppSettingsController settings;
  final SessionController session;
  final UploadCoordinator uploads;
  final BackgroundUploadScheduling backgroundUploads;
  final NetworkMonitor network;
  final OfflineDocumentStore offlineDocuments;
  final ScanCaptureController capture;
  final ShareBridge shareBridge;
  final ShareImportController shareImport;
  final ThumbnailMemoryCache thumbnails;
  final DocumentFiles documentFiles;
  bool _closed = false;

  static Future<AppServices> create() async {
    final queue = await ScanQueueStore.open();
    AppServices? services;
    DocumentFiles? documentFiles;
    OfflineDocumentStore? offlineDocuments;
    try {
      final settings = AppSettingsController(queue.database);
      await settings.initialize();
      final thumbnails = ThumbnailMemoryCache();
      documentFiles = await DocumentFiles.open();
      offlineDocuments = await OfflineDocumentStore.open(files: documentFiles);
      final network = ConnectivityNetworkMonitor();
      final backgroundUploads = BackgroundUploadScheduler(queue: queue);
      late final SessionController session;
      late final UploadCoordinator uploads;
      late final ScanCaptureController capture;
      late final ShareImportController shareImport;

      AccountIdentity? currentIdentity() => session.identity;

      session = SessionController(
        vault: SecureCredentialVault(),
        onPauseUploads: () async {
          offlineDocuments!.cancelPending();
          await uploads.pause();
          await backgroundUploads.pause();
          await documentFiles!.clear();
        },
        onBeginOfflineSignOut: offlineDocuments.beginSignOut,
        onRollbackOfflineSignOut: offlineDocuments.rollbackSignOut,
        onFinishOfflineSignOut: offlineDocuments.finishSignOut,
        onClearMemoryCaches: () {
          thumbnails.clear();
          capture.concealForIdentityTransition();
          shareImport.concealForIdentityTransition();
        },
        onResumeUploads: () async {
          final identity = session.identity;
          if (identity == null) return;
          await backgroundUploads.resume(identity);
          await uploads.resume();
        },
      );
      final nativeCaptures = await NativeCaptureStore.open();
      uploads = UploadCoordinator(
        store: queue,
        network: network,
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
        backgroundUploads: backgroundUploads,
        shareBridge: shareBridge,
        shareImport: shareImport,
        network: network,
        offlineDocuments: offlineDocuments,
        thumbnails: thumbnails,
        documentFiles: documentFiles,
      );
      await uploads.start();
      await backgroundUploads.start();
      await session.initialize();
      unawaited(capture.recoverPending());
      return services;
    } catch (_) {
      if (services == null) {
        await offlineDocuments?.close();
        await documentFiles?.clear();
        await queue.close();
      } else {
        await services.close();
      }
      rethrow;
    }
  }

  Future<void> onAppConcealed() async {
    thumbnails.clear();
    await uploads.pause();
    await backgroundUploads.onBackgrounded();
  }

  Future<void> onAppResumed() async {
    await backgroundUploads.onForegrounded();
    if (session.state == SessionState.signedIn) {
      await uploads.resume();
    }
    await shareImport.processPending();
    await capture.recoverPending();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await uploads.pause();
    await offlineDocuments.close();
    await documentFiles.clear();
    capture.dispose();
    await shareImport.close();
    uploads.dispose();
    session.dispose();
    settings.dispose();
    thumbnails.clear();
    await shareBridge.close();
    await backgroundUploads.close();
    await queue.close();
  }
}
