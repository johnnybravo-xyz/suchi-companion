import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_mobile/main.dart';
import 'package:suchi_mobile/more/more_screen.dart';
import 'package:suchi_mobile/shell/shell.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';

import '../support/mobile_app_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MobileAppHarness harness;

  setUp(() async {
    harness = MobileAppHarness();
    await harness.initialize();
  });
  tearDown(() => harness.close());

  testWidgets(
    'Appearance changes root without replacing shell or navigator; System follows device',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(SuchiMobileApp(services: harness.services));
      await tester.pumpAndSettle();
      final shellState = tester.state(find.byType(SuchiShell));
      final navigator = tester.state(find.byType(Navigator));
      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark').last);
      await tester.pumpAndSettle();
      expect(harness.services.settings.themeMode, ThemeMode.dark);
      expect(
        Theme.of(tester.element(find.byType(MoreScreen))).brightness,
        Brightness.dark,
      );
      expect(tester.state(find.byType(SuchiShell)), same(shellState));
      expect(tester.state(find.byType(Navigator)), same(navigator));
      expect(find.text('Appearance'), findsOneWidget);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(MoreScreen))).brightness,
        Brightness.dark,
      );

      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('System').last);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(MoreScreen))).brightness,
        Brightness.light,
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(MoreScreen))).brightness,
        Brightness.dark,
      );
      expect(tester.state(find.byType(SuchiShell)), same(shellState));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'account details disappear on sign-out without exposing prior identity',
    (tester) async {
      await tester.pumpWidget(SuchiMobileApp(services: harness.services));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('suchi.example.com').last);
      await tester.pumpAndSettle();
      expect(find.text('https://suchi.example.com'), findsOneWidget);
      expect(find.text('FILING SYSTEM'), findsOneWidget);
      expect(find.widgetWithText(SelectableText, 'Archive'), findsOneWidget);
      expect(
        find.text('Pair this device again to use a different filing system.'),
        findsOneWidget,
      );
      await tester.runAsync(harness.services.session.signOut);
      await tester.pumpAndSettle();
      expect(find.text('Account details'), findsNothing);
      expect(
        find.widgetWithText(SelectableText, 'https://suchi.example.com'),
        findsNothing,
      );
      expect(find.byType(MoreScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'theme transition preserves branded intermediate colors and honors reduced motion',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(SuchiMobileApp(services: harness.services));
      await tester.pumpAndSettle();
      SuchiColors palette() =>
          SuchiColors.of(tester.element(find.byType(SuchiShell)));
      expect(palette().manila, const Color(0xFFF2E8CE));
      await tester.runAsync(
        () => harness.services.settings.setThemeMode(ThemeMode.dark),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(palette().manila, isNot(SuchiColors.light.manila));
      expect(palette().manila, isNot(SuchiColors.dark.manila));
      await tester.pumpAndSettle();
      expect(palette().manila, const Color(0xFF38342A));
      expect(palette().ink, const Color(0xFFECEAE2));
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      await tester.runAsync(
        () => harness.services.settings.setThemeMode(ThemeMode.light),
      );
      await tester.pump();
      await tester.pump();
      expect(palette().paper, const Color(0xFFFAFAF8));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
