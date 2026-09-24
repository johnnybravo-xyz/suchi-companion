import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/api_models.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';
import 'package:suchi_mobile/auth/session_controller.dart';
import 'package:suchi_mobile/detail/document_files.dart';
import 'package:suchi_mobile/more/app_settings_controller.dart';
import 'package:suchi_mobile/more/more_screen.dart';
import 'package:suchi_mobile/offline/offline_document_store.dart';
import 'package:suchi_mobile/scan/scan_database.dart';
import 'package:suchi_mobile/scan/storage_protection.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporary;
  late ScanDatabase database;
  late AppSettingsController settings;
  late OfflineDocumentStore store;
  late SessionController session;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('suchi-offline-more-');
    database = ScanDatabase(NativeDatabase.memory());
    settings = AppSettingsController(database);
    await settings.initialize();
    final files = DocumentFiles(
      root: await Directory('${temporary.path}/exports').create(),
    );
    store = await OfflineDocumentStore.open(
      files: files,
      root: Directory('${temporary.path}/offline'),
      storageProtection: const _NoopProtection(),
      newUuid: () => '00000000-0000-4000-8000-000000000001',
      now: () => DateTime.utc(2026, 9, 12),
    );
    session = SessionController(
      vault: _StoredVault(),
      onClearOfflineDocuments: store.clearAccount,
      clientFactory: (origin, token) => SuchiClient(
        origin: origin,
        token: token,
        httpClient: MockClient(
          (_) async => throw const SocketException('offline'),
        ),
      ),
    );
    await session.initialize();
    final payload = utf8.encode('%PDF-offline');
    await store.save(
      identity: session.identity!,
      document: _document(payload.length),
      client: SuchiClient(
        origin: session.origin!,
        token: 'a' * 64,
        httpClient: MockClient(
          (_) async => http.Response.bytes(
            payload,
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
    await store.close();
    await database.close();
    await temporary.delete(recursive: true);
  });

  testWidgets('offline More exposes only local-safe account actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SuchiTheme.light,
        home: MoreScreen(
          session: session,
          settings: settings,
          offlineDocuments: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Working offline'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Offline documents'), findsOneWidget);
    expect(find.text('1 on this device'), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Trash')).onTap,
      isNull,
    );
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Privacy policy'))
          .onTap,
      isNull,
    );

    await tester.tap(find.text('Offline documents'));
    await tester.pumpAndSettle();
    expect(find.text('1 document · 12 B'), findsOneWidget);
    expect(find.text('Quarterly report'), findsOneWidget);
    await tester.tap(find.text('Close'));
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

DocumentDetail _document(int size) => DocumentDetail.fromJson({
  'id': 91,
  'title': 'Quarterly report',
  'mime_type': 'application/pdf',
  'original_size': size,
  'original_blob': 'b' * 64,
  'jd_category_id': 31,
  'jd_category_code': 31,
  'jd_category_name': 'Utilities',
  'jd_area_name': 'Home',
  'sensitivity': '',
  'created_at': 100,
  'added_at': 110,
  'updated_at': 120,
  'source_mtime': null,
  'trashed_at': null,
  'sources': const [],
  'tags': const ['tax'],
  'correspondents': const [],
  'languages': 'eng',
  'languages_locked': false,
  'content': '',
});

final class _NoopProtection implements StorageProtection {
  const _NoopProtection();

  @override
  Future<void> protectDirectory(String path) async {}
}
