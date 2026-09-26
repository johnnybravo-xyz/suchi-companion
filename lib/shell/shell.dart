import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../app/app_services.dart';
import '../auth/account_identity.dart';
import '../detail/document_detail_screen.dart';
import '../documents/document_list_mode.dart';
import '../documents/documents_screen.dart';
import '../documents/jd_category_store.dart';
import '../inbox/inbox_screen.dart';
import '../more/more_screen.dart';
import '../offline/offline_document_store.dart';
import '../scan/capture_mode_picker.dart';
import '../scan/scan_database.dart';
import '../scan/scan_queue_screen.dart';
import '../scan/scan_queue_store.dart';
import '../scan/scanner_bridge.dart';
import '../search/saved_views.dart';
import '../search/search_screen.dart';
import '../share/share_import_controller.dart';
import '../theme/suchi_theme.dart';
import '../trash/trash_screen.dart';

class SuchiShell extends StatefulWidget {
  const SuchiShell({required this.services, super.key});

  final AppServices services;

  @override
  State<SuchiShell> createState() => _SuchiShellState();
}

class _SuchiShellState extends State<SuchiShell> {
  SuchiClient? get _client => widget.services.session.client;
  JdCategoryStore? _categories;
  SuchiClient? _categoryClient;
  late final SavedViewController _savedViews;
  int _selected = 0;
  bool _startupInboxPending = true;
  int _searchFocusSerial = 0;
  int? _searchFocusRequest;
  SavedView? _requestedSavedView;
  int _savedViewRevision = 0;
  bool _choosingCaptureMode = false;
  int _readerRevision = 0;
  late DocumentListMode _listMode;
  final _queueRows = ValueNotifier<List<ScanUpload>>(const []);
  final _queueUnavailable = ValueNotifier<bool>(false);
  late final StreamSubscription<List<ScanUpload>> _queueSubscription;
  AccountIdentity? _observedIdentity;
  Map<String, String>? _previousQueueStates;

  @override
  void initState() {
    super.initState();
    _listMode = widget.services.settings.documentListMode;
    widget.services.settings.addListener(_settingsChanged);
    _updateClient();
    if (_client == null) _startupInboxPending = false;
    _savedViews = SavedViewController(session: widget.services.session);
    _syncIdentity();
    widget.services.session.addListener(_sessionChanged);
    _queueSubscription = widget.services.queue.watchUploads().listen(
      _queueChanged,
      onError: (Object error, StackTrace stack) {
        if (mounted) _queueUnavailable.value = true;
      },
    );
  }

  @override
  void dispose() {
    widget.services.settings.removeListener(_settingsChanged);
    widget.services.session.removeListener(_sessionChanged);
    unawaited(_queueSubscription.cancel());
    _queueRows.dispose();
    _queueUnavailable.dispose();
    _categories?.dispose();
    _savedViews.dispose();
    super.dispose();
  }

  void _settingsChanged() {
    final mode = widget.services.settings.documentListMode;
    if (_listMode != mode) setState(() => _listMode = mode);
  }

  void _updateClient() {
    final client = _client;
    if (client == _categoryClient) return;
    _categories?.dispose();
    _categoryClient = client;
    _categories = client == null
        ? null
        : JdCategoryStore(
            client: client,
            onUnauthorized: widget.services.session.expire,
          );
    _categories?.load();
  }

  void _sessionChanged() {
    final clientChanged = _categoryClient != _client;
    if (clientChanged) _updateClient();
    _syncIdentity();
    if (clientChanged && mounted) setState(() {});
  }

  AccountIdentity? get _currentIdentity => widget.services.session.identity;

  void _syncIdentity() {
    final identity = _currentIdentity;
    if (_observedIdentity == identity) return;
    final previous = _observedIdentity;
    _observedIdentity = identity;
    if (previous != null) _startupInboxPending = false;
    _previousQueueStates = null;
    if (previous != null && mounted) {
      setState(() {
        _requestedSavedView = null;
        _savedViewRevision++;
      });
    }
  }

