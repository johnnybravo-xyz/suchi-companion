import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          body: MoreScreen(session: session, settings: settings),
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
