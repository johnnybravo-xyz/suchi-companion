import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/session_controller.dart';
import '../documents/document_list_mode.dart';
import '../offline/offline_document_store.dart';
import '../scan/scan_queue_store.dart';
import '../scan/scanner_bridge.dart';
import '../theme/suchi_theme.dart';
import '../widgets/suchi_widgets.dart';
import 'app_settings_controller.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({
    required this.session,
    required this.settings,
    required this.offlineDocuments,
    required this.queue,
    this.onOpenTrash,
    super.key,
  });

  final SessionController session;
  final AppSettingsController settings;
  final OfflineDocumentStore offlineDocuments;
  final ScanQueueStore queue;
  final VoidCallback? onOpenTrash;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  static final _website = Uri.parse('https://suchi.page');

  bool _savingTheme = false;
  bool _savingOcr = false;
  bool _choosingCaptureMode = false;
  bool _savingDocumentListMode = false;
  bool _retrying = false;
  VoidCallback? _concealAccountSheet;

  @override
  void didUpdateWidget(covariant MoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) _concealAccountSheet?.call();
  }

  @override
  void dispose() {
    _concealAccountSheet?.call();
    super.dispose();
  }

  Future<void> _openWebApp(BuildContext context) async {
    final origin = widget.session.origin;
    if (origin == null ||
        !await launchUrl(origin, mode: LaunchMode.externalApplication)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The Suchi web app could not be opened.')),
      );
    }
  }

  Future<void> _openWebsite(BuildContext context) async {
    bool opened;
    try {
      opened = await launchUrl(_website, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The Suchi website could not be opened.')),
      );
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of Suchi Companion?'),
        content: const Text(
          'Offline document copies will be removed from this device. Queued files stay protected and will not upload to another account unless you explicitly assign or discard them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final signedOut = await widget.session.signOut();
    if (signedOut || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign-out not completed'),
        content: const Text(
          'Suchi Companion could not remove the saved credential from this device, so you are still signed in. Try again before handing the device to someone else.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<T?> _showSettingsSheet<T>({
    required String title,
    required WidgetBuilder builder,
    bool accountBearing = false,
  }) async {
    final session = widget.session;
    final identity = session.identity;
    ModalRoute<T>? ownedRoute;
    var invalidated = false;

    bool sameAccount() =>
        !invalidated &&
        (session.state == SessionState.signedIn ||
            session.state == SessionState.offline) &&
        session.identity == identity;

    void conceal() {
      invalidated = true;
      // Remove only this sheet, even if another route has since opened above it.
      // A microtask also makes removal safe when More is being disposed in build.
      scheduleMicrotask(() {
        final route = ownedRoute;
        if (route != null && route.isActive) {
          route.navigator?.removeRoute(route);
        }
      });
    }

    void accountChanged() {
      if (!sameAccount()) conceal();
    }

    if (accountBearing) {
      if (identity == null || !sameAccount()) return null;
      _concealAccountSheet?.call();
      _concealAccountSheet = conceal;
      session.addListener(accountChanged);
    }
    try {
      final result = await showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: SuchiColors.of(context).paper,
        sheetAnimationStyle: SuchiMotion.sheetStyle(context),
        clipBehavior: Clip.antiAlias,
        builder: (context) {
          ownedRoute = ModalRoute.of<T>(context);
          return ListenableBuilder(
            listenable: session,
            builder: (context, _) {
              if (accountBearing && !sameAccount()) {
                conceal();
                return const SizedBox.shrink();
              }
              final colors = SuchiColors.of(context);
              return LayoutBuilder(
                builder: (context, constraints) => ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.85,
                  ),
                  child: Material(
                    color: colors.paper,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              20,
                              8,
                              20,
                              24 + MediaQuery.viewInsetsOf(context).bottom,
                            ),
                            child: ListTileTheme(
                              data: _rowTheme(context),
                              child: Builder(builder: builder),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
      return accountBearing && !sameAccount() ? null : result;
    } finally {
      if (accountBearing) {
        session.removeListener(accountChanged);
        if (identical(_concealAccountSheet, conceal)) {
          _concealAccountSheet = null;
        }
      }
    }
  }

  Future<void> _chooseTheme() async {
    if (_savingTheme || !widget.settings.loaded) return;
    final settings = widget.settings;
    setState(() => _savingTheme = true);
    try {
      final selected = await _showSettingsSheet<ThemeMode>(
        title: 'Appearance',
        builder: (context) => ListenableBuilder(
          listenable: settings,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in ThemeMode.values)
                Semantics(
                  checked: settings.themeMode == mode,
                  inMutuallyExclusiveGroup: true,
                  child: ListTile(
                    leading: Icon(_themeIcon(mode)),
                    title: Text(_themeLabel(mode)),
                    subtitle: mode == ThemeMode.system
                        ? const Text('Follow device appearance')
                        : null,
                    selected: settings.themeMode == mode,
                    trailing: settings.themeMode == mode
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.pop(context, mode),
                  ),
                ),
            ],
          ),
        ),
      );
      if (selected != null) await settings.setThemeMode(selected);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Theme preference could not be saved. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingTheme = false);
    }
  }

  Future<void> _chooseDocumentView() async {
    if (_savingDocumentListMode || !widget.settings.loaded) return;
    final settings = widget.settings;
    setState(() => _savingDocumentListMode = true);
    try {
      final selected = await _showSettingsSheet<DocumentListMode>(
        title: 'Document view',
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in DocumentListMode.values)
              Semantics(
                checked: settings.documentListMode == mode,
                inMutuallyExclusiveGroup: true,
                child: ListTile(
                  leading: Icon(_viewIcon(mode)),
                  title: Text(_viewLabel(mode)),
                  subtitle: Text(switch (mode) {
                    DocumentListMode.standard => 'Current roomy cards',
                    DocumentListMode.compact =>
                      'More documents, still easy to scan',
                    DocumentListMode.detailed =>
                      'Larger previews and more metadata',
                  }),
                  selected: settings.documentListMode == mode,
                  trailing: settings.documentListMode == mode
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, mode),
                ),
              ),
          ],
        ),
      );
      if (selected != null) await settings.setDocumentListMode(selected);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document view could not be saved. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingDocumentListMode = false);
    }
  }

  Future<void> _setServerOcrOnly(bool value) async {
    if (_savingOcr || !widget.settings.loaded) return;
    setState(() => _savingOcr = true);
    try {
      await widget.settings.setServerOcrOnly(value);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Capture preference could not be saved. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingOcr = false);
    }
  }

  Future<void> _chooseCaptureMode() async {
    if (_choosingCaptureMode || !widget.settings.loaded) return;
    final settings = widget.settings;
    setState(() => _choosingCaptureMode = true);
    try {
      final selected = await _showSettingsSheet<CaptureMode>(
        title: 'Camera mode',
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in CaptureMode.values)
              Semantics(
                checked: settings.captureMode == mode,
                inMutuallyExclusiveGroup: true,
                child: ListTile(
                  leading: Icon(
                    mode == CaptureMode.scanner
                        ? Icons.document_scanner_outlined
                        : Icons.photo_camera_outlined,
                  ),
                  title: Text(
                    mode == CaptureMode.scanner ? 'Scanner' : 'Photo',
                  ),
                  subtitle: Text(
                    mode == CaptureMode.scanner
                        ? 'Clean up pages'
                        : 'Keep full frame',
                  ),
                  selected: settings.captureMode == mode,
                  trailing: settings.captureMode == mode
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, mode),
                ),
              ),
          ],
        ),
      );
      if (selected != null) await settings.setCaptureMode(selected);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera mode could not be saved. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _choosingCaptureMode = false);
    }
  }

  Future<void> _showAccountDetails() async {
    final session = widget.session;
    final user = session.user;
    final origin = session.origin;
    final client = session.client;
    final identity = session.identity;
    if (user == null || origin == null || identity == null) return;
    await _showSettingsSheet<void>(
      title: 'Account details',
      accountBearing: true,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SectionLabel('Verified host'),
          const SizedBox(height: 6),
          SelectableText(user.instanceHost),
          const SizedBox(height: 18),
          const SectionLabel('Server address'),
          const SizedBox(height: 6),
          SelectableText(origin.toString()),
          const SizedBox(height: 18),
          const SectionLabel('Account'),
          const SizedBox(height: 6),
          SelectableText(user.label),
          if (user.label != user.email) ...[
            const SizedBox(height: 4),
            SelectableText(user.email),
          ],
          const SizedBox(height: 18),
          const SectionLabel('Filing system'),
          const SizedBox(height: 6),
          SelectableText(
            user.systemCode.isEmpty
                ? user.systemName
                : '${user.systemCode} · ${user.systemName}',
          ),
          const SizedBox(height: 6),
          Text(
            'Pair this device again to use a different filing system.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: SuchiColors.of(context).muted),
          ),
          if (client != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                if (identical(session.client, client) &&
                    session.identity == identity &&
                    session.state == SessionState.signedIn) {
                  _openWebApp(context);
                }
              },
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open Suchi web app'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _retryConnection() async {
    if (_retrying || !widget.session.canRetryStoredCredentials) return;
    setState(() => _retrying = true);
    await widget.session.retryStoredCredentials();
    if (!mounted) return;
    setState(() => _retrying = false);
    if (widget.session.state == SessionState.offline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suchi is still unavailable.')),
      );
    }
  }

  Future<void> _showPrivacyDetails() => _showSettingsSheet<void>(
    title: 'Privacy & storage',
    builder: (context) => _StorageManager(
      session: widget.session,
      offlineDocuments: widget.offlineDocuments,
      queue: widget.queue,
    ),
  );

  ListTileThemeData _rowTheme(BuildContext context) {
    final colors = SuchiColors.of(context);
    return ListTileThemeData(
      minTileHeight: 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      iconColor: colors.muted,
      textColor: colors.ink,
      titleTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: colors.ink,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: colors.muted, fontSize: 12),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: ListenableBuilder(
      listenable: Listenable.merge([widget.settings, widget.session]),
      builder: (context, _) {
        final colors = SuchiColors.of(context);
        final user = widget.session.user;
        final offline = widget.session.state == SessionState.offline;
        return ListTileTheme(
          data: _rowTheme(context).copyWith(
            minTileHeight: 52,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const ExcludeSemantics(child: BrandMark(size: 40)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Suchi Companion',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Capture on your phone. Keep it in your archive.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (user != null)
                SuchiCard(
                  elevated: false,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colors.manila,
                      foregroundColor: colors.ink,
                      child: Text(
                        initialsFor(user.label),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(user.instanceHost),
                    subtitle: Text(user.label),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showAccountDetails,
                  ),
                ),
              const SizedBox(height: 12),
              if (offline) ...[
                SuchiCard(
                  elevated: false,
                  child: ListTile(
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: const Text('Working offline'),
                    subtitle: const Text(
                      'Saved documents and Scan remain available. Uploads wait for verification.',
                    ),
                    trailing: _retrying
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: widget.session.canRetryStoredCredentials
                                ? _retryConnection
                                : null,
                            child: const Text('Retry'),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SuchiCard(
                elevated: false,
                child: Column(
                  children: [
                    _PreferenceTile(
                      icon: _themeIcon(widget.settings.themeMode),
                      title: 'Appearance',
                      value: _themeLabel(widget.settings.themeMode),
                      enabled: widget.settings.loaded && !_savingTheme,
                      onTap: _chooseTheme,
                    ),
                    Divider(height: 1, thickness: 1, color: colors.line),
                    _PreferenceTile(
                      icon: _viewIcon(widget.settings.documentListMode),
                      title: 'Document view',
                      value: _viewLabel(widget.settings.documentListMode),
                      enabled:
                          widget.settings.loaded && !_savingDocumentListMode,
                      onTap: _chooseDocumentView,
                    ),
                    Divider(height: 1, thickness: 1, color: colors.line),
                    _PreferenceTile(
                      icon: Icons.photo_camera_outlined,
                      title: 'Camera mode',
                      value: widget.settings.captureMode == CaptureMode.scanner
                          ? 'Scanner'
                          : 'Photo',
                      enabled: widget.settings.loaded && !_choosingCaptureMode,
                      onTap: _chooseCaptureMode,
                    ),
                    Divider(height: 1, thickness: 1, color: colors.line),
                    SwitchListTile(
                      key: const ValueKey('server-ocr-only'),
                      contentPadding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
                      title: const Text('Server OCR only'),
                      secondary: const Icon(Icons.privacy_tip_outlined),
                      value: widget.settings.serverOcrOnly,
                      onChanged: widget.settings.loaded && !_savingOcr
                          ? _setServerOcrOnly
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SuchiCard(
                elevated: false,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('Trash'),
                      subtitle: offline
                          ? const Text('Available when connected')
                          : null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: offline ? null : widget.onOpenTrash,
                    ),
                    Divider(height: 1, thickness: 1, color: colors.line),
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: const Text('Privacy & storage'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showPrivacyDetails,
                    ),
                    Divider(height: 1, thickness: 1, color: colors.line),
                    ListTile(
                      leading: const Icon(Icons.open_in_browser_outlined),
                      title: const Text('Explore Suchi'),
                      subtitle: const Text('suchi.page'),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => _openWebsite(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: colors.danger,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => _signOut(context),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

final class _DeviceStorageUsage {
  const _DeviceStorageUsage({
    required this.availableBytes,
    required this.queueCount,
    required this.queueBytes,
  });

  final int availableBytes;
  final int queueCount;
  final int queueBytes;
}

class _StorageManager extends StatefulWidget {
  const _StorageManager({
    required this.session,
    required this.offlineDocuments,
    required this.queue,
  });

  final SessionController session;
  final OfflineDocumentStore offlineDocuments;
  final ScanQueueStore queue;

  @override
  State<_StorageManager> createState() => _StorageManagerState();
}

class _StorageManagerState extends State<_StorageManager> {
  late Future<_DeviceStorageUsage> _usage = _loadUsage();
  bool _removing = false;

  Future<_DeviceStorageUsage> _loadUsage() async {
    final queue = await widget.queue.storageUsage();
    final available = await widget.offlineDocuments.availableBytes();
    return _DeviceStorageUsage(
      availableBytes: available,
      queueCount: queue.itemCount,
      queueBytes: queue.byteSize,
    );
  }

  Future<void> _removeOffline({required bool otherAccounts}) async {
    if (_removing) return;
    final identity = widget.session.identity;
    if (identity == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          otherAccounts
              ? 'Remove other account copies?'
              : 'Remove this account’s offline copies?',
        ),
        content: Text(
          otherAccounts
              ? 'This removes saved copies left by signed-out or expired accounts, including any unfinished sign-out cleanup. Current-account copies and queued uploads are not removed.'
              : 'This removes saved document copies for the current account. Queued uploads are not removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove copies'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing = true);
    try {
      if (otherAccounts) {
        await widget.offlineDocuments.clearOtherAccounts(identity);
      } else {
        await widget.offlineDocuments.clearAccount(identity);
      }
      if (mounted) setState(() => _usage = _loadUsage());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline copies could not be removed. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.offlineDocuments,
    builder: (context, _) {
      final identity = widget.session.identity;
      final accountCount = widget.offlineDocuments.entriesFor(identity).length;
      final accountBytes = widget.offlineDocuments.totalBytesFor(identity);
      final totalCount = widget.offlineDocuments.totalCount;
      final totalBytes = widget.offlineDocuments.totalBytes;
      final orphanedCount = identity == null
          ? totalCount
          : widget.offlineDocuments.orphanedCountFor(identity);
      final orphanedBytes = identity == null
          ? totalBytes
          : widget.offlineDocuments.orphanedBytesFor(identity);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'No analytics, ads, remote crash reporting, or document relay.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Credentials use device-only secure storage. Queued files and offline document copies stay protected on this device and are excluded from cloud backup.',
          ),
          const SizedBox(height: 24),
          const SectionLabel('Current account'),
          const SizedBox(height: 8),
          Text(
            identity == null
                ? 'No active account'
                : '${_itemCount(accountCount, 'offline copy', 'offline copies')} · ${_formatStorageBytes(accountBytes)}',
            key: const ValueKey('account-storage-usage'),
          ),
          if (identity != null && accountCount > 0) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('remove-account-offline'),
              onPressed: _removing
                  ? null
                  : () => _removeOffline(otherAccounts: false),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove account copies'),
            ),
          ],
          const SizedBox(height: 24),
          const SectionLabel('On this device'),
          const SizedBox(height: 8),
          Text(
            '${_itemCount(totalCount, 'offline copy', 'offline copies')} · ${_formatStorageBytes(totalBytes)}',
            key: const ValueKey('device-offline-usage'),
          ),
          const SizedBox(height: 6),
          FutureBuilder<_DeviceStorageUsage>(
            future: _usage,
            builder: (context, snapshot) {
              final usage = snapshot.data;
              if (usage == null) {
                return Text(
                  snapshot.hasError
                      ? 'Queue and free-space details unavailable'
                      : 'Checking queue and free space…',
                );
              }
              return Text(
                '${_itemCount(usage.queueCount, 'queued item')} · '
                '${_formatStorageBytes(usage.queueBytes)} queued\n'
                '${_formatStorageBytes(usage.availableBytes)} available',
                key: const ValueKey('device-storage-usage'),
              );
            },
          ),
          if (identity != null && orphanedCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${_itemCount(orphanedCount, 'copy', 'copies')} from signed-out or expired accounts · ${_formatStorageBytes(orphanedBytes)}',
              key: const ValueKey('orphaned-offline-usage'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('remove-other-offline'),
              onPressed: _removing
                  ? null
                  : () => _removeOffline(otherAccounts: true),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Remove other account copies'),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Manage unresolved uploads individually in Scan. Suchi Companion never evicts queued files or offline copies automatically.',
          ),
          const SizedBox(height: 24),
          const SectionLabel('Server OCR only'),
          const SizedBox(height: 8),
          const Text(
            'Uploads started while this is on omit text recognized on this phone. Suchi will extract or OCR the document instead.',
          ),
        ],
      );
    },
  );
}

String _itemCount(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : plural ?? '${singular}s'}';

String _formatStorageBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inlineValue =
          constraints.maxWidth >= 300 &&
          MediaQuery.textScalerOf(context).scale(15) <= 20;
      return ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: inlineValue ? null : Text(value),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (inlineValue) ...[
              Text(value, style: ListTileTheme.of(context).subtitleTextStyle),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.chevron_right),
          ],
        ),
        enabled: enabled,
        onTap: onTap,
      );
    },
  );
}

String _themeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};

IconData _themeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.system => Icons.brightness_auto_outlined,
  ThemeMode.light => Icons.light_mode_outlined,
  ThemeMode.dark => Icons.dark_mode_outlined,
};

String _viewLabel(DocumentListMode mode) => switch (mode) {
  DocumentListMode.standard => 'Standard',
  DocumentListMode.compact => 'Compact',
  DocumentListMode.detailed => 'Detailed',
};

IconData _viewIcon(DocumentListMode mode) => switch (mode) {
  DocumentListMode.standard => Icons.view_agenda_outlined,
  DocumentListMode.compact => Icons.view_list_outlined,
  DocumentListMode.detailed => Icons.view_day_outlined,
};
