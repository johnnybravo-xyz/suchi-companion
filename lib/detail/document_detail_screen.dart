import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../auth/session_controller.dart';
import '../documents/jd_category_store.dart';
import '../documents/jd_index.dart';
import '../documents/thumbnail_cache.dart';
import '../theme/suchi_theme.dart';
import '../widgets/suchi_widgets.dart';
import 'document_files.dart';
import 'email_preview.dart';
import 'document_edit_screen.dart';
import 'document_text_screen.dart';

class DocumentDetailScreen extends StatefulWidget {
  const DocumentDetailScreen({
    required this.documentId,
    required this.client,
    required this.session,
    required this.cache,
    required this.categories,
    required this.files,
    this.onChanged,
    super.key,
  });

  final int documentId;
  final SuchiClient client;
  final SessionController session;
  final ThumbnailMemoryCache cache;
  final JdCategoryStore categories;
  final DocumentFiles files;
  final VoidCallback? onChanged;

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen>
    with WidgetsBindingObserver {
  DocumentDetail? _document;
  Uint8List? _preview;
  String? _emailHtml;
  ApiException? _error;
  String? _previewMessage;
  bool _loading = true;
  bool _previewLoading = false;
  bool _revealed = false;
  bool _mutating = false;
  bool _fileLoading = false;
  int _generation = 0;
  int _previewGeneration = 0;
  int _sensitivePreviewEpoch = 0;
  final ExpansibleController _informationController = ExpansibleController();

  bool get _sameAccount =>
      widget.session.state == SessionState.signedIn &&
      identical(widget.session.client, widget.client);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_sessionChanged);
    widget.categories.load();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_sessionChanged);
    if (_fileLoading) widget.files.cancelPending();
    _generation++;
    _previewGeneration++;
    _evictRevealedPreview();
    _informationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _concealPreview();
      if (_fileLoading) widget.files.cancelPending();
    }
  }

  void _sessionChanged() {
    if (!mounted || _sameAccount) return;
    _generation++;
    _previewGeneration++;
    _sensitivePreviewEpoch++;
    _evictRevealedPreview();
    setState(() {
      _document = null;
      _revealed = false;
    });
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _openFile({required bool share}) async {
    final document = _document;
    if (document == null || _fileLoading || _mutating) return;
    final generation = _generation;
    final confirmed =
        !document.isSensitive ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                scrollable: true,
                title: Text(
                  share ? 'Share this document?' : 'Open this document?',
                ),
                content: Text(
                  '${document.isSensitive ? 'This document is ${sensitivityLabel(document.sensitivity).toLowerCase()}. ' : ''}'
                  '${share || Platform.isAndroid ? 'A copy will be available to the app you choose. That app may retain it.' : 'The full document will download to this device. The viewer also lets you save or share a copy.'}',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(share ? 'Share document' : 'Open document'),
                  ),
                ],
              ),
            ) ==
            true;
    if (confirmed != true ||
        !mounted ||
        generation != _generation ||
        !_sameAccount) {
      return;
    }
    setState(() => _fileLoading = true);
    try {
      await widget.files.handoff(
        client: widget.client,
        documentId: document.id,
        reveal: document.isSensitive,
        share: share,
      );
    } on ApiException catch (error) {
      if (error.expiresSession) widget.session.expire(error);
      if (!mounted || error.kind == ApiFailureKind.cancelled) return;
      _showFileError(
        friendlyApiMessage(
          error,
          fallback: 'The document could not be downloaded.',
        ),
      );
    } on PlatformException catch (error) {
      if (mounted) {
        _showFileError(error.message ?? 'The document could not be opened.');
      }
    } on FileSystemException {
      if (mounted) {
        _showFileError(
          'The document could not be saved temporarily. Check available device storage and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _fileLoading = false);
    }
  }

  void _showFileError(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  void didHaveMemoryPressure() => _concealPreview();

  Future<void> _load() async {
    final generation = ++_generation;
    _previewGeneration++;
    _sensitivePreviewEpoch++;
    _evictRevealedPreview();
    setState(() {
      _loading = true;
      _error = null;
      _revealed = false;
      _preview = null;
      _emailHtml = null;
      _previewMessage = null;
      _previewLoading = false;
    });
    try {
      final document = await widget.client.document(widget.documentId);
      if (!mounted || generation != _generation || !_sameAccount) return;
      setState(() {
        _document = document;
        _loading = false;
        _revealed = false;
        _preview = null;
      });
      if (!document.isSensitive) await _loadPreview(reveal: false);
    } on ApiException catch (error) {
      if (!mounted || generation != _generation || !_sameAccount) return;
      if (error.expiresSession) widget.session.expire(error);
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadPreview({required bool reveal}) async {
    if (!_sameAccount) return;
    final document = _document;
    if (document == null) return;
    final generation = ++_previewGeneration;
    setState(() {
      _previewLoading = true;
      _previewMessage = null;
      _emailHtml = null;
    });
    try {
      if (_isEmail(document.mimeType)) {
        final html = hardenEmailPreviewHtml(
          await widget.client.emailPreview(widget.documentId, reveal: reveal),
        );
        if (!mounted ||
            generation != _previewGeneration ||
            !_sameAccount ||
            reveal != _revealed && document.isSensitive) {
          return;
        }
        setState(() {
          _preview = null;
          _emailHtml = html;
        });
      } else {
        final result = await widget.cache.load(
          widget.client,
          widget.documentId,
          width: 512,
          reveal: reveal,
        );
        if (!mounted ||
            generation != _previewGeneration ||
            !_sameAccount ||
            reveal != _revealed && document.isSensitive) {
          return;
        }
        setState(() {
          _emailHtml = null;
          switch (result) {
            case ThumbnailImage(:final bytes):
              _preview = bytes;
            case ThumbnailGated():
              _preview = null;
              _previewMessage = 'Reveal is required to load this preview.';
            case ThumbnailUnavailable():
              _preview = null;
              _previewMessage = 'Preview is still being prepared.';
          }
        });
      }
    } on ApiException catch (error) {
      if (!mounted || generation != _previewGeneration || !_sameAccount) {
        return;
      }
      if (error.expiresSession) widget.session.expire(error);
      setState(() {
        _previewMessage = friendlyApiMessage(
          error,
          fallback: 'The preview could not be loaded.',
        );
      });
    } on FormatException {
      if (!mounted || generation != _previewGeneration || !_sameAccount) {
        return;
      }
      setState(() {
        _previewMessage = 'Suchi returned an unsafe email preview.';
      });
    } finally {
      if (mounted && generation == _previewGeneration) {
        setState(() => _previewLoading = false);
      }
    }
  }

  Future<void> _reveal() async {
    if (!_sameAccount) return;
    setState(() => _revealed = true);
    await _loadPreview(reveal: true);
  }

  void _hide() {
    _previewGeneration++;
    _sensitivePreviewEpoch++;
    _evictRevealedPreview();
    setState(() {
      _revealed = false;
      _preview = null;
      _emailHtml = null;
      _previewMessage = null;
      _previewLoading = false;
    });
  }

  void _evictRevealedPreview() {
    final bytes = _preview;
    if (_document?.isSensitive == true && bytes != null) {
      MemoryImage(bytes).evict();
    }
    widget.cache.evict(widget.documentId, reveal: true);
    _preview = null;
    _emailHtml = null;
  }

  void _concealPreview() {
    if (_document?.isSensitive == true) {
      _hide();
      return;
    }
    if (_emailHtml == null) return;
    _previewGeneration++;
    setState(() {
      _emailHtml = null;
      _previewMessage = 'Preview hidden after leaving Suchi Companion.';
      _previewLoading = false;
    });
  }

  Future<void> _edit() async {
    final document = _document;
    if (document == null || _mutating || _fileLoading) return;
    final generation = _generation;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentEditScreen(
          document: document,
          client: widget.client,
          session: widget.session,
        ),
      ),
    );
    if (changed == true &&
        mounted &&
        generation == _generation &&
        _sameAccount) {
      widget.onChanged?.call();
      await _load();
    }
  }

  void _readText() {
    final document = _document;
    if (document == null ||
        _mutating ||
        _fileLoading ||
        widget.session.state != SessionState.signedIn ||
        !identical(widget.session.client, widget.client)) {
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentTextScreen(
          documentId: document.id,
          title: document.title,
          sensitivity: document.sensitivity,
          client: widget.client,
          session: widget.session,
        ),
      ),
    );
  }

  Future<void> _fileUnder() async {
    final document = _document;
    if (document == null || _mutating || _fileLoading || !_sameAccount) return;
    final generation = _generation;
    final category = await showJdCategorySheet(
      context,
      store: widget.categories,
      title: 'File “${document.title}” under',
    );
    if (!mounted ||
        generation != _generation ||
        !_sameAccount ||
        category == null ||
        category.id == document.jdCategoryId) {
      return;
    }
    setState(() => _mutating = true);
    try {
      await widget.client.patchDocument(document.id, jdCategoryId: category.id);
      if (!mounted || generation != _generation || !_sameAccount) return;
      widget.onChanged?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Filed under ${category.label}.')));
      await _load();
    } on ApiException catch (error) {
      if (!mounted || generation != _generation || !_sameAccount) return;
      if (error.expiresSession) widget.session.expire(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyApiMessage(
              error,
              fallback: 'The document could not be filed.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _trash() async {
    if (_mutating || _fileLoading || !_sameAccount) return;
    final generation = _generation;
    final client = widget.client;
    final session = widget.session;
    final documentId = widget.documentId;
    final onChanged = widget.onChanged;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Move to Trash?'),
        content: const Text(
          'You can restore this document immediately with Undo, or from '
          'More → Trash for up to 30 days, subject to server availability.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        generation != _generation ||
        !_sameAccount) {
      return;
    }
    setState(() => _mutating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await client.trashDocument(documentId);
      if (!mounted || generation != _generation || !_sameAccount) return;
      onChanged?.call();
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Document moved to Trash.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              if (!identical(session.client, client)) return;
              try {
                await client.restoreDocument(documentId);
                if (!identical(session.client, client)) return;
                onChanged?.call();
              } on ApiException catch (error) {
                if (!identical(session.client, client)) return;
                if (error.expiresSession) session.expire(error);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      friendlyApiMessage(
                        error,
                        fallback: 'The document could not be restored.',
                      ),
                    ),
                  ),
                );
              }
            },
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted || generation != _generation || !_sameAccount) return;
      if (error.expiresSession) widget.session.expire(error);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            friendlyApiMessage(
              error,
              fallback: 'The document could not be moved to Trash.',
            ),
          ),
        ),
      );
      setState(() => _mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: SuchiColors.of(context).paper,
    appBar: AppBar(
      leading: const BackButton(),
      title: const Text('Document'),
      actions: [
        IconButton(
          tooltip: 'Edit document',
          onPressed: _mutating || _fileLoading || _document == null
              ? null
              : _edit,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Move to Trash',
          onPressed: _mutating || _fileLoading || _document == null
              ? null
              : _trash,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: SafeArea(top: false, child: _body()),
  );

  Widget _body() {
    if (!_sameAccount) return const SizedBox.shrink();
    if (_loading && _document == null) {
      return const _DetailSkeleton();
    }
    final error = _error;
    if (error != null && _document == null) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [_detailError(error)],
      );
    }
    final document = _document!;
    final colors = SuchiColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final date = DateFormat.yMMMd().format(
      DateTime.fromMillisecondsSinceEpoch(
        document.createdAt * 1000,
        isUtc: true,
      ).toLocal(),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        const SectionLabel('Document'),
        const SizedBox(height: 8),
        Text(
          document.title,
          style: textTheme.headlineSmall?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (document.jdCategoryCode != null)
              JdChip(code: document.jdCategoryCode),
            Text(
              [
                if (document.jdCategoryName?.trim().isNotEmpty == true)
                  document.jdCategoryName!,
                date,
              ].join(' · '),
              style: textTheme.bodySmall,
            ),
            Semantics(
              label: 'Classification: ${_classification(document.sensitivity)}',
              excludeSemantics: true,
              child: QuietBadge(_classification(document.sensitivity)),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          _detailError(error),
          const SizedBox(height: 6),
          Text('Showing last loaded information.', style: textTheme.bodySmall),
        ],
        if (_loading) ...[
          const SizedBox(height: 12),
          const Row(
            children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Expanded(child: Text('Refreshing document information…')),
            ],
          ),
        ],
        const SizedBox(height: 18),
        _previewPane(document),
        const SizedBox(height: 16),
        if (_fileLoading)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Preparing document…')),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: widget.files.cancelPending,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          )
        else
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            onPressed: _mutating ? null : () => _openFile(share: false),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open document'),
          ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns = (constraints.maxWidth / (104 * scale + 8))
                .floor()
                .clamp(1, 3);
            final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
            final enabled = !_mutating && !_fileLoading;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _secondaryAction(
                  width: width,
                  icon: Icons.ios_share,
                  label: 'Share',
                  onPressed: enabled ? () => _openFile(share: true) : null,
                ),
                _secondaryAction(
                  width: width,
                  icon: Icons.article_outlined,
                  label: 'Read text',
                  onPressed: enabled ? _readText : null,
                ),
                _secondaryAction(
                  width: width,
                  icon: Icons.drive_file_move_outline,
                  label: 'File under',
                  onPressed: enabled ? _fileUnder : null,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        SuchiCard(
          child: ExpansionTile(
            controller: _informationController,
            onExpansionChanged: (_) => setState(() {}),
            title: const Text('Document information'),
            subtitle: const Text('Type, size, sources, tags'),
            expansionAnimationStyle: SuchiMotion.standardStyle(context),
            shape: const Border(),
            collapsedShape: const Border(),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              _MetaRow(label: 'Type', value: document.mimeType),
              _MetaRow(
                label: 'Size',
                value: _formatBytes(document.originalSize),
              ),
              if (document.languages.isNotEmpty)
                _MetaRow(label: 'Languages', value: document.languages),
              if (document.sources.isNotEmpty) ...[
                const _InformationLabel('Sources'),
                for (final source in document.sources)
                  _MetaRow(
                    label: source.label,
                    value: source.detail?.isNotEmpty == true
                        ? source.detail!
                        : source.kind,
                  ),
              ],
              if (document.correspondents.isNotEmpty) ...[
                const _InformationLabel('Correspondents'),
                for (final correspondent in document.correspondents)
                  _MetaRow(
                    label: correspondent.role,
                    value: correspondent.name,
                  ),
              ],
              if (document.tags.isNotEmpty) ...[
                const _InformationLabel('Tags'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final tag in document.tags)
                        Chip(label: Text(tag), backgroundColor: colors.manila),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailError(ApiException error) => InlineError(
    message: friendlyApiMessage(
      error,
      fallback: 'Document details could not be loaded.',
    ),
    requestId: error.requestId,
    onRetry: _load,
  );

  Widget _secondaryAction({
    required double width,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) => SizedBox(
    width: width,
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(104, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, textAlign: TextAlign.center),
    ),
  );

  Widget _previewPane(DocumentDetail document) {
    final colors = SuchiColors.of(context);
    final concealed = document.isSensitive && !_revealed;
    final content = concealed
        ? _SensitiveGate(document: document, onReveal: _reveal)
        : _previewContent(document);
    // Concealment and WebView removal replace the entire subtree immediately,
    // never retaining sensitive bytes or email HTML in an outgoing animation.
    final well = KeyedSubtree(
      key: ValueKey((document.isSensitive, _sensitivePreviewEpoch, concealed)),
      child: concealed || _emailHtml != null
          ? content
          : _animatedPreview(content),
    );
    return SuchiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Preview',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _isEmail(document.mimeType)
                            ? 'Email body'
                            : 'First page',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (document.isSensitive && _revealed)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: _hide,
                          icon: const Icon(
                            Icons.visibility_off_outlined,
                            size: 18,
                          ),
                          label: const Text('Hide'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            constraints: const BoxConstraints(minHeight: 265),
            decoration: BoxDecoration(
              color: colors.manila,
              border: Border(top: BorderSide(color: colors.line)),
            ),
            alignment: Alignment.center,
            child: well,
          ),
        ],
      ),
    );
  }

  Widget _animatedPreview(Widget content) {
    if (MediaQuery.disableAnimationsOf(context)) return content;
    return AnimatedSize(
      duration: SuchiMotion.standard(context),
      curve: Curves.easeOutCubic,
      child: AnimatedSwitcher(
        duration: SuchiMotion.standard(context),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.center,
          children: [
            for (final child in previous)
              ExcludeSemantics(child: IgnorePointer(child: child)),
            ?current,
          ],
        ),
        child: content,
      ),
    );
  }

  Widget _previewContent(DocumentDetail document) {
    if (_emailHtml case final html?) {
      return SandboxedEmailPreview(
        key: ValueKey(html),
        html: html,
        onOpen: () => _openFile(share: false),
      );
    }
    if (_preview case final bytes?) {
      return Padding(
        key: const ValueKey('image'),
        padding: const EdgeInsets.all(12),
        child: Image.memory(
          bytes,
          height: 250,
          fit: BoxFit.contain,
          semanticLabel: 'First page preview',
        ),
      );
    }
    if (_previewLoading) {
      return const SizedBox(
        key: ValueKey('loading'),
        height: 265,
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              semanticsLabel: 'Loading preview',
            ),
          ),
        ),
      );
    }
    return Padding(
      key: const ValueKey('unavailable'),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 36,
            color: SuchiColors.of(context).muted,
          ),
          const SizedBox(height: 12),
          Text(
            'No preview available',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _previewMessage ?? 'Suchi may still be preparing this document.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => _loadPreview(reveal: _revealed),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static bool _isEmail(String mimeType) =>
      mimeType.split(';').first.trim().toLowerCase() == 'message/rfc822';
}

class _SensitiveGate extends StatelessWidget {
  const _SensitiveGate({required this.document, required this.onReveal});

  final DocumentDetail document;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline, size: 38, color: SuchiColors.of(context).ink),
        const SizedBox(height: 12),
        Text(
          '${_classification(document.sensitivity)} preview hidden',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 7),
        Text(
          'The image will load only after you choose Reveal.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: onReveal,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Reveal preview'),
        ),
      ],
    ),
  );
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: SuchiColors.of(context).line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 5),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: SuchiColors.of(context).ink),
        ),
      ],
    ),
  );
}

String _classification(String sensitivity) => switch (sensitivity) {
  'public' => 'Public',
  'internal' => 'Internal',
  'confidential' => 'Confidential',
  'restricted' => 'Restricted',
  _ => 'Not set',
};

class _InformationLabel extends StatelessWidget {
  const _InformationLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Align(alignment: Alignment.centerLeft, child: SectionLabel(label)),
  );
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    Widget bar(double width, double height) => Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
    return Semantics(
      label: 'Loading document',
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            bar(70, 12),
            const SizedBox(height: 12),
            bar(double.infinity, 28),
            const SizedBox(height: 8),
            bar(210, 28),
            const SizedBox(height: 12),
            bar(180, 20),
            const SizedBox(height: 18),
            SuchiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: bar(70, 16),
                  ),
                  Container(height: 265, color: colors.manila),
                ],
              ),
            ),
            const SizedBox(height: 16),
            bar(double.infinity, 52),
            const SizedBox(height: 10),
            bar(double.infinity, 48),
            const SizedBox(height: 18),
            SuchiCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  bar(180, 18),
                  const SizedBox(height: 8),
                  bar(150, 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
