import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../app/display_environment.dart';

const kSuchiWideBreakpoint = 720.0;
const kSuchiRailWidth = 88.0;
const kSuchiMasterMinWidth = 320.0;
const kSuchiMasterMaxWidth = 400.0;
const kSuchiDetailMinWidth = 312.0;
const kSuchiContentMaxWidth = 720.0;
const kSuchiSheetMaxWidth = 560.0;
const kSuchiMoreMaxWidth = 1040.0;
const kSuchiMoreCardMinWidth = 320.0;
const kSuchiMoreCardMaxWidth = 480.0;

enum SuchiChromeMode { bottomDock, sideDock, rail }

enum SuchiHorizontalEdge { leading, trailing }

@immutable
final class SuchiShellLayout {
  const SuchiShellLayout({
    required this.mode,
    this.edge = SuchiHorizontalEdge.leading,
  });

  final SuchiChromeMode mode;
  final SuchiHorizontalEdge edge;

  bool get isWide => mode == SuchiChromeMode.rail;

  @override
  bool operator ==(Object other) =>
      other is SuchiShellLayout && mode == other.mode && edge == other.edge;

  @override
  int get hashCode => Object.hash(mode, edge);
}

SuchiShellLayout resolveSuchiShellLayout({
  required double width,
  required SuchiVerticalBarEdge verticalBarEdge,
}) {
  final reportedEdge = switch (verticalBarEdge) {
    SuchiVerticalBarEdge.leading => SuchiHorizontalEdge.leading,
    SuchiVerticalBarEdge.trailing => SuchiHorizontalEdge.trailing,
    SuchiVerticalBarEdge.unspecified => null,
  };
  if (width >= kSuchiWideBreakpoint) {
    return SuchiShellLayout(
      mode: SuchiChromeMode.rail,
      edge: reportedEdge ?? SuchiHorizontalEdge.leading,
    );
  }
  if (reportedEdge != null) {
    return SuchiShellLayout(mode: SuchiChromeMode.sideDock, edge: reportedEdge);
  }
  return const SuchiShellLayout(mode: SuchiChromeMode.bottomDock);
}

enum SuchiWorkspaceAxis { horizontal, vertical }

@immutable
final class SuchiWorkspaceLayout {
  const SuchiWorkspaceLayout({
    required this.master,
    required this.detail,
    required this.axis,
    required this.isSplit,
    this.division,
  });

  final Rect master;
  final Rect detail;
  final SuchiWorkspaceAxis axis;
  final bool isSplit;
  final Rect? division;
}

SuchiWorkspaceLayout resolveSuchiWorkspaceLayout({
  required Rect bounds,
  required bool wide,
  List<Rect> divisions = const <Rect>[],
}) {
  final division = _relevantDivision(bounds, divisions);
  if (division != null) {
    final clipped = division.intersect(bounds);
    if (clipped.height >= clipped.width) {
      return SuchiWorkspaceLayout(
        master: Rect.fromLTRB(
          bounds.left,
          bounds.top,
          clipped.left,
          bounds.bottom,
        ),
        detail: Rect.fromLTRB(
          clipped.right,
          bounds.top,
          bounds.right,
          bounds.bottom,
        ),
        axis: SuchiWorkspaceAxis.horizontal,
        isSplit: true,
        division: clipped,
      );
    }
    return SuchiWorkspaceLayout(
      master: Rect.fromLTRB(bounds.left, bounds.top, bounds.right, clipped.top),
      detail: Rect.fromLTRB(
        bounds.left,
        clipped.bottom,
        bounds.right,
        bounds.bottom,
      ),
      axis: SuchiWorkspaceAxis.vertical,
      isSplit: true,
      division: clipped,
    );
  }
  if (!wide) {
    return SuchiWorkspaceLayout(
      master: bounds,
      detail: Rect.fromLTWH(bounds.right, bounds.bottom, 0, 0),
      axis: SuchiWorkspaceAxis.horizontal,
      isSplit: false,
    );
  }
  final maximumMaster = math.min(
    kSuchiMasterMaxWidth,
    math.max(0.0, bounds.width - kSuchiDetailMinWidth),
  );
  final desiredMaster = (bounds.width * 0.36)
      .clamp(kSuchiMasterMinWidth, kSuchiMasterMaxWidth)
      .toDouble();
  final masterWidth = math.min(desiredMaster, maximumMaster);
  return SuchiWorkspaceLayout(
    master: Rect.fromLTWH(bounds.left, bounds.top, masterWidth, bounds.height),
    detail: Rect.fromLTRB(
      bounds.left + masterWidth,
      bounds.top,
      bounds.right,
      bounds.bottom,
    ),
    axis: SuchiWorkspaceAxis.horizontal,
    isSplit: true,
  );
}

