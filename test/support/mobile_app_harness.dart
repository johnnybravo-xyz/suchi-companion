import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/app/app_services.dart';
import 'package:suchi_mobile/auth/account_identity.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';
import 'package:suchi_mobile/auth/session_controller.dart';
import 'package:suchi_mobile/detail/document_files.dart';
import 'package:suchi_mobile/documents/thumbnail_cache.dart';
import 'package:suchi_mobile/more/app_settings_controller.dart';
import 'package:suchi_mobile/offline/offline_document_store.dart';
import 'package:suchi_mobile/scan/network_monitor.dart';
import 'package:suchi_mobile/scan/scan_capture_controller.dart';
import 'package:suchi_mobile/scan/scan_database.dart';
import 'package:suchi_mobile/scan/scan_queue_store.dart';
import 'package:suchi_mobile/scan/scanner_bridge.dart';
import 'package:suchi_mobile/scan/storage_protection.dart';
import 'package:suchi_mobile/scan/upload_coordinator.dart';
import 'package:suchi_mobile/share/share_bridge.dart';
import 'package:suchi_mobile/share/share_import_controller.dart';

/// Real services with isolated storage and controllable external boundaries.
final class MobileAppHarness {
  late final Directory temporary;
  late final ScanDatabase database;
  late final AppServices services;
  final requests = <http.Request>[];
  int captures = 0;
  final captureModes = <String>[];
  Future<http.Response> Function(http.Request)? respond;
  bool _initialized = false;

  AccountIdentity? get identity => services.session.identity;

  Future<void> initialize({
    NetworkMonitor? network,
    ShareIntake? intake,
    http.Client Function()? transportFactory,
    DateTime Function()? now,
  }) async {
    FlutterSecureStorage.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp('suchi-app-');
    database = ScanDatabase(NativeDatabase.memory());
    final queue = await ScanQueueStore.open(
      database: database,
      root: Directory('${temporary.path}/queue'),
      storageProtection: const TestStorageProtection(),
    );
    late OfflineDocumentStore offlineDocuments;
    final session = SessionController(
      vault: TestCredentialVault(),
      onPauseUploads: () async {
        if (_initialized) await services.uploads.pause();
      },
      onClearMemoryCaches: () {
        if (!_initialized) return;
        services.thumbnails.clear();
        services.capture.concealForIdentityTransition();
        services.shareImport.concealForIdentityTransition();
      },
      onResumeUploads: () async {
        if (_initialized) await services.uploads.resume();
      },
      onClearOfflineDocuments: (identity) =>
          offlineDocuments.clearAccount(identity),
      clientFactory: (origin, token) => SuchiClient(
        origin: origin,
        token: token,
        httpClient:
            transportFactory?.call() ??
            MockClient((request) async {
              requests.add(request);
              return respond == null
                  ? archiveResponse(request)
                  : respond!(request);
            }),
      ),
    );
    await session.pairWithToken(
      serverAddress: 'https://suchi.example.com',
      token: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(scannerChannelName),
      (call) async {
        if (call.method == 'capture') {
          captures++;
          captureModes.add((call.arguments as Map)['mode'] as String);
          return {'cancelled': true, 'page_count': 0, 'pages': <Object>[]};
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(shareChannelName),
      (call) async => call.method == 'pending' ? <Object>[] : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('app.suchi.page/documents'),
      (_) async => null,
    );
    final bridge = ShareBridge();
    final exports = await Directory('${temporary.path}/exports').create();
    final documentFiles = DocumentFiles(root: exports);
    offlineDocuments = await OfflineDocumentStore.open(
      files: documentFiles,
      root: Directory('${temporary.path}/offline'),
      storageProtection: const TestStorageProtection(),
    );
    final settings = AppSettingsController(database);
    await settings.initialize();
    services = AppServices(
      queue: queue,
      settings: settings,
      session: session,
      uploads: UploadCoordinator(
        store: queue,
        network: network ?? TestOfflineNetwork(),
        currentClient: () => session.client,
        currentIdentity: () => identity,
        deviceOcrEnabled: () => false,
        onUnauthorized: session.expire,
        now: now,
      ),
      network: TestOnlineNetwork(),
      offlineDocuments: offlineDocuments,
      capture: ScanCaptureController(
        scanner: ScannerBridge(),
        queue: queue,
        currentIdentity: () => identity,
      ),
      shareBridge: bridge,
      shareImport: ShareImportController(
        intake: intake ?? bridge,
        queue: queue,
        currentIdentity: () => identity,
      ),
      thumbnails: ThumbnailMemoryCache(),
      documentFiles: documentFiles,
    );
    _initialized = true;
  }

  Future<void> close() async {
    await services.close();
    await database.close();
    await temporary.delete(recursive: true);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      scannerChannelName,
      shareChannelName,
      'app.suchi.page/documents',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
  }
}

http.Response archiveResponse(http.Request request) {
  return switch (request.url.path) {
    '/api/handshake' => fixtureResponse('handshake.json'),
    '/api/whoami' => fixtureResponse('whoami.json'),
    '/api/jd/categories/' => fixtureResponse('jd-categories.json'),
    '/api/documents/' => fixtureResponse('documents-page.json'),
    '/api/search/' => fixtureResponse('search-page.json'),
    '/api/documents/91' => fixtureResponse('document-detail.json'),
    _ => http.Response('', 404),
  };
}

http.Response fixtureResponse(String name) => http.Response(
  File('test/fixtures/api/v1/$name').readAsStringSync(),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

final class TestCredentialVault implements CredentialVault {
  @override
  Future<void> clear() async {}
  @override
  Future<StoredCredentials?> read() async => null;
  @override
  Future<void> save(StoredCredentials credentials) async {}
}

final class TestStorageProtection implements StorageProtection {
  const TestStorageProtection();
  @override
  Future<void> protectDirectory(String path) async {}
}

final class TestOfflineNetwork implements NetworkMonitor {
  @override
  Stream<bool> get changes => const Stream.empty();
  @override
  Future<bool> isOnline() async => false;
}

final class TestOnlineNetwork implements NetworkMonitor {
  @override
  Stream<bool> get changes => const Stream.empty();

  @override
  Future<bool> isOnline() async => true;
}
