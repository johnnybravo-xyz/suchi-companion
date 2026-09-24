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
import '../offline/offline_document_store.dart';
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
    this.offlineDocuments,
    this.onChanged,
    super.key,
  });

  final int documentId;
  final SuchiClient client;
  final SessionController session;
  final ThumbnailMemoryCache cache;
  final JdCategoryStore categories;
  final DocumentFiles files;
  final OfflineDocumentStore? offlineDocuments;
  final VoidCallback? onChanged;

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen>
    with WidgetsBindingObserver {
  DocumentDetail? _document;
  Uint8List? _preview;
  String? _emailHtml;
  OfflineDocument? _offlineFallback;
  ApiException? _error;
  String? _previewMessage;
  bool _loading = true;
  bool _previewLoading = false;
  bool _revealed = false;
  bool _mutating = false;
  bool _fileLoading = false;
  bool _offlineMutating = false;
  String _offlineProgressLabel = 'Saving offline copy…';
  int _generation = 0;
  int _previewGeneration = 0;
  int _sensitivePreviewEpoch = 0;

  bool get _sameAccount =>
      widget.session.state == SessionState.signedIn &&
          identical(widget.session.client, widget.client) ||
      _offlineFallback != null &&
          widget.session.identity == _offlineFallback!.identity;

  OfflineDocument? get _offlineEntry =>
      widget.offlineDocuments?.find(widget.session.identity, widget.documentId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_sessionChanged);
    widget.categories.load();
    widget.offlineDocuments?.addListener(_offlineStoreChanged);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_sessionChanged);
    if (_fileLoading) widget.files.cancelPending();
    widget.offlineDocuments?.removeListener(_offlineStoreChanged);
    if (_offlineMutating) widget.offlineDocuments?.cancelPending();
    _generation++;
    _previewGeneration++;
    _evictRevealedPreview();
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

  void _offlineStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openFile({required bool share}) async {
    final document = _document;
    if (document == null || _fileLoading || _mutating || _offlineMutating) {
      return;
    }
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
                  '${_offlineFallback != null || share || Platform.isAndroid ? 'A copy will be available to the app you choose. That app may retain it.' : 'The full document will download to this device. The viewer also lets you save or share a copy.'}',
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
    final identity = widget.session.identity;
    if (confirmed != true ||
        !mounted ||
        generation != _generation ||
        !_sameAccount ||
        identity == null) {
      return;
    }
    setState(() => _fileLoading = true);
    try {
      final offline = _offlineFallback;
      if (offline != null) {
        await widget.offlineDocuments!.handoff(
          identity: identity,
          entry: offline,
          share: share,
        );
      } else {
        await widget.files.handoff(
          client: widget.client,
          documentId: document.id,
          reveal: document.isSensitive,
          share: share,
        );
      }
    } on ApiException catch (error) {
      if (error.expiresSession) widget.session.expire(error);
      if (!mounted ||
          generation != _generation ||
          widget.session.identity != identity ||
          error.kind == ApiFailureKind.cancelled) {
        return;
      }
      _showFileError(
        friendlyApiMessage(
          error,
          fallback: 'The document could not be downloaded.',
        ),
      );
    } on PlatformException catch (error) {
      if (mounted &&
          generation == _generation &&
          widget.session.identity == identity) {
        _showFileError(error.message ?? 'The document could not be opened.');
      }
    } on FileSystemException {
      if (mounted &&
          generation == _generation &&
          widget.session.identity == identity) {
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

  Future<void> _saveOffline() async {
    final store = widget.offlineDocuments;
    final document = _document;
    final identity = widget.session.identity;
    if (store == null ||
        document == null ||
        identity == null ||
        _offlineFallback != null ||
        _offlineMutating ||
        _fileLoading ||
        _mutating ||
        !_sameAccount) {
      return;
    }
    if (document.isSensitive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Keep sensitive document offline?'),
          content: const Text(
            'A protected full copy will remain on this device until you remove it or sign out.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Keep offline'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || !_sameAccount) return;
    }
    final updating = store.find(identity, document.id) != null;
    setState(() {
      _offlineProgressLabel = updating
          ? 'Updating offline copy…'
          : 'Saving offline copy…';
      _offlineMutating = true;
    });
    try {
      await store.save(
        identity: identity,
        document: document,
        client: widget.client,
        reveal: document.isSensitive,
      );
      if (!mounted || !_sameAccount) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document is available offline.')),
      );
    } on ApiException catch (error) {
      if (error.expiresSession) widget.session.expire(error);
      if (!mounted || error.kind == ApiFailureKind.cancelled) return;
      _showFileError(
        friendlyApiMessage(
          error,
          fallback: 'The offline copy could not be saved.',
        ),
      );
    } on OfflineDocumentException catch (error) {
      if (mounted && error.code != 'offline_cancelled') {
        _showFileError(error.message);
      }
    } on FileSystemException {
      if (mounted) {
        _showFileError(
          'The offline copy could not be saved. Check available device storage and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _offlineMutating = false);
    }
  }

  Future<void> _removeOffline() async {
    final store = widget.offlineDocuments;
    final entry = _offlineEntry ?? _offlineFallback;
    final identity = widget.session.identity;
    if (store == null ||
        entry == null ||
        identity == null ||
        entry.identity != identity ||
        _offlineMutating) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove offline copy?'),
        content: const Text(
          'The document will remain in Suchi but will no longer be available without a connection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        !_sameAccount ||
        widget.session.identity != identity) {
      return;
    }
    setState(() {
      _offlineProgressLabel = 'Removing offline copy…';
      _offlineMutating = true;
    });
    try {
      await store.remove(identity, entry.document.id);
      if (!mounted || widget.session.identity != identity) return;
      if (_offlineFallback != null) {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Offline copy removed.')));
      }
    } on FileSystemException {
      if (mounted && widget.session.identity == identity) {
        _showFileError('The offline copy could not be removed.');
      }
    } finally {
      if (mounted) setState(() => _offlineMutating = false);
    }
  }

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
      _offlineFallback = null;
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
        _offlineFallback = null;
        _loading = false;
        _revealed = false;
        _preview = null;
      });
      if (!document.isSensitive) await _loadPreview(reveal: false);
    } on ApiException catch (error) {
      if (!mounted || generation != _generation || !_sameAccount) return;
      final offline = widget.offlineDocuments?.find(
        widget.session.identity,
        widget.documentId,
      );
      if ((error.kind == ApiFailureKind.network ||
              error.kind == ApiFailureKind.timeout) &&
          offline != null) {
        setState(() {
          _document = offline.document;
          _offlineFallback = offline;
          _loading = false;
          _error = null;
          _preview = null;
          _emailHtml = null;
          _previewMessage = 'Preview is unavailable while offline.';
          _previewLoading = false;
        });
        return;
      }
      if (error.expiresSession) widget.session.expire(error);
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadPreview({required bool reveal}) async {
    if (!_sameAccount || _offlineFallback != null) return;
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
    if (document == null ||
        _mutating ||
        _fileLoading ||
        _offlineFallback != null) {
      return;
    }
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
        _offlineFallback != null ||
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
    if (document == null ||
        _mutating ||
        _fileLoading ||
        _offlineFallback != null ||
        !_sameAccount) {
      return;
    }
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
    if (_mutating ||
        _fileLoading ||
        _offlineFallback != null ||
        !_sameAccount) {
      return;
    }
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
      actions: [
        IconButton(
          tooltip: 'Share document',
          onPressed:
              _mutating || _fileLoading || _offlineMutating || _document == null
              ? null
              : () => _openFile(share: true),
          icon: const Icon(Icons.ios_share_outlined),
        ),
        IconButton(
          tooltip: 'Edit document',
          onPressed:
              _mutating ||
                  _fileLoading ||
                  _offlineMutating ||
                  _offlineFallback != null ||
                  _document == null
              ? null
              : _edit,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Move to Trash',
          onPressed:
              _mutating ||
                  _fileLoading ||
                  _offlineMutating ||
                  _offlineFallback != null ||
                  _document == null
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
    final textTheme = Theme.of(context).textTheme;
    final offlineEntry = _offlineEntry ?? _offlineFallback;
    final offlineOutdated =
        offlineEntry != null &&
        offlineEntry.document.originalBlob != document.originalBlob;
    final summary = <String>[
      if (document.jdCategoryName?.trim().isNotEmpty == true)
        document.jdCategoryName!.trim(),
      ?_sender(document),
      _formatDate(document.createdAt),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        _previewPane(
          document,
          offlineEntry: offlineEntry,
          offlineOutdated: offlineOutdated,
        ),
        const SizedBox(height: 20),
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
            Text(summary.join(' · '), style: textTheme.bodySmall),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          _detailError(error),
          const SizedBox(height: 6),
          Text('Showing last loaded information.', style: textTheme.bodySmall),
        ],
        if (_offlineFallback != null) ...[
          const SizedBox(height: 12),
          const SuchiCard(
            elevated: false,
            child: ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Showing offline copy'),
              subtitle: Text(
                'Document details are read-only until Suchi is reachable.',
              ),
            ),
          ),
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
        _bodyActions(),
        const SizedBox(height: 20),
        const SectionLabel('Details'),
        const SizedBox(height: 8),
        _metadataCard(document),
        const SizedBox(height: 20),
        _provenanceFooter(document),
      ],
    );
  }

  Widget _metadataCard(DocumentDetail document) {
    final rows = <MapEntry<String, String>>[
      MapEntry('Filed', _filedUnder(document)),
      MapEntry('From', _sender(document) ?? 'None'),
      MapEntry(
        'Tags',
        document.tags.isEmpty ? 'None' : document.tags.join(' · '),
      ),
      MapEntry('Sensitivity', _classification(document.sensitivity)),
      if (document.languages.trim().isNotEmpty)
        MapEntry('Languages', document.languages.trim()),
    ];
    return SuchiCard(
      key: const ValueKey('document-metadata'),
      elevated: false,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++)
            _MetaRow(
              label: rows[index].key,
              value: rows[index].value,
              showDivider: index != rows.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _provenanceFooter(DocumentDetail document) {
    final source = document.sources.isEmpty
        ? 'None'
        : _sourceName(document.sources.first);
    final visible =
        'Added ${_formatDate(document.addedAt)} · '
        'Source $source · Blob ${_shortBlob(document.originalBlob)}';
    return Semantics(
      key: const ValueKey('document-provenance'),
      label:
          'Provenance. Added ${_formatDate(document.addedAt)}. '
          'Source $source. Original blob ${_shortBlob(document.originalBlob)}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Provenance'),
            const SizedBox(height: 7),
            Text(
              visible,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SuchiColors.of(context).muted,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
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

  Widget _bodyActions() {
    final enabled = !_mutating && !_fileLoading && !_offlineMutating;
    final online = _offlineFallback == null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final stacked = constraints.maxWidth < 340 || scale > 1.3;
        final read = _bodyAction(
          icon: Icons.article_outlined,
          label: 'Read text',
          onPressed: enabled && online ? _readText : null,
        );
        final file = _bodyAction(
          icon: Icons.drive_file_move_outline,
          label: 'File under…',
          onPressed: enabled && online ? _fileUnder : null,
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [read, const SizedBox(height: 8), file],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: read),
            const SizedBox(width: 8),
            Expanded(child: file),
          ],
        );
      },
    );
  }

  Widget _bodyAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 52),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    ),
    onPressed: onPressed,
    icon: Icon(icon, size: 19),
    label: Text(label, textAlign: TextAlign.center),
  );

  Widget _previewPane(
    DocumentDetail document, {
    required OfflineDocument? offlineEntry,
    required bool offlineOutdated,
  }) {
    final colors = SuchiColors.of(context);
    final concealed =
        _offlineFallback == null && document.isSensitive && !_revealed;
    final content = _offlineFallback != null
        ? _offlinePreviewContent()
        : concealed
        ? _SensitiveGate(document: document, onReveal: _reveal)
        : _previewContent(document);
    // Concealment and WebView removal replace the entire subtree immediately,
    // never retaining sensitive bytes or email HTML in an outgoing animation.
    final well = KeyedSubtree(
      key: ValueKey((document.isSensitive, _sensitivePreviewEpoch, concealed)),
      child: concealed || _emailHtml != null || _offlineFallback != null
          ? content
          : _animatedPreview(content),
    );
    final enabled = !_mutating && !_offlineMutating && !_fileLoading;
    final activate = enabled
        ? concealed
              ? _reveal
              : () => _openFile(share: false)
        : null;
    return SuchiCard(
      key: const ValueKey('document-preview'),
      color: colors.manila,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: concealed ? 'Reveal document preview' : 'Open document',
            child: InkWell(
              onTap: activate,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 300),
                    child: Center(child: well),
                  ),
                  if (!concealed)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.end,
                        children: [
                          if (document.isSensitive && _revealed)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                backgroundColor: colors.surface.withValues(
                                  alpha: 0.94,
                                ),
                              ),
                              onPressed: _hide,
                              icon: const Icon(
                                Icons.visibility_off_outlined,
                                size: 18,
                              ),
                              label: const Text('Hide'),
                            ),
                          Tooltip(
                            message: _fileLoading
                                ? 'Cancel document handoff'
                                : 'Open document',
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(48, 48),
                              ),
                              onPressed: _fileLoading
                                  ? widget.files.cancelPending
                                  : activate,
                              icon: _fileLoading
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.open_in_new, size: 18),
                              label: Text(_fileLoading ? 'Cancel' : 'Open'),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          _previewFooter(
            document,
            offlineEntry: offlineEntry,
            offlineOutdated: offlineOutdated,
          ),
        ],
      ),
    );
  }

  Widget _offlinePreviewContent() {
    final colors = SuchiColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 38, color: colors.muted),
          const SizedBox(height: 12),
          Text(
            'Preview unavailable offline',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Open the protected full copy to view this document.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _previewFooter(
    DocumentDetail document, {
    required OfflineDocument? offlineEntry,
    required bool offlineOutdated,
  }) {
    final colors = SuchiColors.of(context);
    final control = _offlineControl(offlineEntry, offlineOutdated);
    final fileInfo = Wrap(
      spacing: 9,
      runSpacing: 7,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        QuietBadge(_friendlyType(document.mimeType)),
        Text(
          _formatBytes(document.originalSize),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final stacked = constraints.maxWidth < 420 || scale > 1.25;
          if (control == null) return fileInfo;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                fileInfo,
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft, child: control),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: fileInfo),
              const SizedBox(width: 8),
              Flexible(
                child: Align(alignment: Alignment.centerRight, child: control),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget? _offlineControl(OfflineDocument? offlineEntry, bool offlineOutdated) {
    final store = widget.offlineDocuments;
    if (store == null) return null;
    if (_offlineMutating) {
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              semanticsLabel: _offlineProgressLabel,
            ),
          ),
          Text(_offlineProgressLabel),
          TextButton(
            onPressed: store.cancelPending,
            child: const Text('Cancel'),
          ),
        ],
      );
    }
    final enabled = !_mutating && !_fileLoading;
    if (offlineEntry == null) {
      return TextButton.icon(
        onPressed: enabled ? _saveOffline : null,
        icon: const Icon(Icons.download_for_offline_outlined),
        label: const Text('Make available offline'),
      );
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!offlineOutdated)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.offline_pin, size: 18),
                SizedBox(width: 6),
                Text('Available offline'),
              ],
            ),
          ),
        if (offlineOutdated)
          TextButton.icon(
            onPressed: enabled ? _saveOffline : null,
            icon: const Icon(Icons.update),
            label: const Text('Update offline copy'),
          ),
        TextButton.icon(
          onPressed: enabled ? _removeOffline : null,
          icon: const Icon(Icons.remove_circle_outline),
          label: const Text('Remove offline copy'),
        ),
      ],
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
          height: 270,
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

  static String _formatDate(int seconds) => DateFormat.yMMMd().format(
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true).toLocal(),
  );

  static String? _sender(DocumentDetail document) {
    for (final correspondent in document.correspondents) {
      if (correspondent.role.trim().toLowerCase() == 'sender') {
        final name = correspondent.name.trim();
        return name.isEmpty ? null : name;
      }
    }
    if (document.correspondents.isEmpty) return null;
    final name = document.correspondents.first.name.trim();
    return name.isEmpty ? null : name;
  }

  static String _filedUnder(DocumentDetail document) {
    final path = <String>[
      if (document.jdAreaName?.trim().isNotEmpty == true)
        document.jdAreaName!.trim(),
      if (document.jdCategoryName?.trim().isNotEmpty == true)
        document.jdCategoryName!.trim(),
    ];
    if (path.isEmpty) return document.jdCategoryCode?.toString() ?? 'None';
    final label = path.join(' / ');
    return document.jdCategoryCode == null
        ? label
        : '${document.jdCategoryCode} · $label';
  }

  static String _sourceName(DocumentSource source) {
    final label = source.label.trim();
    final kind = source.kind.trim();
    if (label.isEmpty) return kind.isEmpty ? 'None' : kind;
    if (kind.isEmpty || label.toLowerCase() == kind.toLowerCase()) return label;
    return '$label / $kind';
  }

  static String _shortBlob(String digest) {
    if (digest.length <= 16) return digest;
    return '${digest.substring(0, 8)}…${digest.substring(digest.length - 8)}';
  }

  static String _friendlyType(String mimeType) {
    final normalized = mimeType.split(';').first.trim().toLowerCase();
    return switch (normalized) {
      'application/pdf' => 'PDF',
      'message/rfc822' => 'EMAIL',
      'text/plain' => 'TEXT',
      'text/html' => 'HTML',
      'image/jpeg' => 'JPEG',
      'image/png' => 'PNG',
      'image/heic' || 'image/heif' => 'HEIC',
      'application/msword' ||
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
        'WORD',
      'application/vnd.ms-excel' ||
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' =>
        'EXCEL',
      'application/vnd.ms-powerpoint' ||
      'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
        'POWERPOINT',
      'application/zip' => 'ZIP',
      _ when normalized.startsWith('image/') => 'IMAGE',
      _ when normalized.startsWith('audio/') => 'AUDIO',
      _ when normalized.startsWith('video/') => 'VIDEO',
      _ => 'FILE',
    };
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
          'The preview will load only after you choose Reveal.',
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
  const _MetaRow({
    required this.label,
    required this.value,
    required this.showDivider,
  });

  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodySmall;
    final valueStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: SuchiColors.of(context).ink);
    return Semantics(
      container: true,
      label: '$label: $value',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final stacked = constraints.maxWidth < 290 || scale > 1.3;
            return Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                border: showDivider
                    ? Border(
                        bottom: BorderSide(color: SuchiColors.of(context).line),
                      )
                    : null,
              ),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(label, style: labelStyle),
                        const SizedBox(height: 5),
                        Text(value, style: valueStyle),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 92,
                          child: Text(label, style: labelStyle),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(value, style: valueStyle)),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

String _classification(String sensitivity) => switch (sensitivity) {
  'public' => 'Public',
  'internal' => 'Internal',
  'confidential' => 'Confidential',
  'restricted' => 'Restricted',
  _ => 'Not set',
};

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
            SuchiCard(
              color: colors.manila,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 300),
                  Container(
                    color: colors.surface,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        bar(58, 24),
                        const SizedBox(width: 10),
                        bar(64, 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            bar(double.infinity, 28),
            const SizedBox(height: 8),
            bar(210, 28),
            const SizedBox(height: 12),
            bar(180, 20),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: bar(double.infinity, 52)),
                const SizedBox(width: 8),
                Expanded(child: bar(double.infinity, 52)),
              ],
            ),
            const SizedBox(height: 20),
            bar(60, 12),
            const SizedBox(height: 8),
            SuchiCard(
              elevated: false,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  bar(double.infinity, 16),
                  const SizedBox(height: 18),
                  bar(180, 16),
                  const SizedBox(height: 18),
                  bar(150, 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
