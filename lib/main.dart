import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_licenses.dart';
import 'app/app_services.dart';
import 'app/lifecycle_privacy_shield.dart';
import 'auth/pair_screen.dart';
import 'auth/session_controller.dart';
import 'scan/scan_database.dart';
import 'shell/shell.dart';
import 'theme/suchi_theme.dart';
import 'widgets/suchi_widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicenses();
  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<AppServices> _services;

  @override
  void initState() {
    super.initState();
    _services = AppServices.create();
  }

  void _retry() => setState(() => _services = AppServices.create());

  @override
  Widget build(BuildContext context) => FutureBuilder<AppServices>(
    future: _services,
    builder: (context, snapshot) {
      if (snapshot.data case final services?) {
        return SuchiMobileApp(services: services);
      }
      return MaterialApp(
        title: 'Suchi Companion',
        debugShowCheckedModeBanner: false,
        theme: SuchiTheme.light,
        darkTheme: SuchiTheme.dark,
        themeMode: ThemeMode.system,
        themeAnimationDuration:
            MediaQuery.maybeDisableAnimationsOf(context) == true
            ? Duration.zero
            : const Duration(milliseconds: 180),
        themeAnimationCurve: Curves.easeOutCubic,
        builder: _themedSystemChrome,
        scrollBehavior: const SuchiScrollBehavior(),
        home: Scaffold(
          body: SafeArea(
            child: snapshot.hasError
                ? EmptyState(
                    title: 'Suchi Companion could not start',
                    message: isUnsupportedLocalStorageError(snapshot.error)
                        ? UnsupportedLocalStorageException.message
                        : 'Protected local storage could not be opened. Check available device storage and try again.',
                    icon: Icons.error_outline,
                    action: FilledButton(
                      onPressed: _retry,
                      child: const Text('Try again'),
                    ),
                  )
                : const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BrandMark(size: 58),
                        SizedBox(height: 18),
                        CircularProgressIndicator(),
                      ],
                    ),
                  ),
          ),
        ),
      );
    },
  );
}

class SuchiMobileApp extends StatefulWidget {
  const SuchiMobileApp({required this.services, super.key});

  final AppServices services;

  @override
  State<SuchiMobileApp> createState() => _SuchiMobileAppState();
}

class _SuchiMobileAppState extends State<SuchiMobileApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.services.shareImport.start());
    });
  }

  @override
  void dispose() {
    unawaited(widget.services.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LifecyclePrivacyShield(
    onConceal: widget.services.thumbnails.clear,
    onResume: widget.services.onAppResumed,
    child: ListenableBuilder(
      listenable: widget.services.settings,
      builder: (context, _) => MaterialApp(
        title: 'Suchi Companion',
        debugShowCheckedModeBanner: false,
        theme: SuchiTheme.light,
        darkTheme: SuchiTheme.dark,
        themeMode: widget.services.settings.themeMode,
        themeAnimationDuration:
            MediaQuery.maybeDisableAnimationsOf(context) == true
            ? Duration.zero
            : const Duration(milliseconds: 180),
        themeAnimationCurve: Curves.easeOutCubic,
        builder: _themedSystemChrome,
        scrollBehavior: const SuchiScrollBehavior(),
        home: ListenableBuilder(
          listenable: widget.services.session,
          builder: (context, _) => switch (widget.services.session.state) {
            SessionState.loading => const _SessionLoadingScreen(),
            SessionState.signedIn || SessionState.offline => SuchiShell(
              key: ValueKey(widget.services.session.state),
              services: widget.services,
            ),
            SessionState.signedOut ||
            SessionState.verifying ||
            SessionState.expired => PairScreen(
              session: widget.services.session,
              offlineDocuments: widget.services.offlineDocuments,
            ),
          },
        ),
      ),
    ),
  );
}

Widget _themedSystemChrome(BuildContext context, Widget? child) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: SuchiColors.of(context).surface,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
    ),
    child: child ?? const SizedBox.shrink(),
  );
}

class _SessionLoadingScreen extends StatelessWidget {
  const _SessionLoadingScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(size: 58),
            SizedBox(height: 18),
            CircularProgressIndicator(),
          ],
        ),
      ),
    ),
  );
}
