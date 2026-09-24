import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../auth/account_identity.dart';
import '../auth/session_controller.dart';
import '../offline/offline_document_store.dart';
import '../scan/network_monitor.dart';
import '../theme/suchi_theme.dart';
import '../widgets/suchi_widgets.dart';
import 'document_list_mode.dart';
import 'jd_category_store.dart';
import 'jd_index.dart';
import 'thumbnail_cache.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({
    required this.client,
    required this.session,
    required this.cache,
    required this.categories,
    required this.onOpenSearch,
    required this.onOpenDocument,
    required this.listMode,
    this.offlineDocuments,
    this.network,
    this.onOpenOfflineDocument,
    this.savedView,
    this.savedViewRevision = 0,
    this.refreshRevision = 0,
    super.key,
  });

  final SuchiClient? client;
  final SessionController session;
  final ThumbnailMemoryCache cache;
  final JdCategoryStore? categories;
  final VoidCallback onOpenSearch;
  final ValueChanged<int> onOpenDocument;
  final ValueChanged<OfflineDocument>? onOpenOfflineDocument;
  final OfflineDocumentStore? offlineDocuments;
  final NetworkMonitor? network;
  final DocumentListMode listMode;
  final SavedView? savedView;
  final int savedViewRevision;
  final int refreshRevision;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  AccountIdentity? _copyIdentity;
  SuchiClient? _copyClient;
  OfflineDocumentStore? _copyStore;
  int? _copyDocumentId;
  bool _copySaving = false;
  String _copyProgressLabel = 'Saving offline copy…';
  int _copyToken = 0;
  final _scroll = ScrollController();
  List<DocumentSummary> _documents = const [];
  Map<int, OfflineDocument> _offlineById = const {};
  StreamSubscription<bool>? _networkSubscription;
  ApiException? _error;
  int? _categoryId;
  String _ordering = '-created_at';
  SavedView? _activeView;
  String? _scopeError;
  int _count = 0;
  int _page = 0;
  int _generation = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _offlineSelected = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _offlineSelected =
        widget.session.state == SessionState.offline || widget.client == null;
    _activeView = _offlineSelected ? null : widget.savedView;
    _ordering = _activeView?.filter?.ordering ?? '-created_at';
    widget.categories?.load();
    widget.offlineDocuments?.addListener(_offlineDocumentsChanged);
    widget.session.addListener(_sessionChanged);
    _listenToNetwork();
    if (_offlineSelected) {
      _loadOffline();
    } else {
      _startOnlineLoad();
    }
  }

  @override
  void didUpdateWidget(covariant DocumentsScreen oldWidget) {
    if (oldWidget.offlineDocuments != widget.offlineDocuments ||
        oldWidget.client != widget.client) {
      _cancelCopy();
    }
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offlineDocuments != widget.offlineDocuments) {
      oldWidget.offlineDocuments?.removeListener(_offlineDocumentsChanged);
      widget.offlineDocuments?.addListener(_offlineDocumentsChanged);
    }
    if (oldWidget.network != widget.network) _listenToNetwork();
    if (oldWidget.client != widget.client) {
      _categoryId = null;
      _activeView = null;
      _scopeError = null;
      _ordering = '-created_at';
      _offlineSelected =
          widget.session.state == SessionState.offline || widget.client == null;
      widget.categories?.load();
      if (_offlineSelected) {
        _loadOffline();
      } else {
        _startOnlineLoad();
      }
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } else if (oldWidget.savedViewRevision != widget.savedViewRevision &&
        widget.client != null) {
      _activateSavedView(widget.savedView);
    } else if (oldWidget.refreshRevision != widget.refreshRevision) {
      _load(reset: true);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.session.removeListener(_sessionChanged);
    _cancelCopy();
    _networkSubscription?.cancel();
    widget.offlineDocuments?.removeListener(_offlineDocumentsChanged);
    _scroll.dispose();
    super.dispose();
  }

  bool _copyIsCurrent(AccountIdentity identity, SuchiClient client) =>
      mounted &&
      widget.session.state == SessionState.signedIn &&
      widget.session.identity == identity &&
      identical(widget.session.client, client) &&
      identical(widget.client, client) &&
      !_offlineSelected;

  void _cancelCopy() {
    _copyToken++;
    if (_copySaving) _copyStore?.cancelPending();
    _clearCopy();
  }

  void _clearCopy() {
    _copyIdentity = null;
    _copyClient = null;
    _copyStore = null;
    _copyDocumentId = null;
    _copySaving = false;
  }

  void _sessionChanged() {
    final identity = _copyIdentity;
    final client = _copyClient;
    if (identity == null ||
        client == null ||
        _copyIsCurrent(identity, client)) {
      return;
    }
    _cancelCopy();
    if (mounted) setState(() {});
  }

  void _showCopyError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _makeAvailableOffline(DocumentSummary summary) async {
    final identity = widget.session.identity;
    final client = widget.client;
    final store = widget.offlineDocuments;
    if (identity == null ||
        client == null ||
        store == null ||
        _copyDocumentId != null ||
        !_copyIsCurrent(identity, client)) {
      return;
    }
    final ticket = ++_copyToken;
    bool current() =>
        ticket == _copyToken &&
        _copyIsCurrent(identity, client) &&
        identical(widget.offlineDocuments, store);
    setState(() {
      _copyIdentity = identity;
      _copyClient = client;
      _copyStore = store;
      _copyDocumentId = summary.id;
      _copyProgressLabel = 'Loading document…';
    });
    try {
      // List summaries are not authoritative: classification and file size can
      // change independently of a list page.
      final document = await client.document(summary.id);
      if (!mounted || !current()) {
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
        if (confirmed != true || !current()) {
          return;
        }
      }
      final updating = store.find(identity, document.id) != null;
      setState(() {
        _copyProgressLabel = updating
            ? 'Updating offline copy…'
            : 'Saving offline copy…';
        _copySaving = true;
      });
      await store.save(
        identity: identity,
        document: document,
        client: client,
        reveal: document.isSensitive,
      );
      if (!mounted || !current()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updating
                ? 'Offline copy updated.'
                : 'Document is available offline.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!current()) return;
      if (error.expiresSession) {
        widget.session.expire(error);
      } else if (error.kind != ApiFailureKind.cancelled) {
        _showCopyError(
          friendlyApiMessage(
            error,
            fallback: 'The offline copy could not be saved.',
          ),
        );
      }
    } on OfflineDocumentException catch (error) {
      if (current() && error.code != 'offline_cancelled') {
        _showCopyError(error.message);
      }
    } on FileSystemException {
      if (current()) {
        _showCopyError(
          'The offline copy could not be saved. Check available device storage and try again.',
        );
      }
    } finally {
      if (mounted && ticket == _copyToken) {
        setState(_clearCopy);
      }
    }
  }

  void _listenToNetwork() {
    unawaited(_networkSubscription?.cancel());
    _networkSubscription = widget.network?.changes.listen(_connectivityChanged);
  }

  void _startOnlineLoad() {
    final network = widget.network;
    if (network == null) {
      _load(reset: true);
      return;
    }
    unawaited(_loadWhenConnected(network));
  }

  Future<void> _loadWhenConnected(NetworkMonitor network) async {
    var online = true;
    try {
      online = await network.isOnline();
    } catch (_) {
      // The API request remains the authoritative connectivity check.
    }
    if (!mounted || _offlineSelected || network != widget.network) return;
    if (!online) {
      _selectOffline(closeDrawer: false);
    } else {
      await _load(reset: true);
    }
  }

  void _connectivityChanged(bool online) {
    if (!online && widget.client != null && !_offlineSelected) {
      _selectOffline(closeDrawer: false);
    }
  }

  void _offlineDocumentsChanged() {
    if (!mounted) return;
    if (_offlineSelected) {
      _loadOffline();
    } else {
      setState(() {});
    }
  }

  void _onScroll() {
    if (!_offlineSelected && _scroll.position.extentAfter < 280) _loadMore();
  }

  void _activateSavedView(SavedView? view) {
    _offlineSelected = false;
    _activeView = view;
    _categoryId = null;
    _scopeError = null;
    _ordering = view?.filter?.ordering ?? '-created_at';
    _load(reset: true);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _load({required bool reset}) async {
    if (_offlineSelected || widget.client == null) {
      _loadOffline();
      return;
    }
    if (!reset && (_loading || _loadingMore)) return;
    final activeView = _activeView;
    if (activeView != null && !activeView.available) {
      ++_generation;
      setState(() {
        _documents = const [];
        _offlineById = const {};
        _count = 0;
        _page = 0;
        _hasMore = false;
        _loading = false;
        _loadingMore = false;
        _error = null;
        _scopeError =
            'This Saved View cannot be opened in this app version. '
            '${activeView.filterError ?? 'Its filters are unsupported.'}';
      });
      return;
    }
    final generation = reset ? ++_generation : _generation;
    setState(() {
      _error = null;
      _scopeError = null;
      if (reset) {
        _loading = true;
        _loadingMore = false;
        _documents = const [];
        _offlineById = const {};
        _count = 0;
        _page = 0;
        _hasMore = false;
      } else {
        _loadingMore = true;
      }
    });
    final requestedPage = reset ? 1 : _page + 1;
    try {
      final result = await widget.client!.listDocuments(
        page: requestedPage,
        pageSize: 30,
        jdCategoryId: _categoryId,
        ordering: _ordering,
        savedViewFilter: activeView?.filter,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _documents = reset
            ? List.unmodifiable(result.results)
            : List.unmodifiable([..._documents, ...result.results]);
        _count = result.count;
        _page = requestedPage;
        _hasMore = result.next != null;
      });
    } on ApiException catch (error) {
      if (!mounted || generation != _generation) return;
      if (error.expiresSession) {
        widget.session.expire(error);
      } else if ((error.kind == ApiFailureKind.network ||
              error.kind == ApiFailureKind.timeout) &&
          widget.offlineDocuments != null) {
        _selectOffline(closeDrawer: false);
        return;
      } else {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _loadOffline() {
    final generation = ++_generation;
    final entries = widget.offlineDocuments
        ?.entriesFor(widget.session.identity)
        .toList(growable: false);
    final sorted = entries ?? <OfflineDocument>[];
    sorted.sort((left, right) {
      final comparison = switch (_ordering) {
        'created_at' => left.document.createdAt.compareTo(
          right.document.createdAt,
        ),
        'title' => left.document.title.toLowerCase().compareTo(
          right.document.title.toLowerCase(),
        ),
        '-title' => right.document.title.toLowerCase().compareTo(
          left.document.title.toLowerCase(),
        ),
        'updated_at' => left.document.updatedAt.compareTo(
          right.document.updatedAt,
        ),
        '-updated_at' => right.document.updatedAt.compareTo(
          left.document.updatedAt,
        ),
        _ => right.document.createdAt.compareTo(left.document.createdAt),
      };
      return comparison != 0
          ? comparison
          : left.document.id.compareTo(right.document.id);
    });
    if (!mounted || generation != _generation) return;
    setState(() {
      _documents = List.unmodifiable(sorted.map((entry) => entry.summary));
      _offlineById = Map.unmodifiable({
        for (final entry in sorted) entry.document.id: entry,
      });
      _count = sorted.length;
      _page = 1;
      _hasMore = false;
      _loading = false;
      _loadingMore = false;
      _error = null;
      _scopeError = null;
    });
  }

  Future<void> _loadMore() async {
    if (_offlineSelected || !_hasMore || _loading || _loadingMore) return;
    await _load(reset: false);
  }

  void _selectCategory(JDCategory? category, {bool closeDrawer = true}) {
    if (closeDrawer) Navigator.maybePop(context);
    final selected = category?.id;
    if (!_offlineSelected && _activeView == null && selected == _categoryId) {
      return;
    }
    setState(() {
      _offlineSelected = false;
      _activeView = null;
      _scopeError = null;
      _categoryId = selected;
      _ordering = '-created_at';
    });
    _load(reset: true);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _selectOffline({bool closeDrawer = true}) {
    if (closeDrawer) Navigator.maybePop(context);
    if (_offlineSelected) return;
    _cancelCopy();
    setState(() {
      _offlineSelected = true;
      _activeView = null;
      _categoryId = null;
      _scopeError = null;
      _ordering = '-created_at';
    });
    _loadOffline();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _selectSort(String ordering) {
    if (_activeView != null) return;
    if (ordering == _ordering) return;
    setState(() => _ordering = ordering);
    if (_offlineSelected) {
      _loadOffline();
    } else {
      _load(reset: true);
    }
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    final categories = widget.categories;
    JDCategory? selectedCategory;
    if (categories != null) {
      for (final category in categories.categories) {
        if (category.id == _categoryId) {
          selectedCategory = category;
          break;
        }
      }
    }
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: colors.paper,
      endDrawer: categories == null
          ? null
          : Drawer(
              backgroundColor: colors.paper,
              width: MediaQuery.sizeOf(context).width * 0.9,
              child: SafeArea(child: _scopeDrawer(categories)),
            ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SuchiPageHeader(
              serverLabel: widget.session.user!.instanceHost,
              userLabel: widget.session.user!.label,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    'Documents',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.client != null)
                        IconButton(
                          tooltip: 'Search documents',
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          onPressed: widget.onOpenSearch,
                          icon: const Icon(Icons.search),
                        ),
                      PopupMenuButton<String>(
                        tooltip: _activeView == null
                            ? 'Sort documents'
                            : 'Saved View controls sorting',
                        enabled: _activeView == null,
                        initialValue: _ordering,
                        onSelected: _selectSort,
                        icon: const Icon(Icons.sort),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        itemBuilder: (context) => [
                          for (final entry in const {
                            '-created_at': 'Newest first',
                            'created_at': 'Oldest first',
                            'title': 'Title A–Z',
                            '-updated_at': 'Recently updated',
                          }.entries)
                            CheckedPopupMenuItem(
                              value: entry.key,
                              checked: _ordering == entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Tooltip(
                    message: categories == null
                        ? 'Offline documents'
                        : 'Open JD Index',
                    child: InkWell(
                      onTap: categories == null
                          ? null
                          : () => _scaffoldKey.currentState?.openEndDrawer(),
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _offlineSelected
                                    ? 'Offline'
                                    : _activeView?.name ??
                                          selectedCategory?.label ??
                                          'All documents',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color:
                                          !_offlineSelected &&
                                              _activeView == null &&
                                              selectedCategory == null
                                          ? colors.muted
                                          : colors.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            if (categories != null) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.expand_more, color: colors.muted),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!_loading && _error == null && _scopeError == null)
                    Text(
                      '$_count ${_count == 1 ? 'document' : 'documents'}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.muted),
                    ),
                  if (widget.offlineDocuments != null)
                    FilterChip(
                      avatar: const Icon(Icons.offline_pin_outlined, size: 18),
                      label: Text(
                        'Saved offline · ${widget.offlineDocuments!.entriesFor(widget.session.identity).length}',
                      ),
                      selected: _offlineSelected,
                      onSelected: widget.client == null
                          ? null
                          : (selected) {
                              if (selected) {
                                _selectOffline(closeDrawer: false);
                              } else {
                                _selectCategory(null, closeDrawer: false);
                              }
                            },
                    ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _scopeDrawer(JdCategoryStore categories) => JdIndex(
    store: categories,
    title: 'Choose documents',
    selectedId: _categoryId,
    includeAll: true,
    onAllSelected: () => _selectCategory(null),
    onSelected: _selectCategory,
  );

  void _openSummary(DocumentSummary document) {
    if (!_offlineSelected) {
      widget.onOpenDocument(document.id);
      return;
    }
    final entry = _offlineById[document.id];
    if (entry != null) widget.onOpenOfflineDocument?.call(entry);
  }

  Widget _body() {
    if (_scopeError case final message?) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [InlineError(message: message)],
      );
    }
    if (_loading && _documents.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [ListSkeleton(mode: widget.listMode)],
      );
    }
    if (_error != null && _documents.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          InlineError(
            message: friendlyApiMessage(
              _error!,
              fallback: 'Documents could not be loaded.',
            ),
            requestId: _error!.requestId,
            onRetry: () => _load(reset: true),
          ),
        ],
      );
    }
    if (_documents.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          children: [
            const SizedBox(height: 80),
            EmptyState(
              title: _offlineSelected
                  ? 'No offline documents'
                  : 'No documents here',
              message: _offlineSelected
                  ? 'Make a document available offline while connected.'
                  : 'Scan a document or choose another JD category or Saved View.',
              icon: _offlineSelected
                  ? Icons.offline_pin_outlined
                  : Icons.folder_open_outlined,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        itemCount: _documents.length + 1,
        itemBuilder: (context, index) {
          if (index < _documents.length) {
            final document = _documents[index];
            final hasOfflineCopy =
                widget.offlineDocuments?.find(
                  widget.session.identity,
                  document.id,
                ) !=
                null;
            return Padding(
              key: ValueKey(document.id),
              padding: EdgeInsets.only(
                bottom: switch (widget.listMode) {
                  DocumentListMode.standard => 8,
                  DocumentListMode.compact => 6,
                  DocumentListMode.detailed => 10,
                },
              ),
              child:
                  _offlineSelected ||
                      widget.client == null ||
                      widget.offlineDocuments == null ||
                      widget.session.state != SessionState.signedIn
                  ? SuchiCard(
                      child: IndexRow(
                        document: document,
                        mode: widget.listMode,
                        client: _offlineSelected ? null : widget.client,
                        cache: widget.cache,
                        onTap: () => _openSummary(document),
                        onUnauthorized: widget.session.expire,
                      ),
                    )
                  : _OfflineSwipeRow(
                      enabled: _copyDocumentId == null,
                      actionLabel: hasOfflineCopy
                          ? 'Update offline copy'
                          : 'Make available offline',
                      compactActionLabel: hasOfflineCopy
                          ? 'Update offline'
                          : 'Save offline',
                      progressLabel: _copyDocumentId == document.id
                          ? _copyProgressLabel
                          : null,
                      onAction: () => _makeAvailableOffline(document),
                      onCancel: () => setState(_cancelCopy),
                      child: SuchiCard(
                        child: IndexRow(
                          document: document,
                          mode: widget.listMode,
                          client: widget.client,
                          cache: widget.cache,
                          onTap: () => _openSummary(document),
                          onUnauthorized: widget.session.expire,
                        ),
                      ),
                    ),
            );
          }
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final error = _error;
          if (error != null) {
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InlineError(
                message: friendlyApiMessage(
                  error,
                  fallback: 'More documents could not be loaded.',
                ),
                requestId: error.requestId,
                onRetry: _loadMore,
              ),
            );
          }
          if (_hasMore) {
            return Center(
              child: TextButton(
                onPressed: _loadMore,
                child: const Text('Load more'),
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

/// Reveals a non-destructive action without taking the row out of the list.
class _OfflineSwipeRow extends StatefulWidget {
  const _OfflineSwipeRow({
    required this.enabled,
    required this.actionLabel,
    required this.compactActionLabel,
    required this.progressLabel,
    required this.onAction,
    required this.onCancel,
    required this.child,
  });

  final bool enabled;
  final String actionLabel;
  final String compactActionLabel;
  final String? progressLabel;
  final VoidCallback onAction;
  final VoidCallback onCancel;
  final Widget child;

  @override
  State<_OfflineSwipeRow> createState() => _OfflineSwipeRowState();
}

class _OfflineSwipeRowState extends State<_OfflineSwipeRow> {
  static const _actionWidth = 184.0;
  double _exposed = 0;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    final compactLabel = MediaQuery.textScalerOf(context).scale(14) >= 21;
    final visibleLabel = compactLabel
        ? widget.compactActionLabel
        : widget.actionLabel;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _actionWidth.clamp(0.0, constraints.maxWidth).toDouble();
        return ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                width: width,
                child: IgnorePointer(
                  ignoring: _exposed == 0,
                  child: ExcludeSemantics(
                    excluding: _exposed == 0,
                    child: ColoredBox(
                      color: colors.success,
                      child: widget.progressLabel != null
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.onAccent,
                                    semanticsLabel: widget.progressLabel!,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    widget.progressLabel!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: colors.onAccent),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Cancel offline copy',
                                  color: colors.onAccent,
                                  onPressed: widget.onCancel,
                                  icon: const Icon(Icons.close, size: 18),
                                ),
                              ],
                            )
                          : SizedBox.expand(
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: colors.onAccent,
                                  disabledForegroundColor: colors.onAccent
                                      .withValues(alpha: 0.7),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: widget.enabled ? _startAction : null,
                                icon: const Icon(
                                  Icons.download_for_offline_outlined,
                                ),
                                label: Text(
                                  visibleLabel,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              AnimatedSlide(
                offset: Offset(
                  constraints.maxWidth == 0
                      ? 0
                      : _exposed / constraints.maxWidth,
                  0,
                ),
                duration: _dragging
                    ? Duration.zero
                    : SuchiMotion.standard(context),
                curve: Curves.easeOutCubic,
                child: Semantics(
                  customSemanticsActions:
                      widget.enabled && widget.progressLabel == null
                      ? {
                          CustomSemanticsAction(label: widget.actionLabel):
                              _startAction,
                        }
                      : const {},
                  child: GestureDetector(
                    behavior: HitTestBehavior.deferToChild,
                    onHorizontalDragStart: (_) =>
                        setState(() => _dragging = true),
                    onHorizontalDragUpdate: (details) => setState(() {
                      _exposed = (_exposed + details.delta.dx)
                          .clamp(0.0, width)
                          .toDouble();
                    }),
                    onHorizontalDragEnd: (details) => setState(() {
                      _dragging = false;
                      _exposed =
                          _exposed > width / 3 ||
                              (details.primaryVelocity ?? 0) > 300
                          ? width
                          : 0;
                    }),
                    onHorizontalDragCancel: () => setState(() {
                      _dragging = false;
                      _exposed = _exposed > width / 2 ? width : 0;
                    }),
                    child: widget.child,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _startAction() {
    setState(() => _exposed = 0);
    widget.onAction();
  }
}
