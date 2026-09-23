import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../auth/account_identity.dart';
import '../auth/session_controller.dart';
import '../more/app_settings_controller.dart';
import '../share/share_import_controller.dart';
import '../theme/suchi_theme.dart';
import '../widgets/suchi_widgets.dart';
import 'scan_capture_controller.dart';
import 'scan_database.dart';
import 'scan_queue_store.dart';
import 'scanner_bridge.dart';
import 'upload_coordinator.dart';

class ScanQueueScreen extends StatefulWidget {
  const ScanQueueScreen({
    required this.queue,
    required this.capture,
    required this.uploads,
    required this.session,
    required this.shareImport,
    required this.settings,
    required this.onScan,
    required this.onOpenDocument,
    super.key,
  });

  final ScanQueueStore queue;
  final ScanCaptureController capture;
  final UploadCoordinator uploads;
  final SessionController session;
  final ShareImportController shareImport;
  final AppSettingsController settings;
  final VoidCallback onScan;
  final ValueChanged<int> onOpenDocument;

  @override
  State<ScanQueueScreen> createState() => _ScanQueueScreenState();
}

class _ScanQueueScreenState extends State<ScanQueueScreen> {
  VoidCallback? _concealPicker;

  @override
  void didUpdateWidget(covariant ScanQueueScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) _concealPicker?.call();
  }

  @override
  void dispose() {
    _concealPicker?.call();
    super.dispose();
  }

  Future<void> _openUpload(ScanUpload upload) async {
    final session = widget.session;
    final client = session.client;
    final identity = session.identity;
    bool sameAccount() =>
        mounted &&
        identical(widget.session, session) &&
        session.state == SessionState.signedIn &&
        identical(session.client, client) &&
        session.identity == identity;
    if (client == null ||
        identity == null ||
        !sameAccount() ||
        !_canOpenUpload(upload, session)) {
      return;
    }
    if (!upload.split) {
      widget.onOpenDocument(upload.serverDocumentId!);
      return;
    }
    final ids = _splitIds(upload);
    if (ids != null && ids.length == 1) {
      widget.onOpenDocument(ids.single);
      return;
    }
    if (_concealPicker != null) return;
    ModalRoute<int>? ownedRoute;
    var invalidated = false;
    void conceal() {
      invalidated = true;
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

    _concealPicker = conceal;
    session.addListener(accountChanged);
    try {
      final selected = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: SuchiColors.of(context).paper,
        sheetAnimationStyle: SuchiMotion.sheetStyle(context),
        clipBehavior: Clip.antiAlias,
        builder: (context) {
          ownedRoute = ModalRoute.of<int>(context);
          return ListenableBuilder(
            listenable: session,
            builder: (context, _) {
              if (invalidated || !sameAccount()) {
                conceal();
                return const SizedBox.shrink();
              }
              return _SplitDocumentsPicker(
                client: client,
                originId: upload.splitOriginId,
                ids: ids,
                isCurrent: () => !invalidated && sameAccount(),
              );
            },
          );
        },
      );
      if (selected != null &&
          !invalidated &&
          sameAccount() &&
          ids != null &&
          ids.contains(selected)) {
        widget.onOpenDocument(selected);
      }
    } finally {
      session.removeListener(accountChanged);
      if (identical(_concealPicker, conceal)) _concealPicker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = widget.queue;
    final capture = widget.capture;
    final uploads = widget.uploads;
    final session = widget.session;
    final shareImport = widget.shareImport;
    final onScan = widget.onScan;
    return SafeArea(
      bottom: false,
      child: StreamBuilder<List<ScanUpload>>(
        stream: queue.watchUploads(),
        initialData: const [],
        builder: (context, snapshot) {
          return ListenableBuilder(
            listenable: Listenable.merge([
              capture,
              uploads,
              shareImport,
              session,
              widget.settings,
            ]),
            builder: (context, _) {
              final identity = session.identity;
              final items = visibleQueueUploads(
                snapshot.data ?? const [],
                identity,
              );
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                      child: Text(
                        'Scan',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(17, 0, 17, 16),
                    sliver: SliverToBoxAdapter(
                      child: _CaptureHero(
                        capture: capture,
                        settings: widget.settings,
                        onScan: onScan,
                      ),
                    ),
                  ),
                  if (shareImport.errorMessage != null ||
                      (shareImport.lastSummary?.rejected ?? 0) > 0 ||
                      (shareImport.lastSummary?.failed ?? 0) > 0)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(17, 0, 17, 13),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            InlineError(
                              message:
                                  shareImport.errorMessage ??
                                  '${shareImport.lastSummary!.failed} shared ${shareImport.lastSummary!.failed == 1 ? 'item' : 'items'} failed and ${shareImport.lastSummary!.rejected} ${shareImport.lastSummary!.rejected == 1 ? 'was' : 'were'} unsupported.',
                              onRetry: shareImport.processPending,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: shareImport.dismissResult,
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                ),
                                child: const Text('Dismiss'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(19, 0, 19, 9),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Uploads',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            '${items.length} ${items.length == 1 ? 'item' : 'items'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (items.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(19, 8, 19, 28),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Captured and shared documents appear here.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: SuchiColors.of(context).muted),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(17, 0, 17, 28),
                      sliver: DecoratedSliver(
                        decoration: BoxDecoration(
                          color: SuchiColors.of(context).surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: SuchiColors.of(context).line,
                          ),
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              if (index.isOdd) return const Divider();
                              final upload = items[index ~/ 2];
                              return Material(
                                key: ValueKey(upload.id),
                                type: MaterialType.transparency,
                                child: _QueueRow(
                                  onOpen: () => _openUpload(upload),
                                  upload: upload,
                                  queue: queue,
                                  uploads: uploads,
                                  session: session,
                                ),
                              );
                            },
                            childCount: items.length * 2 - 1,
                            findChildIndexCallback: (key) {
                              final index = items.indexWhere(
                                (item) => item.id == (key as ValueKey).value,
                              );
                              return index < 0 ? null : index * 2;
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

bool _canOpenUpload(ScanUpload upload, SessionController session) {
  final identity = session.identity;
  return session.state == SessionState.signedIn &&
      identity != null &&
      queueUploadBelongsToIdentity(upload, identity) &&
      const {
        'processingServer',
        'filed',
        'duplicate',
        'processingFailed',
      }.contains(upload.state) &&
      (upload.split || (upload.serverDocumentId ?? 0) > 0);
}

Set<int>? _splitIds(ScanUpload upload) {
  try {
    final decoded = jsonDecode(upload.splitDocumentIds ?? '');
    if (decoded is! List || decoded.isEmpty) return null;
    final ids = <int>{};
    for (final value in decoded) {
      if (value is! int ||
          value <= 0 ||
          value == upload.splitOriginId ||
          value == upload.serverDocumentId) {
        return null;
      }
      ids.add(value);
    }
    return ids;
  } on FormatException {
    return null;
  }
}

class _SplitDocumentsPicker extends StatefulWidget {
  const _SplitDocumentsPicker({
    required this.client,
    required this.originId,
    required this.ids,
    required this.isCurrent,
  });

  final SuchiClient client;
  final int? originId;
  final Set<int>? ids;
  final bool Function() isCurrent;

  @override
  State<_SplitDocumentsPicker> createState() => _SplitDocumentsPickerState();
}

class _SplitDocumentsPickerState extends State<_SplitDocumentsPicker> {
  List<DocumentSummary> _documents = const [];
  ApiException? _error;
  bool _loading = false;
  bool _loaded = false;

  bool get _identified => widget.ids != null && (widget.originId ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    if (_identified) _load();
  }

  Future<void> _load() async {
    if (_loading || !widget.isCurrent()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.client.splitDocuments(widget.originId!);
      if (!mounted || !widget.isCurrent()) return;
      final byId = <int, DocumentSummary>{
        for (final document in results)
          if (widget.ids!.contains(document.id)) document.id: document,
      };
      final documents = byId.values.toList()
        ..sort((a, b) {
          if (a.splitIndex == null && b.splitIndex != null) return 1;
          if (a.splitIndex != null && b.splitIndex == null) return -1;
          final part = (a.splitIndex ?? 0).compareTo(b.splitIndex ?? 0);
          return part != 0 ? part : a.id.compareTo(b.id);
        });
      setState(() {
        _documents = documents;
        _loaded = true;
      });
    } on ApiException catch (error) {
      if (mounted && widget.isCurrent()) setState(() => _error = error);
    } catch (_) {
      if (mounted && widget.isCurrent()) {
        setState(() {
          _error = const ApiException(
            kind: ApiFailureKind.network,
            message: 'The documents could not be loaded. Try again.',
          );
        });
      }
    } finally {
      if (mounted && widget.isCurrent()) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.85),
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
                        'Documents from this upload',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_identified)
                        const Text(
                          'Documents from this upload could not be identified.',
                        )
                      else ...[
                        if (_error != null)
                          InlineError(
                            message: _error!.message,
                            requestId: _error!.requestId,
                            onRetry: _loading ? null : _load,
                          ),
                        if (_loading && !_loaded)
                          Semantics(
                            label: 'Loading documents from this upload',
                            child: ExcludeSemantics(
                              child: Column(
                                children: [
                                  for (var i = 0; i < 3; i++)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: colors.manila,
                                              borderRadius:
                                                  BorderRadius.circular(7),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Container(
                                              height: 14,
                                              color: colors.surface2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (_loaded && _documents.isEmpty)
                          const Text(
                            'These split documents are no longer available.',
                          ),
                        if (_documents.isNotEmpty &&
                            _documents.length < widget.ids!.length)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Some documents from this upload are no longer available.',
                            ),
                          ),
                        for (final (index, document) in _documents.indexed)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            minVerticalPadding: 12,
                            minTileHeight: 56,
                            leading: Container(
                              width: 40,
                              height: 44,
                              decoration: BoxDecoration(
                                color: colors.manila,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Icon(
                                document.isSensitive
                                    ? Icons.lock_outline
                                    : Icons.insert_drive_file_outlined,
                              ),
                            ),
                            title: Text(document.title),
                            subtitle: Text(
                              [
                                'Part ${(document.splitIndex ?? index) + 1}',
                                if (document.jdCategoryName
                                        ?.trim()
                                        .isNotEmpty ??
                                    false)
                                  document.jdCategoryName!.trim(),
                              ].join(' · '),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              if (widget.isCurrent()) {
                                Navigator.pop(context, document.id);
                              }
                            },
                          ),
                        if (_loaded)
                          TextButton.icon(
                            onPressed: _loading ? null : _load,
                            icon: _loading
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                            label: Text(
                              _loading ? 'Refreshing documents' : 'Refresh',
                            ),
                          ),
                      ],
                    ],
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

class _CaptureHero extends StatelessWidget {
  const _CaptureHero({
    required this.capture,
    required this.settings,
    required this.onScan,
  });

  final ScanCaptureController capture;
  final AppSettingsController settings;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final photo = settings.captureMode == CaptureMode.photo;
    final title = switch (capture.state) {
      ScanCaptureState.capturing =>
        photo ? 'Opening camera' : 'Opening scanner',
      ScanCaptureState.processingPages => 'Reading captured pages',
      ScanCaptureState.composingPdf => 'Composing document',
      ScanCaptureState.staging => 'Protecting capture',
      ScanCaptureState.complete => 'Capture safely queued',
      ScanCaptureState.failed => 'Capture needs attention',
      ScanCaptureState.idle => photo ? 'Ready for a photo' : 'Ready to scan',
    };
    final message = switch (capture.state) {
      ScanCaptureState.capturing =>
        'Finish or cancel in the system-owned camera.',
      ScanCaptureState.processingPages =>
        'On-device text recognition is preparing optional upload metadata.',
      ScanCaptureState.composingPdf =>
        'The captured pages are becoming one PDF.',
      ScanCaptureState.staging =>
        'Files and checksums are being committed to the durable queue.',
      ScanCaptureState.complete => capture.warningMessage ?? 'Saved to the queue. Uploads resume while Suchi Companion is open and the server is reachable.',
      ScanCaptureState.failed =>
        capture.errorMessage ?? 'The scan could not be prepared.',
      ScanCaptureState.idle =>
        photo
            ? 'Keep the full photo without document cropping or cleanup. Saved as a one-page PDF.'
            : 'Find edges, straighten pages and improve lighting. Review your scan before saving.',
    };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SuchiColors.of(context).camera,
        borderRadius: BorderRadius.circular(21),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E0F1519),
            blurRadius: 26,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: Colors.white, fontSize: 25),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: const Color(0xFFA8B0B4)),
          ),
          const SizedBox(height: 20),
          if (capture.isBusy)
            const LinearProgressIndicator()
          else if (capture.state == ScanCaptureState.failed)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!capture.hasPendingCapture || capture.canRetryPending)
                  FilledButton(
                    onPressed: capture.hasPendingCapture
                        ? capture.retryPending
                        : onScan,
                    child: const Text('Retry'),
                  ),
                if (capture.hasPendingCapture)
                  TextButton(
                    onPressed: capture.discardPending,
                    child: const Text('Discard capture'),
                  ),
                if (capture.canOpenSettings)
                  TextButton(
                    onPressed: capture.openSettings,
                    child: const Text('Open Settings'),
                  ),
              ],
            )
          else
            FilledButton.icon(
              onPressed: settings.loaded ? onScan : null,
              icon: Icon(
                photo
                    ? Icons.photo_camera_outlined
                    : Icons.document_scanner_outlined,
              ),
              label: Text(
                photo
                    ? 'Take a photo'
                    : capture.state == ScanCaptureState.complete
                    ? 'Scan another document'
                    : 'Scan a document',
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Hold the centre camera button to switch modes, or use More → Camera mode.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: const Color(0xFFA8B0B4)),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatefulWidget {
  const _QueueRow({
    required this.upload,
    required this.queue,
    required this.uploads,
    required this.session,
    required this.onOpen,
  });

  final ScanUpload upload;
  final ScanQueueStore queue;
  final UploadCoordinator uploads;
  final SessionController session;
  final VoidCallback onOpen;

  @override
  State<_QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends State<_QueueRow> {
  bool _acting = false;

  AccountIdentity? get _identity => widget.session.identity;

  Future<void> _assign() async {
    final identity = _identity;
    if (identity == null) return;
    await _act(() async {
      await widget.queue.assign(widget.upload.id, identity: identity);
      await widget.uploads.processNow();
    });
  }

  Future<void> _retry() => _act(() => widget.uploads.retry(widget.upload.id));

  Future<void> _restage() => _act(() async {
    await widget.uploads.restageConflict(widget.upload.id);
  });

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Discard queued document?'),
        content: const Text(
          'The local queued copy will be removed permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _act(() => widget.queue.removeUpload(widget.upload.id));
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await action();
    } on QueueStageException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final upload = widget.upload;
    final identity = _identity;
    final belongsHere =
        identity != null && queueUploadBelongsToIdentity(upload, identity);
    final status = _status(upload, belongsHere: belongsHere);
    final canOpen = !_acting && _canOpenUpload(upload, widget.session);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: canOpen,
          child: InkWell(
            onTap: canOpen
                ? () {
                    if (!_acting &&
                        _canOpenUpload(widget.upload, widget.session)) {
                      widget.onOpen();
                    }
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Container(
                    width: 39,
                    height: 44,
                    decoration: BoxDecoration(
                      color: SuchiColors.of(context).manila,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      upload.source == 'camera'
                          ? Icons.document_scanner_outlined
                          : Icons.ios_share_outlined,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          upload.filename,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          status.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: status.color,
                          ),
                        ),
                        Text(
                          status.message,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (_acting) ...[
                    const SizedBox(width: 8),
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ] else if (canOpen) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (!_acting)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _actions(upload, belongsHere),
          ),
      ],
    );
  }

  Widget _actions(ScanUpload upload, bool belongsHere) {
    if (upload.state == 'unassigned') {
      return Wrap(
        spacing: 4,
        children: [
          TextButton(onPressed: _assign, child: const Text('Upload here')),
          TextButton(onPressed: _discard, child: const Text('Discard')),
        ],
      );
    }
    if (!belongsHere) return const SizedBox.shrink();
    if (upload.state == 'uploadFailed') {
      return Wrap(
        spacing: 4,
        children: [
          if (upload.lastErrorCode == 'idempotency_conflict')
            TextButton(onPressed: _restage, child: const Text('Stage again'))
          else
            TextButton(onPressed: _retry, child: const Text('Retry')),
          TextButton(onPressed: _discard, child: const Text('Discard')),
        ],
      );
    }
    if (upload.state == 'processingFailed') {
      return TextButton(onPressed: _retry, child: const Text('Check again'));
    }
    return const SizedBox.shrink();
  }

  _QueueStatus _status(ScanUpload upload, {required bool belongsHere}) {
    final colors = SuchiColors.of(context);
    if (!belongsHere && upload.state != 'unassigned') {
      return _QueueStatus(
        'OTHER',
        'This item belongs to another paired account.',
        colors.warning,
      );
    }
    return switch (upload.state) {
      'unassigned' => _QueueStatus(
        'Choose account',
        'Choose whether to upload this item to the paired account.',
        colors.warning,
      ),
      'queued' => _QueueStatus(
        upload.lastErrorMessage == null ? 'Queued' : 'Waiting to retry',
        upload.lastErrorMessage ?? 'Protected locally and waiting to upload.',
        colors.muted,
      ),
      'uploading' => _QueueStatus(
        'Sending',
        '${upload.bytesSent} of ${upload.byteSize} bytes sent.',
        colors.accent,
      ),
      'processingServer' => _QueueStatus(
        'Processing',
        upload.lastErrorMessage == null
            ? 'Accepted. Suchi is filing and indexing it.'
            : 'Accepted. Waiting to check processing again. ${upload.lastErrorMessage}',
        colors.accent,
      ),
      'filed' => _QueueStatus(
        'Filed',
        upload.restored
            ? 'Filed by restoring an existing document.'
            : 'Filed successfully.',
        colors.success,
      ),
      'duplicate' => _QueueStatus(
        'Duplicate',
        'Already present in this archive.',
        colors.success,
      ),
      'uploadFailed' => _QueueStatus(
        'Needs attention',
        upload.lastErrorMessage ?? 'Upload needs attention.',
        colors.warning,
      ),
      'processingFailed' => _QueueStatus(
        'Check processing',
        upload.lastErrorMessage ?? 'Server processing needs attention.',
        colors.warning,
      ),
      _ => _QueueStatus(
        'UNKNOWN',
        'This queue state is not recognized.',
        colors.danger,
      ),
    };
  }
}

final class _QueueStatus {
  const _QueueStatus(this.label, this.message, this.color);

  final String label;
  final String message;
  final Color color;
}