  void _queueChanged(List<ScanUpload> rows) {
    if (!mounted) return;
    _syncIdentity();
    final identity = _currentIdentity;
    final states = <String, String>{};
    var completed = false;
    if (identity != null) {
      for (final row in visibleQueueUploads(rows, identity)) {
        if (!queueUploadBelongsToIdentity(row, identity)) continue;
        states[row.id] = row.state;
        final previous = _previousQueueStates?[row.id];
        if (previous != null &&
            previous != 'filed' &&
            previous != 'duplicate' &&
            (row.state == 'filed' || row.state == 'duplicate')) {
          completed = true;
        }
      }
    }
    _previousQueueStates = states;
    _queueUnavailable.value = false;
    _queueRows.value = rows;
    if (completed) _refreshArchive();
  }

  void _openQueue() => setState(() {
    _startupInboxPending = false;
    _selected = 2;
  });

  void _select(int index) {
    _startupInboxPending = false;
    setState(() {
      _selected = index;
      _searchFocusRequest = null;
    });
    if (index == 2) _capture();
  }

  void _openSearchFromDocuments() {
    _startupInboxPending = false;
    setState(() {
      _selected = 3;
      _searchFocusRequest = ++_searchFocusSerial;
    });
  }

  void _initialInboxLoaded(
    SuchiClient client,
    AccountIdentity? identity,
    bool empty,
  ) {
    if (!mounted ||
        !_startupInboxPending ||
        _selected != 0 ||
        _client != client ||
        _currentIdentity != identity) {
      return;
    }
    _startupInboxPending = false;
    if (empty) setState(() => _selected = 1);
  }

  void _capture() {
    final services = widget.services;
    if (_currentIdentity == null ||
        _choosingCaptureMode ||
        !services.settings.loaded ||
        services.capture.isBusy ||
        services.capture.hasPendingCapture) {
      return;
    }
    unawaited(
      services.capture.captureAndStage(mode: services.settings.captureMode),
    );
  }

  Future<void> _chooseCaptureMode(Rect anchor) async {
    final services = widget.services;
    if (_currentIdentity == null ||
        _choosingCaptureMode ||
        !services.settings.loaded ||
        services.capture.isBusy ||
        services.capture.hasPendingCapture) {
      _openQueue();
      return;
    }
    _choosingCaptureMode = true;
    final identity = _currentIdentity;
    unawaited(HapticFeedback.selectionClick());
    try {
      final mode = await chooseCaptureMode(
        context,
        settings: services.settings,
        anchor: anchor,
      );
      if (!mounted || mode == null || _currentIdentity != identity) {
        return;
      }
      _choosingCaptureMode = false;
      _select(2);
    } finally {
      _choosingCaptureMode = false;
    }
  }

  void _refreshArchive() {
    if (!mounted || _client == null) return;
    setState(() => _readerRevision++);
  }

  void _openSavedView(SavedView view) {
    if (_client == null) return;
    setState(() {
      _requestedSavedView = view;
      _savedViewRevision++;
      _selected = 1;
    });
  }

