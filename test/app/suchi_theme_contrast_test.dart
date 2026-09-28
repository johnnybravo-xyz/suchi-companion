import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_companion/theme/suchi_theme.dart';

void main() {
  test('semantic text colors meet WCAG AA across app surfaces', () {
    for (final entry in const {
      'light': SuchiColors.light,
      'dark': SuchiColors.dark,
    }.entries) {
      final colors = entry.value;
      final surfaces = {
        'paper': colors.paper,
        'surface': colors.surface,
        'surface2': colors.surface2,
        'tint': Color.alphaBlend(colors.tint, colors.surface),
        'manila': colors.manila,
      };
      final foregrounds = {
        'ink': colors.ink,
        'muted': colors.muted,
        'accent': colors.accent,
        'success': colors.success,
        'warning': colors.warning,
        'danger': colors.danger,
      };
      for (final foreground in foregrounds.entries) {
        for (final background in surfaces.entries) {
          _expectContrast(
            foreground.value,
            background.value,
            minimum: 4.5,
            description: '${entry.key} ${foreground.key} on ${background.key}',
          );
        }
      }
      for (final background in {
        'accent': colors.accent,
        'success': colors.success,
        'danger': colors.danger,
      }.entries) {
        _expectContrast(
          colors.onAccent,
          background.value,
          minimum: 4.5,
          description: '${entry.key} onAccent on ${background.key}',
        );
      }
      for (final background in {
        'paper': colors.paper,
        'surface': colors.surface,
      }.entries) {
        _expectContrast(
          colors.lineStrong,
          background.value,
          minimum: 3,
          description: '${entry.key} control outline on ${background.key}',
        );
      }
    }
  });
}

void _expectContrast(
  Color foreground,
  Color background, {
  required double minimum,
  required String description,
}) {
  final light = foreground.computeLuminance();
  final dark = background.computeLuminance();
  final ratio =
      (light > dark ? light + 0.05 : dark + 0.05) /
      (light > dark ? dark + 0.05 : light + 0.05);
  expect(ratio, greaterThanOrEqualTo(minimum), reason: description);
}
