import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_companion/app/lifecycle_privacy_shield.dart';

void main() {
  testWidgets('conceals app content whenever the app is inactive', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var concealed = 0;
    var resumed = 0;
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: LifecyclePrivacyShield(
          onConceal: () => concealed++,
          onResume: () async => resumed++,
          child: Semantics(
            label: 'Private document',
            button: true,
            child: GestureDetector(
              key: const ValueKey('private-content'),
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('lifecycle-privacy-shield')),
      findsNothing,
    );
    expect(
      tester.semantics.simulatedAccessibilityTraversal().map(
        (node) => node.label,
      ),
      contains('Private document'),
    );
    expect(
      find.byKey(const ValueKey('private-content')).hitTestable(),
      findsOneWidget,
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
      tester.semantics.simulatedAccessibilityTraversal().map(
        (node) => node.label,
      ),
      isNot(contains('Private document')),
    );
    expect(
      find.byKey(const ValueKey('private-content')).hitTestable(),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('private-content')),
      warnIfMissed: false,
    );
    expect(taps, 0);
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
    expect(
      tester.semantics.simulatedAccessibilityTraversal().map(
        (node) => node.label,
      ),
      contains('Private document'),
    );
    expect(
      find.byKey(const ValueKey('private-content')).hitTestable(),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