  Future<void> _openDocument(int id) {
    final client = _client;
    final categories = _categories;
    if (client == null || categories == null) return Future.value();
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: RouteSettings(name: '/documents/$id'),
        builder: (context) => DocumentDetailScreen(
          documentId: id,
          client: client,
          session: widget.services.session,
          cache: widget.services.thumbnails,
          categories: categories,
          files: widget.services.documentFiles,
          offlineDocuments: widget.services.offlineDocuments,
          onChanged: _refreshArchive,
        ),
      ),
    );
  }

  Future<void> _openOfflineDocument(OfflineDocument entry) async {
    final identity = _currentIdentity;
    if (identity == null || entry.identity != identity) return;
    if (entry.document.isSensitive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Open sensitive document?'),
          content: const Text(
            'The document will be handed to another app and may remain visible there.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || _currentIdentity != identity) return;
    }
    if (!mounted || _currentIdentity != identity) return;
    try {
      await widget.services.offlineDocuments.handoff(
        identity: identity,
        entry: entry,
        share: false,
      );
    } catch (_) {
      if (!mounted || _currentIdentity != identity) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The offline document could not be opened.'),
        ),
      );
    }
  }

  Future<void> _openTrash() {
    final client = _client;
    if (client == null) return Future.value();
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/trash'),
        builder: (context) => TrashScreen(
          client: client,
          session: widget.services.session,
          onRestored: _refreshArchive,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    final categories = _categories;
    if (client == null || categories == null) {
      final offlineSelected = switch (_selected) {
        2 => 1,
        4 => 2,
        _ => 0,
      };
      final screens = <Widget>[
        DocumentsScreen(
          key: const ValueKey('offline-documents'),
          listMode: _listMode,
          client: null,
          session: widget.services.session,
          cache: widget.services.thumbnails,
          categories: null,
          offlineDocuments: widget.services.offlineDocuments,
          network: widget.services.network,
          onOpenSearch: () {},
          onOpenDocument: (_) {},
          onOpenOfflineDocument: _openOfflineDocument,
        ),
        _scanQueueScreen(),
        MoreScreen(
          session: widget.services.session,
          settings: widget.services.settings,
        ),
      ];
      return Scaffold(
        body: IndexedStack(index: offlineSelected, children: screens),
        bottomNavigationBar: _queueDock(offlineOnly: true),
      );
    }
    final startupIdentity = _currentIdentity;
    final screens = <Widget>[
      InboxScreen(
        key: const ValueKey('inbox'),
        listMode: _listMode,
        refreshRevision: _readerRevision,
        client: client,
        session: widget.services.session,
        cache: widget.services.thumbnails,
        categories: categories,
        onOpenDocument: _openDocument,
        onInitialLoadComplete: (empty) =>
            _initialInboxLoaded(client, startupIdentity, empty),
      ),
      DocumentsScreen(
        key: const ValueKey('documents'),
        listMode: _listMode,
        refreshRevision: _readerRevision,
        savedView: _requestedSavedView,
        savedViewRevision: _savedViewRevision,
        client: client,
        session: widget.services.session,
        cache: widget.services.thumbnails,
        categories: categories,
        offlineDocuments: widget.services.offlineDocuments,
        network: widget.services.network,
        onOpenSearch: _openSearchFromDocuments,
        onOpenDocument: _openDocument,
        onOpenOfflineDocument: _openOfflineDocument,
      ),
      _scanQueueScreen(),
      SearchScreen(
        client: client,
        session: widget.services.session,
        cache: widget.services.thumbnails,
        onOpenDocument: _openDocument,
        onOpenSavedView: _openSavedView,
        savedViews: _savedViews,
        active: _selected == 3,
        focusRequest: _selected == 3 ? _searchFocusRequest : null,
      ),
      MoreScreen(
        session: widget.services.session,
        settings: widget.services.settings,
        onOpenTrash: _openTrash,
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: _selected, children: screens),
      bottomNavigationBar: _queueDock(),
    );
  }

  Widget _scanQueueScreen() => ScanQueueScreen(
    queue: widget.services.queue,
    capture: widget.services.capture,
    uploads: widget.services.uploads,
    session: widget.services.session,
    shareImport: widget.services.shareImport,
    settings: widget.services.settings,
    onScan: _capture,
    onOpenDocument: _openDocument,
  );

  Widget _queueDock({bool offlineOnly = false}) => ListenableBuilder(
    listenable: Listenable.merge([
      _queueRows,
      _queueUnavailable,
      widget.services.session,
      widget.services.shareImport,
      widget.services.uploads,
      widget.services.settings,
      widget.services.offlineDocuments,
    ]),
    builder: (context, _) {
      final identity = _currentIdentity;
      final rows = visibleQueueUploads(_queueRows.value, identity);
      final pending = rows
          .where((item) => item.state != 'filed' && item.state != 'duplicate')
          .length;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActivityBar(
            // Replace the animation subtree immediately on account change.
            key: ValueKey(identity),
            rows: rows,
            identity: identity,
            offlineDocuments: widget.services.offlineDocuments,
            importer: widget.services.shareImport,
            uploadsEnabled: widget.services.uploads.isActive,
            unavailable: _queueUnavailable.value,
            onView: _openQueue,
          ),
          _SuchiDock(
            selected: _selected,
            pendingCount: pending,
            onSelected: _select,
            captureMode: widget.services.settings.captureMode,
            onChooseCaptureMode: _chooseCaptureMode,
            offlineOnly: offlineOnly,
          ),
        ],
      );
    },
  );
}

class _Activity {
  const _Activity({
    required this.phase,
    required this.title,
    required this.detail,
    required this.icon,
    this.working = false,
    this.attention = false,
    this.progress,
  });

  final String phase;
  final String title;
  final String detail;
  final IconData icon;
  final bool working;
  final bool attention;
  final double? progress;
}

class _ActivityBar extends StatelessWidget {
  const _ActivityBar({
    required this.rows,
    required this.identity,
    required this.importer,
    required this.offlineDocuments,
    required this.uploadsEnabled,
    required this.unavailable,
    required this.onView,
    super.key,
  });

