import 'package:flutter/material.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../auth/session_controller.dart';
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
    this.refreshRevision = 0,
    super.key,
  });

  final SuchiClient client;
  final SessionController session;
  final ThumbnailMemoryCache cache;
  final JdCategoryStore categories;
  final VoidCallback onOpenSearch;
  final ValueChanged<int> onOpenDocument;
  final DocumentListMode listMode;
  final int refreshRevision;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scroll = ScrollController();
  List<DocumentSummary> _documents = const [];
  ApiException? _error;
  int? _categoryId;
  String _ordering = '-created_at';
  int _count = 0;
  int _page = 0;
  int _generation = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    widget.categories.load();
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant DocumentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _categoryId = null;
      _ordering = '-created_at';
      widget.categories.load();
      _load(reset: true);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } else if (oldWidget.refreshRevision != widget.refreshRevision) {
      _load(reset: true);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _generation++;
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 280) _loadMore();
  }

  Future<void> _load({required bool reset}) async {
    if (!reset && (_loading || _loadingMore)) return;
    final generation = reset ? ++_generation : _generation;
    setState(() {
      _error = null;
      if (reset) {
        _loading = true;
        _loadingMore = false;
        _documents = const [];
        _count = 0;
        _page = 0;
        _hasMore = false;
      } else {
        _loadingMore = true;
      }
    });
    final requestedPage = reset ? 1 : _page + 1;
    try {
      final result = await widget.client.listDocuments(
        page: requestedPage,
        pageSize: 30,
        jdCategoryId: _categoryId,
        ordering: _ordering,
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
      if (error.expiresSession) widget.session.expire(error);
      setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loading || _loadingMore) return;
    await _load(reset: false);
  }

  void _selectCategory(JDCategory? category) {
    Navigator.maybePop(context);
    final selected = category?.id;
    if (selected == _categoryId) return;
    setState(() => _categoryId = selected);
    _load(reset: true);
  }

  void _selectSort(String ordering) {
    if (ordering == _ordering) return;
    setState(() => _ordering = ordering);
    _load(reset: true);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    final selectedCategory = widget.categories.categories
        .where((category) => category.id == _categoryId)
        .firstOrNull;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: colors.paper,
      endDrawer: Drawer(
        backgroundColor: colors.paper,
        width: MediaQuery.sizeOf(context).width * 0.9,
        child: SafeArea(
          child: JdIndex(
            store: widget.categories,
            title: 'Filter by JD Index',
            selectedId: _categoryId,
            includeAll: true,
            onAllSelected: () => _selectCategory(null),
            onSelected: _selectCategory,
          ),
        ),
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
                        tooltip: 'Sort documents',
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
                    message: 'Open JD Index',
                    child: InkWell(
                      onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                selectedCategory?.label ?? 'All documents',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: selectedCategory == null
                                          ? colors.muted
                                          : colors.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.expand_more, color: colors.muted),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!_loading && _error == null)
                    Text(
                      '$_count ${_count == 1 ? 'document' : 'documents'}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.muted),
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

  Widget _body() {
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
          children: const [
            SizedBox(height: 80),
            EmptyState(
              title: 'No documents here',
              message: 'Scan a document or choose another JD category.',
              icon: Icons.folder_open_outlined,
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
            return Padding(
              key: ValueKey(document.id),
              padding: EdgeInsets.only(
                bottom: switch (widget.listMode) {
                  DocumentListMode.standard => 8,
                  DocumentListMode.compact => 6,
                  DocumentListMode.detailed => 10,
                },
              ),
              child: SuchiCard(
                child: IndexRow(
                  document: document,
                  mode: widget.listMode,
                  client: widget.client,
                  cache: widget.cache,
                  onTap: () => widget.onOpenDocument(document.id),
                  onUnauthorized: widget.session.expire,
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
