import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_mobile/app/lifecycle_privacy_shield.dart';

void main() {
  testWidgets('conceals app content whenever the app is inactive', (
    tester,
  ) async {
    var concealed = 0;
    var resumed = 0;
    await tester.pumpWidget(
      LifecyclePrivacyShield(
        onConceal: () => concealed++,
        onResume: () async => resumed++,
        child: const ColoredBox(color: Colors.white),
      ),
    );

    expect(
      find.byKey(const ValueKey('lifecycle-privacy-shield')),
      findsNothing,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(concealed, 1);
    expect(
      find.byKey(const ValueKey('lifecycle-privacy-shield')),
      findsOneWidget,
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('lifecycle-privacy-shield')),
          )
          .color,
      const Color(0x59FAFAF8),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(concealed, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(resumed, 1);
    expect(
      find.byKey(const ValueKey('lifecycle-privacy-shield')),
      findsNothing,
    );
  });
}