Rect? _relevantDivision(Rect bounds, List<Rect> divisions) {
  Rect? best;
  var bestOverlap = 0.0;
  for (final division in divisions) {
    if (division.width <= 0 || division.height <= 0) continue;
    final overlap = division.intersect(bounds);
    if (overlap.isEmpty) continue;
    final firstSide = overlap.height >= overlap.width
        ? overlap.left - bounds.left
        : overlap.top - bounds.top;
    final secondSide = overlap.height >= overlap.width
        ? bounds.right - overlap.right
        : bounds.bottom - overlap.bottom;
    if (firstSide <= 0 || secondSide <= 0) continue;
    final overlapArea = overlap.width * overlap.height;
    if (overlapArea > bestOverlap) {
      best = division;
      bestOverlap = overlapArea;
    }
  }
  return best;
}

EdgeInsets occlusionInsetsFor(Rect bounds, Iterable<Rect> occlusions) {
  var left = 0.0;
  var top = 0.0;
  var right = 0.0;
  var bottom = 0.0;
  for (final occlusion in occlusions) {
    final clipped = occlusion.intersect(bounds);
    if (clipped.isEmpty) continue;
    if (occlusion.left <= bounds.left) {
      left = math.max(left, clipped.right - bounds.left);
    }
    if (occlusion.top <= bounds.top) {
      top = math.max(top, clipped.bottom - bounds.top);
    }
    if (occlusion.right >= bounds.right) {
      right = math.max(right, bounds.right - clipped.left);
    }
    if (occlusion.bottom >= bounds.bottom) {
      bottom = math.max(bottom, bounds.bottom - clipped.top);
    }
  }
  return EdgeInsets.fromLTRB(left, top, right, bottom);
}

EdgeInsets additionalOcclusionInsets(
  EdgeInsets occlusions,
  EdgeInsets safeArea,
) => EdgeInsets.fromLTRB(
  math.max(0, occlusions.left - safeArea.left),
  math.max(0, occlusions.top - safeArea.top),
  math.max(0, occlusions.right - safeArea.right),
  math.max(0, occlusions.bottom - safeArea.bottom),
);

final class AdaptiveCenteredContent extends StatelessWidget {
  const AdaptiveCenteredContent({
    required this.child,
    this.maxWidth = kSuchiContentMaxWidth,
    this.alignment = Alignment.topCenter,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(maxWidth, constraints.maxWidth),
        ),
        child: child,
      ),
    ),
  );
}

final class AdaptiveSheetContent extends StatelessWidget {
  const AdaptiveSheetContent({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
    this.includeKeyboardInset = true,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool includeKeyboardInset;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final keyboardInset = includeKeyboardInset
          ? MediaQuery.viewInsetsOf(context).bottom
          : 0.0;
      return Padding(
        padding: padding.copyWith(bottom: padding.bottom + keyboardInset),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(
                kSuchiSheetMaxWidth,
                math.max(0, constraints.maxWidth - padding.horizontal),
              ),
            ),
            child: child,
          ),
        ),
      );
    },
  );
}
