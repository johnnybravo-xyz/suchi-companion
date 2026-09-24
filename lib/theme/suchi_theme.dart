import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@immutable
final class SuchiColors extends ThemeExtension<SuchiColors> {
  const SuchiColors({
    required this.paper,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.onAccent,
    required this.tint,
    required this.manila,
    required this.success,
    required this.warning,
    required this.danger,
    required this.camera,
    required this.line,
    required this.lineStrong,
  });

  final Color paper;
  final Color surface;
  final Color surface2;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color accent;
  final Color onAccent;
  final Color tint;
  final Color manila;
  final Color success;
  final Color warning;
  final Color danger;
  final Color camera;
  final Color line;
  final Color lineStrong;

  static const light = SuchiColors(
    paper: Color(0xFFFAFAF8),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF1F1ED),
    ink: Color(0xFF17181A),
    muted: Color(0xFF6A7079),
    faint: Color(0xFF8A8F97),
    accent: Color(0xFF0575B6),
    onAccent: Color(0xFFFFFFFF),
    tint: Color(0xFFEDF5FA),
    manila: Color(0xFFF2E8CE),
    success: Color(0xFF1E7A54),
    warning: Color(0xFFB4541F),
    danger: Color(0xFFC13A2C),
    camera: Color(0xFF0F1519),
    line: Color(0x1C17181A),
    lineStrong: Color(0x3317181A),
  );

  static const dark = SuchiColors(
    paper: Color(0xFF141618),
    surface: Color(0xFF1D2023),
    surface2: Color(0xFF23262A),
    ink: Color(0xFFECEAE2),
    muted: Color(0xFF9C9A90),
    faint: Color(0xFF7E7C72),
    accent: Color(0xFF4FA8DC),
    onAccent: Color(0xFF10222E),
    tint: Color.fromRGBO(79, 168, 220, 0.12),
    manila: Color(0xFF38342A),
    success: Color(0xFF68C398),
    warning: Color(0xFFE09A5F),
    danger: Color(0xFFF0765C),
    camera: Color(0xFF0F1519),
    line: Color.fromRGBO(236, 234, 226, 0.09),
    lineStrong: Color.fromRGBO(236, 234, 226, 0.17),
  );

  static SuchiColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<SuchiColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  SuchiColors copyWith({
    Color? paper,
    Color? surface,
    Color? surface2,
    Color? ink,
    Color? muted,
    Color? faint,
    Color? accent,
    Color? onAccent,
    Color? tint,
    Color? manila,
    Color? success,
    Color? warning,
    Color? danger,
    Color? camera,
    Color? line,
    Color? lineStrong,
  }) => SuchiColors(
    paper: paper ?? this.paper,
    surface: surface ?? this.surface,
    surface2: surface2 ?? this.surface2,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    faint: faint ?? this.faint,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    tint: tint ?? this.tint,
    manila: manila ?? this.manila,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    camera: camera ?? this.camera,
    line: line ?? this.line,
    lineStrong: lineStrong ?? this.lineStrong,
  );

  @override
  SuchiColors lerp(covariant SuchiColors? other, double t) {
    if (other == null) return this;
    return SuchiColors(
      paper: Color.lerp(paper, other.paper, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      tint: Color.lerp(tint, other.tint, t)!,
      manila: Color.lerp(manila, other.manila, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      camera: Color.lerp(camera, other.camera, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
    );
  }
}

abstract final class SuchiTheme {
  static const uiFont = 'Schibsted Grotesk';
  static const monoFont = 'Spline Sans Mono';

  static final ThemeData light = _build(SuchiColors.light, Brightness.light);
  static final ThemeData dark = _build(SuchiColors.dark, Brightness.dark);

  static ThemeData _build(SuchiColors colors, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      primaryContainer: colors.tint,
      onPrimaryContainer: colors.ink,
      secondary: colors.manila,
      onSecondary: colors.ink,
      secondaryContainer: colors.manila,
      onSecondaryContainer: colors.ink,
      tertiary: colors.accent,
      onTertiary: colors.onAccent,
      tertiaryContainer: colors.tint,
      onTertiaryContainer: colors.ink,
      error: colors.danger,
      onError: colors.onAccent,
      errorContainer: colors.danger.withValues(alpha: isDark ? 0.13 : 0.10),
      onErrorContainer: colors.ink,
      surface: colors.surface,
      onSurface: colors.ink,
      onSurfaceVariant: colors.muted,
      surfaceDim: colors.paper,
      surfaceBright: colors.surface,
      surfaceContainerLowest: colors.paper,
      surfaceContainerLow: colors.surface,
      surfaceContainer: colors.surface,
      surfaceContainerHigh: colors.surface2,
      surfaceContainerHighest: colors.surface2,
      inverseSurface: colors.ink,
      onInverseSurface: colors.surface,
      inversePrimary: isDark
          ? SuchiColors.light.accent
          : SuchiColors.dark.accent,
      surfaceTint: colors.accent,
      outline: colors.faint,
      outlineVariant: colors.line,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [colors],
      fontFamily: uiFont,
      scaffoldBackgroundColor: colors.paper,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _SuchiPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: _SuchiPageTransitionsBuilder(),
          TargetPlatform.windows: _SuchiPageTransitionsBuilder(),
          TargetPlatform.linux: _SuchiPageTransitionsBuilder(),
          TargetPlatform.fuchsia: _SuchiPageTransitionsBuilder(),
        },
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: TextStyle(
          fontFamily: uiFont,
          fontSize: 35,
          height: 1.05,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.2,
          color: colors.ink,
        ),
        headlineMedium: TextStyle(
          fontFamily: uiFont,
          fontSize: 27,
          height: 1.1,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: colors.ink,
        ),
        headlineSmall: TextStyle(
          fontFamily: uiFont,
          fontSize: 22,
          height: 1.15,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: colors.ink,
        ),
        titleMedium: TextStyle(
          fontFamily: uiFont,
          fontSize: 15,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: colors.ink,
        ),
        bodyMedium: TextStyle(
          fontFamily: uiFont,
          fontSize: 14,
          height: 1.45,
          color: colors.ink,
        ),
        bodySmall: TextStyle(
          fontFamily: uiFont,
          fontSize: 12,
          height: 1.4,
          color: colors.muted,
        ),
        labelLarge: const TextStyle(
          fontFamily: uiFont,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.paper,
        foregroundColor: colors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: brightness,
          systemNavigationBarColor: colors.surface,
          systemNavigationBarIconBrightness: isDark
              ? Brightness.light
              : Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          fontFamily: uiFont,
          color: colors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(17)),
          side: BorderSide(color: colors.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.paper,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.paper,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        color: colors.line,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          disabledBackgroundColor: colors.surface2,
          disabledForegroundColor: colors.faint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: uiFont,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          foregroundColor: colors.ink,
          side: BorderSide(color: colors.lineStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: uiFont,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: colors.accent,
          textStyle: const TextStyle(
            fontFamily: uiFont,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: colors.lineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: colors.lineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: colors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: colors.danger),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.accent,
        selectionColor: colors.accent.withValues(alpha: isDark ? 0.30 : 0.20),
        selectionHandleColor: colors.accent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(
          fontFamily: uiFont,
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.tint,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: uiFont,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.surface2,
        circularTrackColor: colors.surface2,
      ),
    );
  }

  static const TextStyle monoLabel = TextStyle(
    fontFamily: monoFont,
    fontSize: 10,
    height: 1,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );
}

abstract final class SuchiMotion {
  static Duration fast(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 120);

  static Duration standard(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 180);

  static AnimationStyle standardStyle(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: Duration(milliseconds: 180),
          reverseDuration: Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

  static AnimationStyle sheetStyle(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: Duration(milliseconds: 240),
          reverseDuration: Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
}

final class SuchiScrollBehavior extends MaterialScrollBehavior {
  const SuchiScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

final class _SuchiPageTransitionsBuilder extends PageTransitionsBuilder {
  const _SuchiPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.settings.name == Navigator.defaultRouteName) return child;
    return FadeTransition(opacity: animation, child: child);
  }
}
