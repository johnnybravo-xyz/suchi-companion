import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../more/app_settings_controller.dart';
import '../theme/suchi_theme.dart';
import 'scanner_bridge.dart';

Future<CaptureMode?> chooseCaptureMode(
  BuildContext context, {
  required AppSettingsController settings,
  required Rect anchor,
}) async {
  if (!settings.loaded) return null;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final topLeft = overlay.globalToLocal(anchor.topLeft);
  final colors = SuchiColors.of(context);
  final textTheme = Theme.of(context).textTheme;
  const title = 'Choose & capture';
  final headingStyle = textTheme.labelLarge!.copyWith(
    inherit: false,
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w700,
    color: colors.muted,
  );
  final titleStyle = textTheme.titleSmall!.copyWith(
    inherit: false,
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w600,
  );
  final detailStyle = textTheme.bodySmall!.copyWith(
    inherit: false,
    fontSize: 12,
    height: 1.5,
    color: colors.muted,
  );
  final width = math.min(320.0, overlay.size.width - 32);
  final left = (topLeft.dx + anchor.width / 2 - width / 2).clamp(
    16.0,
    math.max(16.0, overlay.size.width - width - 16),
  );
  // Measure wrapping with the actual font and text scale, so the menu stays
  // above the control rather than growing over the user's thumb.
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  );
  double textHeight(String text, TextStyle style, double availableWidth) {
    painter.text = TextSpan(text: text, style: style);
    painter.layout(maxWidth: availableWidth);
    return painter.height;
  }

  final items = <PopupMenuEntry<CaptureMode>>[
    PopupMenuItem(
      enabled: false,
      height: math.max(40, textHeight(title, headingStyle, width - 32) + 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(title, style: headingStyle),
    ),
    for (final (mode, label, detail) in const [
      (CaptureMode.scanner, 'Scanner', 'Clean up pages'),
      (CaptureMode.photo, 'Photo', 'Keep full frame'),
    ])
      PopupMenuItem(
        value: mode,
        height: math.max(
          72,
          textHeight(label, titleStyle, width - 96) +
              textHeight(detail, detailStyle, width - 96) +
              24,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Semantics(
          checked: settings.captureMode == mode,
          inMutuallyExclusiveGroup: true,
          child: Row(
            children: [
              Icon(
                mode == CaptureMode.scanner
                    ? Icons.document_scanner_outlined
                    : Icons.photo_camera_outlined,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: titleStyle),
                    Text(detail, style: detailStyle),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 20,
                child: settings.captureMode == mode
                    ? Icon(
                        Icons.check,
                        size: 20,
                        color: SuchiColors.of(context).accent,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
  ];
  painter.dispose();
  final menuHeight = items.fold(16.0, (sum, item) => sum + item.height);
  final selected = await showMenu<CaptureMode>(
    context: context,
    semanticLabel: title,
    constraints: BoxConstraints.tightFor(width: width),
    popUpAnimationStyle: SuchiMotion.standardStyle(context),
    clipBehavior: Clip.antiAlias,
    position: RelativeRect.fromLTRB(
      left.toDouble(),
      math.max(8.0, topLeft.dy - menuHeight - 8),
      overlay.size.width - left - width,
      overlay.size.height - topLeft.dy,
    ),
    items: items,
  );
  if (selected == null || !context.mounted) return null;
  try {
    await settings.setCaptureMode(selected);
    return selected;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera mode could not be saved. Try again.'),
        ),
      );
    }
    return null;
  }
}
