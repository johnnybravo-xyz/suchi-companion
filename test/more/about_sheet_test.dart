import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:suchi_companion/app/app_licenses.dart';
import 'package:suchi_companion/more/about_sheet.dart';
import 'package:suchi_companion/theme/suchi_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerBundledLicenses);

  test('registers full bundled font license entries', () async {
    final packages = <String>{};
    await for (final entry in LicenseRegistry.licenses) {
      packages.addAll(entry.packages);
    }

    expect(packages, containsAll(['Schibsted Grotesk', 'Spline Sans Mono']));
  });

  testWidgets('shows build, licenses, and only the Suchi website link', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'Suchi Companion',
      packageName: 'page.suchi.companion',
      version: '0.1.0',
      buildNumber: '7',
      buildSignature: '',
    );
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    final launched = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, (call) async {
          if (call.method != 'launch') return null;
          final arguments = call.arguments as Map<Object?, Object?>;
          launched.add(arguments['url'] as String);
          expect(arguments['headers'], isEmpty);
          expect(arguments['useWebView'], false);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: SuchiTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: AboutSuchiSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Version 0.1.0 · Build 7'), findsOneWidget);
    expect(find.text('Source code'), findsNothing);
    expect(find.text('Open-source licenses'), findsOneWidget);
    expect(find.text('Privacy policy'), findsNothing);
    expect(find.text('Support'), findsNothing);
    expect(find.text('Security'), findsNothing);

    final website = find.byKey(const ValueKey('about-website'));
    await tester.scrollUntilVisible(website, 250);
    await tester.tap(website);
    await tester.pump();
    expect(launched, ['https://suchi.page/']);

    final licenses = find.byKey(const ValueKey('about-licenses'));
    await tester.scrollUntilVisible(licenses, -250);
    await tester.tap(licenses);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Licenses'), findsOneWidget);
    expect(find.text('Suchi Companion'), findsOneWidget);
    expect(find.text('0.1.0 (7)'), findsOneWidget);
  });
}
