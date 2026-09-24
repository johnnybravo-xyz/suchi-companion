import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/api_models.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';
import 'package:suchi_mobile/auth/session_controller.dart';
import 'package:suchi_mobile/more/app_settings_controller.dart';
import 'package:suchi_mobile/more/more_screen.dart';
import 'package:suchi_mobile/scan/scan_database.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScanDatabase database;
  late AppSettingsController settings;
  late SessionController session;

  setUp(() async {
    database = ScanDatabase(NativeDatabase.memory());
    settings = AppSettingsController(database);
    await settings.initialize();
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
  });

  tearDown(() async {
    session.dispose();
    settings.dispose();
    await database.close();
  });

  testWidgets('offline More offers retry without a second document library', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SuchiTheme.light,
        home: MoreScreen(session: session, settings: settings),
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
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Privacy policy'))
          .onTap,
      isNull,
    );

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