  final List<ScanUpload> rows;
  final AccountIdentity? identity;
  final ShareImportController importer;
  final OfflineDocumentStore offlineDocuments;
  final bool uploadsEnabled;
  final bool unavailable;
  final VoidCallback onView;

  _Activity? _activity() {
    ScanUpload? uploading;
    var queued = 0;
    var processing = 0;
    var failed = 0;
    var unassigned = 0;
    var processingRetry = false;
    var queuedRetry = false;
    for (final row in rows) {
      if (row.state == 'unassigned') {
        unassigned++;
        continue;
      }
      if (identity == null || !queueUploadBelongsToIdentity(row, identity!)) {
        continue;
      }
      final retry = row.lastErrorCode != null || row.lastErrorMessage != null;
      switch (row.state) {
        case 'uploading':
          uploading ??= row;
        case 'queued':
          queued++;
          queuedRetry |= retry;
        case 'processingServer':
          processing++;
          processingRetry |= retry;
        case 'uploadFailed':
        case 'processingFailed':
          failed++;
      }
    }
    final summary = importer.lastSummary;
    final importIssues = (summary?.failed ?? 0) + (summary?.rejected ?? 0);
    final importAttention = importIssues > 0 || importer.errorMessage != null;
    final attentionCount =
        failed + (importIssues > 0 ? importIssues : (importAttention ? 1 : 0));
    String documents(int count) =>
        '$count ${count == 1 ? 'document' : 'documents'}';
    _Activity describe(
      String phase,
      String title,
      String detail,
      IconData icon, {
      bool working = false,
      bool attention = false,
      double? progress,
      bool includeQueued = true,
      bool includeProcessing = true,
      bool includeAttention = true,
    }) {
      final extras = <String>[
        if (includeQueued && queued > 0) '$queued queued',
        if (includeProcessing && processing > 0) '$processing processing',
        if (includeAttention && attentionCount > 0)
          '$attentionCount ${attentionCount == 1 ? 'item needs' : 'items need'} attention',
      ];
      return _Activity(
        phase: phase,
        title: title,
        detail: [detail, ...extras].join(' · '),
        icon: icon,
        working: working,
        attention: attention,
        progress: progress,
      );
    }

    if (identity != null && offlineDocuments.savingIdentity == identity) {
      if (offlineDocuments.savingFinishing) {
        return describe(
          'finishingOffline',
          'Finishing offline copy',
          'Verifying the protected file',
          Icons.download_for_offline_outlined,
          working: true,
        );
      }
      return describe(
        'savingOffline',
        'Saving offline copy',
        'Keep Suchi Companion open',
        Icons.download_for_offline_outlined,
        working: true,
        progress: offlineDocuments.savingProgress,
      );
    }

    if (unavailable) {
      return describe(
        'unavailable',
        'Upload activity unavailable',
        'Open the queue to review saved documents',
        Icons.error_outline,
        attention: true,
      );
    }
    if (uploading != null && uploadsEnabled) {
      final row = uploading;
      if (row.byteSize > 0 && row.bytesSent >= row.byteSize) {
        return describe(
          'finishing',
          'Finishing upload',
          'Waiting for Suchi to accept the file',
          Icons.cloud_upload_outlined,
          working: true,
        );
      }
      return describe(
        'uploading',
        'Uploading 1 document',
        'Keep Suchi Companion open',
        Icons.cloud_upload_outlined,
        working: true,
        progress: row.byteSize > 0
            ? (row.bytesSent / row.byteSize).clamp(0.0, 1.0)
            : null,
      );
    }
    if (importer.phase == ShareImportPhase.staging) {
      return describe(
        'staging',
        'Preparing shared documents',
        'Saving securely on this device',
        Icons.save_alt,
        working: true,
      );
    }
    if (!uploadsEnabled && (queued + processing > 0 || uploading != null)) {
      final pending = queued + processing + (uploading == null ? 0 : 1);
      return describe(
        'paused',
        'Uploads paused',
        '${documents(pending)} pending',
        Icons.pause_circle_outline,
        includeQueued: false,
        includeProcessing: false,
      );
    }
    if (processing > 0 && processingRetry) {
      return describe(
        'processingRetry',
        'Waiting to check processing',
        'File uploaded; status check will retry',
        Icons.schedule,
      );
    }
    if (processing > 0) {
      return describe(
        'processing',
        'Processing ${documents(processing)}',
        'Uploaded · Processing in Suchi',
        Icons.hourglass_top,
        working: true,
        includeProcessing: false,
      );
    }
    if (importer.phase == ShareImportPhase.checking) {
      return describe(
        'checking',
        'Checking for shared documents',
        'Reading shared files from this device',
        Icons.file_download_outlined,
        working: true,
      );
    }
    if (failed > 0) {
      return describe(
        'failed',
        'Uploads need attention',
        '$attentionCount ${attentionCount == 1 ? 'item needs' : 'items need'} attention',
        Icons.error_outline,
        attention: true,
        includeAttention: false,
      );
    }
    if (importAttention) {
      return describe(
        'importAttention',
        'Shared import needs attention',
        'Some shared files could not be prepared',
        Icons.warning_amber_rounded,
        attention: true,
        includeAttention: false,
      );
    }
    if (unassigned > 0) {
      return describe(
        'unassigned',
        '${documents(unassigned)} ${unassigned == 1 ? 'needs' : 'need'} an account',
        'Choose Upload here in the queue',
        Icons.person_add_alt,
        attention: true,
      );
    }
    if (queued > 0 && queuedRetry) {
      return describe(
        'queuedRetry',
        'Waiting to retry',
        'Saved on this device',
        Icons.schedule,
      );
    }
    if (queued > 0) {
      return describe(
        'queued',
        '${documents(queued)} queued',
        'Saved on this device',
        Icons.cloud_upload_outlined,
        includeQueued: false,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    final activity = _activity();
    final duration = SuchiMotion.standard(context);
    final reverseDuration = duration == Duration.zero
        ? Duration.zero
        : const Duration(milliseconds: 140);
    final color = activity?.attention == true
        ? (activity?.phase == 'failed' || activity?.phase == 'unavailable'
              ? colors.danger
              : colors.warning)
        : colors.accent;
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 21;
    final offlineSaving =
        activity?.phase == 'savingOffline' ||
        activity?.phase == 'finishingOffline';
    final detail = activity?.progress == null
        ? activity?.detail
        : '${(activity!.progress! * 100).floor()}% '
              '${offlineSaving ? 'downloaded' : 'sent'} · ${activity.detail}';
    final view = activity == null
        ? null
        : TextButton(
            onPressed: offlineSaving ? offlineDocuments.cancelPending : onView,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(offlineSaving ? 'Cancel' : 'View'),
          );
    final child = AnimatedSwitcher(
      duration: duration,
      reverseDuration: reverseDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [
          for (final child in previousChildren)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ExcludeSemantics(child: IgnorePointer(child: child)),
            ),
          ?currentChild,
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, -6 * (1 - animation.value)),
            child: child,
          ),
        ),
      ),
      child: activity == null
          ? const SizedBox.shrink(key: ValueKey('idle'))
          : Column(
              key: ValueKey(activity.phase),
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: activity.attention
                      ? color.withValues(alpha: 0.12)
                      : colors.tint,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            if (!stacked) ...[
                              ExcludeSemantics(
                                child: Icon(
                                  activity.icon,
                                  color: color,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: Semantics(
                                container: true,
                                liveRegion: true,
                                label: '${activity.title}. $detail',
                                child: ExcludeSemantics(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        activity.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: colors.ink,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        detail!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: colors.muted),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (!stacked) ...[const SizedBox(width: 4), ?view],
                          ],
                        ),
                        if (stacked)
                          Row(
                            children: [
                              ExcludeSemantics(
                                child: Icon(
                                  activity.icon,
                                  color: color,
                                  size: 22,
                                ),
                              ),
                              const Spacer(),
                              ?view,
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                if (activity.working)
                  ExcludeSemantics(
                    child: activity.progress == null
                        ? LinearProgressIndicator(
                            minHeight: 3,
                            color: color,
                            backgroundColor: colors.line,
                          )
                        : TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: 0,
                              end: activity.progress!,
                            ),
                            duration: duration,
                            curve: Curves.easeOutCubic,
                            builder: (context, value, _) =>
                                LinearProgressIndicator(
                                  value: value,
                                  minHeight: 3,
                                  color: color,
                                  backgroundColor: colors.line,
                                ),
                          ),
                  ),
              ],
            ),
    );
    if (duration == Duration.zero) return child;
    return AnimatedSize(
      duration: duration,
      reverseDuration: reverseDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

class _SuchiDock extends StatelessWidget {
  const _SuchiDock({
    required this.selected,
    required this.pendingCount,
    required this.onSelected,
    required this.captureMode,
    required this.onChooseCaptureMode,
    this.offlineOnly = false,
  });

  final int selected;
  final int pendingCount;
  final ValueChanged<int> onSelected;
  final CaptureMode captureMode;
  final ValueChanged<Rect> onChooseCaptureMode;
  final bool offlineOnly;

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    final scaledLabel = MediaQuery.textScalerOf(context).scale(11);
    final height = math.max(86.0, 74 + scaledLabel);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ColoredBox(
      color: colors.paper,
      child: SizedBox(
        height: 32 + height + bottom,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned.fill(
              top: 32,
              child: Material(
                color: colors.surface,
                elevation: 8,
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      if (!offlineOnly)
                        Expanded(
                          child: _DockItem(
                            label: 'Inbox',
                            icon: Icons.inbox_outlined,
                            selected: selected == 0,
                            onTap: () => onSelected(0),
                          ),
                        ),
                      Expanded(
                        child: _DockItem(
                          label: 'Documents',
                          icon: Icons.folder_outlined,
                          selected: selected == (offlineOnly ? 0 : 1),
                          onTap: () => onSelected(offlineOnly ? 0 : 1),
                        ),
                      ),
                      const Expanded(child: SizedBox()),
                      if (!offlineOnly)
                        Expanded(
                          child: _DockItem(
                            label: 'Search',
                            icon: Icons.search,
                            selected: selected == 3,
                            onTap: () => onSelected(3),
                          ),
                        ),
                      Expanded(
                        child: _DockItem(
                          label: 'More',
                          icon: Icons.more_horiz,
                          selected: selected == 4,
                          onTap: () => onSelected(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              child: ScanDockButton(
                selected: selected == 2,
                pendingCount: pendingCount,
                onTap: () => onSelected(2),
                mode: captureMode,
                onLongPress: onChooseCaptureMode,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    final duration = SuchiMotion.fast(context);
    final color = selected ? colors.accent : colors.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        containedInkWell: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                width: 34,
                height: 28,
                duration: duration,
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: selected
                      ? colors.tint
                      : colors.tint.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: color),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) =>
                      Icon(icon, size: 22, color: value),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: duration,
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                child: Text(label, textAlign: TextAlign.center, maxLines: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScanDockButton extends StatefulWidget {
  const ScanDockButton({
    required this.selected,
    required this.pendingCount,
    required this.onTap,
    this.mode = CaptureMode.scanner,
    this.onLongPress,
    super.key,
  });

  final bool selected;
  final int pendingCount;
  final VoidCallback onTap;
  final CaptureMode mode;
  final ValueChanged<Rect>? onLongPress;

  @override
  State<ScanDockButton> createState() => _ScanDockButtonState();
}

class _ScanDockButtonState extends State<ScanDockButton> {
  bool _pressed = false;

  void _longPress() {
    setState(() => _pressed = false);
    final box = context.findRenderObject()! as RenderBox;
    widget.onLongPress?.call(box.localToGlobal(Offset.zero) & box.size);
  }

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    return Semantics(
      button: true,
      excludeSemantics: true,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress == null ? null : _longPress,
      hint: widget.onLongPress == null ? null : 'Touch and hold to choose Scanner or Photo, then tap a mode to capture',
      selected: widget.selected,
      label:
          '${widget.mode == CaptureMode.photo ? 'Take photo' : 'Scan document'}${widget.pendingCount == 0 ? '' : ', ${widget.pendingCount} queued'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress == null ? null : _longPress,
        onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
        enableFeedback: false,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1,
          duration: SuchiMotion.fast(context),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: SuchiColors.light.accent,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: colors.surface, width: 5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x4D0575B6),
                      blurRadius: 18,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: Icon(
                  widget.mode == CaptureMode.photo
                      ? Icons.photo_camera_outlined
                      : Icons.document_scanner_outlined,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              if (widget.pendingCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: colors.danger,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: colors.surface, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      widget.pendingCount > 99
                          ? '99+'
                          : '${widget.pendingCount}',
                      style: SuchiTheme.monoLabel.copyWith(
                        color: colors.onAccent,
                        fontSize: 8,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
