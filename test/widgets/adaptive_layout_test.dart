import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_companion/app/display_environment.dart';
import 'package:suchi_companion/widgets/adaptive_layout.dart';

void main() {
  test('shell chrome switches at 720 and honors the system edge', () {
    expect(
      resolveSuchiShellLayout(
        width: 719,
        verticalBarEdge: SuchiVerticalBarEdge.unspecified,
      ),
      const SuchiShellLayout(mode: SuchiChromeMode.bottomDock),
    );
    expect(
      resolveSuchiShellLayout(
        width: 719,
        verticalBarEdge: SuchiVerticalBarEdge.leading,
      ),
      const SuchiShellLayout(
        mode: SuchiChromeMode.sideDock,
        edge: SuchiHorizontalEdge.leading,
      ),
    );
    expect(
      resolveSuchiShellLayout(
        width: 719,
        verticalBarEdge: SuchiVerticalBarEdge.trailing,
      ),
      const SuchiShellLayout(
        mode: SuchiChromeMode.sideDock,
        edge: SuchiHorizontalEdge.trailing,
      ),
    );
    expect(
      resolveSuchiShellLayout(
        width: 720,
        verticalBarEdge: SuchiVerticalBarEdge.unspecified,
      ),
      const SuchiShellLayout(mode: SuchiChromeMode.rail),
    );
    expect(
      resolveSuchiShellLayout(
        width: 1024,
        verticalBarEdge: SuchiVerticalBarEdge.trailing,
      ),
      const SuchiShellLayout(
        mode: SuchiChromeMode.rail,
        edge: SuchiHorizontalEdge.trailing,
      ),
    );
  });

  test('ordinary wide workspace preserves minimum detail width', () {
    final layout = resolveSuchiWorkspaceLayout(
      bounds: const Rect.fromLTWH(88, 0, 632, 844),
      wide: true,
    );

    expect(layout.isSplit, isTrue);
    expect(layout.axis, SuchiWorkspaceAxis.horizontal);
    expect(layout.master, const Rect.fromLTWH(88, 0, 320, 844));
    expect(layout.detail, const Rect.fromLTWH(408, 0, 312, 844));
  });

  test('vertical division creates exact left and right regions', () {
    final layout = resolveSuchiWorkspaceLayout(
      bounds: const Rect.fromLTWH(0, 0, 780, 844),
      wide: true,
      divisions: const [Rect.fromLTWH(384, 0, 12, 844)],
    );

    expect(layout.axis, SuchiWorkspaceAxis.horizontal);
    expect(layout.master, const Rect.fromLTWH(0, 0, 384, 844));
    expect(layout.detail, const Rect.fromLTWH(396, 0, 384, 844));
    expect(layout.division, const Rect.fromLTWH(384, 0, 12, 844));
  });

  test('horizontal division creates exact upper and lower regions', () {
    final layout = resolveSuchiWorkspaceLayout(
      bounds: const Rect.fromLTWH(0, 0, 780, 844),
      wide: false,
      divisions: const [Rect.fromLTWH(0, 410, 780, 14)],
    );

    expect(layout.axis, SuchiWorkspaceAxis.vertical);
    expect(layout.master, const Rect.fromLTWH(0, 0, 780, 410));
    expect(layout.detail, const Rect.fromLTWH(0, 424, 780, 420));
  });

  test('edge occlusions become exact chrome insets', () {
    expect(
      occlusionInsetsFor(const Rect.fromLTWH(0, 0, 780, 844), const [
        Rect.fromLTWH(0, 0, 80, 44),
        Rect.fromLTWH(744, 200, 36, 100),
        Rect.fromLTWH(200, 824, 120, 20),
      ]),
      const EdgeInsets.fromLTRB(80, 44, 36, 20),
    );
  });

  test('safe-area coverage is not added twice for occlusions', () {
    expect(
      additionalOcclusionInsets(
        const EdgeInsets.fromLTRB(80, 44, 36, 20),
        const EdgeInsets.fromLTRB(20, 44, 0, 20),
      ),
      const EdgeInsets.fromLTRB(60, 0, 36, 0),
    );
  });

  testWidgets('centered content uses parent constraints and caps width', (
    tester,
  ) async {
    const childKey = ValueKey('centered-child');
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 1000,
            height: 200,
            child: AdaptiveCenteredContent(
              child: SizedBox(key: childKey, width: 900, height: 100),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(childKey)), const Size(720, 100));

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 500,
            height: 200,
            child: AdaptiveCenteredContent(
              child: SizedBox(key: childKey, width: 900, height: 100),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(childKey)), const Size(500, 100));
  });

  testWidgets('sheet content caps width and includes the keyboard inset', (
    tester,
  ) async {
    const childKey = ValueKey('sheet-child');
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(
          size: Size(800, 600),
          viewInsets: EdgeInsets.only(bottom: 100),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 800,
            height: 600,
            child: AdaptiveSheetContent(
              child: SizedBox(key: childKey, width: 700, height: 100),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(childKey)), const Size(560, 100));
    final padding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(AdaptiveSheetContent),
        matching: find.byType(Padding),
      ),
    );
    expect(padding.padding, const EdgeInsets.fromLTRB(16, 12, 16, 116));
  });
}
