import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_mobile/main.dart';
import 'package:suchi_mobile/scan/scanner_bridge.dart';
import 'package:suchi_mobile/share/share_bridge.dart';
import 'package:suchi_mobile/shell/shell.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';

import '../support/mobile_app_harness.dart';

void main() {
  testWidgets(
    'central Scan control announces queue count and invokes its callback',
    (tester) async {
      var taps = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: SuchiTheme.light,
          home: Scaffold(
            body: Center(
              child: ScanDockButton(
                selected: true,
                pendingCount: 3,
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Scan document, 3 queued'), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);

      await tester.tap(find.text('Scan'));
      await tester.pump();

      expect(taps, 1);
      semantics.dispose();
    },
  );

  testWidgets(
    'dock taps capture immediately and long press remembers a nearby mode at large text',
    (tester) async {
      final intake = _HeldIntake();
      final harness = MobileAppHarness();
      await tester.runAsync(() => harness.initialize(intake: intake));
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(() async {
        if (!intake.pendingResult.isCompleted) {
          intake.pendingResult.complete([]);
        }
        await harness.close();
      });
      await tester.pumpWidget(SuchiMobileApp(services: harness.services));
      await _frames(tester);
      await tester.tap(find.text('View'));
      await _frames(tester);
      expect(harness.captures, 0);
      for (final tab in ['Documents', 'Search', 'Inbox']) {
        await tester.tap(find.text(tab).last);
        await _frames(tester);
        expect(harness.captures, 0);
      }
      final control = tester.getRect(find.byType(ScanDockButton));
      final activity = tester.getRect(find.text('View'));
      expect(activity.bottom, lessThan(control.top));
      await tester.tapAt(Offset(control.center.dx, control.top + 10));
      await _frames(tester);
      expect(harness.captureModes, ['scanner']);
      await tester.longPress(
        find.descendant(
          of: find.byType(ScanDockButton),
          matching: find.text('Scan'),
        ),
      );
      await _frames(tester);
      expect(harness.captures, 1);
      expect(find.text('Scanner'), findsOneWidget);
      final picker = tester.getRect(
        find.byType(PopupMenuItem<CaptureMode>).last,
      );
      expect(picker.bottom, lessThanOrEqualTo(control.top));
      expect(control.top - picker.bottom, lessThan(32));
      await tester.tap(find.text('Photo'));
      await _frames(tester);
      expect(harness.captureModes, ['scanner', 'photo']);
      expect(harness.services.settings.captureMode, CaptureMode.photo);
      await tester.tap(find.text('Documents').last);
      await _frames(tester);
      await tester.tap(find.byType(ScanDockButton));
      await _frames(tester);
      expect(find.text('Take a photo'), findsOneWidget);
      expect(harness.captureModes, ['scanner', 'photo', 'photo']);
      await tester.longPress(find.byType(ScanDockButton));
      await _frames(tester);
      await tester.tapAt(const Offset(10, 100));
      await _frames(tester);
      expect(harness.captures, 3);
      expect(harness.services.settings.captureMode, CaptureMode.photo);
      await tester.tap(find.text('More').last);
      await _frames(tester);
      await tester.scrollUntilVisible(
        find.text('Camera mode'),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await _frames(tester);
      await tester.tap(find.text('Camera mode'));
      await _frames(tester);
      expect(
        tester.getRect(find.byType(BottomSheet)).bottom,
        tester.view.physicalSize.height,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await _frames(tester);
      expect(harness.services.settings.captureMode, CaptureMode.photo);
      expect(harness.captures, 3);
      await tester.tap(find.text('Camera mode'));
      await _frames(tester);
      await tester.tap(find.text('Scanner'));
      await _frames(tester);
      expect(harness.services.settings.captureMode, CaptureMode.scanner);
      expect(harness.captures, 3);
      expect(tester.takeException(), isNull);
      intake.pendingResult.complete([]);
      await _frames(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await _frames(tester);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _HeldIntake implements ShareIntake {
  final pendingResult = Completer<List<SharedBatch>>();
  @override
  Stream<void> get events => const Stream.empty();
  @override
  Future<List<SharedBatch>> pending() => pendingResult.future;
  @override
  Future<String?> pick(String source, String batchId) async => null;
  @override
  Future<void> discard(String batchId) async {}
}
