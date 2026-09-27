import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/api_models.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';
import 'package:suchi_mobile/auth/session_controller.dart';
import 'package:suchi_mobile/more/app_settings_controller.dart';
import 'package:suchi_mobile/detail/document_files.dart';
import 'package:suchi_mobile/more/more_screen.dart';
import 'package:suchi_mobile/offline/offline_document_store.dart';
import 'package:suchi_mobile/scan/scan_database.dart';
import 'package:suchi_mobile/scan/scan_queue_store.dart';
import 'package:suchi_mobile/scan/storage_protection.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScanDatabase database;
  late AppSettingsController settings;
  late SessionController session;
  late Directory temporary;
  late ScanQueueStore queue;
  late OfflineDocumentStore offlineDocuments;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('suchi-more-storage-');
    database = ScanDatabase(NativeDatabase.memory());
    settings = AppSettingsController(database);
    await settings.initialize();
    queue = await ScanQueueStore.open(
      database: database,
      root: Directory('${temporary.path}/queue'),
      storageProtection: const _StorageAccess(),
      storageCapacity: const _StorageAccess(),
    );
    offlineDocuments = await OfflineDocumentStore.open(
      files: DocumentFiles(
        root: await Directory('${temporary.path}/exports').create(),
        storageCapacity: const _StorageAccess(),
      ),
      root: Directory('${temporary.path}/offline'),
      storageProtection: const _StorageAccess(),
      storageCapacity: const _StorageAccess(),
    );
    session = SessionController(
      vault: _StoredVault(),
      clientFactory: (origin, token) => SuchiClient(
        origin: origin,
        token: token,
        httpClient: MockClient(
          (_) async => throw const SocketException('offline'),
        ),
      ),
    );
    await session.initialize();
    final offlineBytes = utf8.encode('%PDF-storage');
    await offlineDocuments.save(
      identity: session.identity!,
      document: DocumentDetail.fromJson(
        jsonDecode(
          File('test/fixtures/api/v1/document-detail.json').readAsStringSync(),
        ) as Map<String, dynamic>,
      ),
      client: SuchiClient(
        origin: session.identity!.origin,
        token: 'a' * 64,
        httpClient: MockClient(
          (_) async => http.Response.bytes(
            offlineBytes,
            200,
            headers: {'content-type': 'application/pdf'},
          ),
        ),
      ),
    );
  });

  tearDown(() async {
    session.dispose();
    settings.dispose();
    await offlineDocuments.close();
    await queue.close();
    await database.close();
    await temporary.delete(recursive: true);
  });

  testWidgets('offline More offers retry and opens the public website', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    final launched = <String>[];
    var opens = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, (call) async {
          if (call.method != 'launch') return null;
          final arguments = call.arguments as Map<Object?, Object?>;
          launched.add(arguments['url'] as String);
          expect(arguments['headers'], isEmpty);
          expect(arguments['useWebView'], false);
          return opens;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: SuchiTheme.light,
        home: Scaffold(
          body: MoreScreen(
            session: session,
            settings: settings,
            offlineDocuments: offlineDocuments,
            queue: queue,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Working offline'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Offline documents'), findsNothing);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Trash')).onTap,
      isNull,
    );
    expect(find.widgetWithText(ListTile, 'Privacy & storage'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Privacy & storage'), 300);
    await tester.tap(find.text('Privacy & storage'));
    await tester.pumpAndSettle();
    expect(find.text('CURRENT ACCOUNT'), findsOneWidget);
    expect(find.text('ON THIS DEVICE'), findsOneWidget);
    expect(find.text('1 offline copy · 12 B'), findsNWidgets(2));
    expect(find.textContaining('0 queued items · 0 B queued'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remove-account-offline')));
    await tester.pumpAndSettle();
    expect(find.text('Remove this account’s offline copies?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('1 offline copy · 12 B'), findsNWidgets(2));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy policy'), findsNothing);
    await tester.scrollUntilVisible(find.text('Explore Suchi'), 300);
    await tester.tap(find.text('Explore Suchi'));
    await tester.pumpAndSettle();
    expect(launched, ['https://suchi.page']);

    opens = false;
    await tester.tap(find.text('Explore Suchi'));
    await tester.pumpAndSettle();
    expect(find.text('The Suchi website could not be opened.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Sign out'), 300);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Offline document copies will be removed'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
  });
}

final class _StoredVault implements CredentialVault {
  StoredCredentials? _credentials = StoredCredentials(
    origin: Uri.parse('https://suchi.example.com'),
    token: 'a' * 64,
    userSnapshot: UserSelf.fromJson(
      jsonDecode(File('test/fixtures/api/v1/whoami.json').readAsStringSync()),
    ),
  );

  @override
  Future<void> clear() async => _credentials = null;

  @override
  Future<StoredCredentials?> read() async => _credentials;

  @override
  Future<void> save(StoredCredentials credentials) async =>
      _credentials = credentials;
}

final class _StorageAccess implements StorageProtection, StorageCapacity {
  const _StorageAccess();

  @override
  Future<int> availableBytes(String absolutePath) async => 1 << 30;

  @override
  Future<void> protectDirectory(String absolutePath) async {}
}
