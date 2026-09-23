import 'package:flutter/material.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../auth/session_controller.dart';
import '../documents/document_list_mode.dart';
import '../documents/jd_category_store.dart';
import '../documents/jd_index.dart';
import '../documents/thumbnail_cache.dart';
import '../theme/suchi_theme.dart';
import '../widgets/suchi_widgets.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    required this.client,
    required this.session,
    required this.cache,
    required this.categories,
    required this.onOpenDocument,
    required this.listMode,
    this.refreshRevision = 0,
    super.key,
  });

  final SuchiClient client;
  final SessionController session;
  final ThumbnailMemoryCache cache;
  final JdCategoryStore categories;
  final ValueChanged<int> onOpenDocument;
  final DocumentListMode listMode;
  final int refreshRevision;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final ScrollController _scroll = ScrollController();
  List<DocumentSummary> _documents = const [];
  final Set<int> _mutating = {};
  ApiException? _error;
  String? _configurationError;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _count = 0;
  int _page = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _initialize();
  }

  @override
  void didUpdateWidget(covariant InboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _mutating.clear();
      _initialize();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } else if (oldWidget.refreshRevision != widget.refreshRevision) {
      _refresh();
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

  Future<void> _initialize() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasMore = false;
      _page = 0;
      _count = 0;
      _documents = const [];
      _error = null;
      _configurationError = null;
    });
    await widget.categories.load();
    if (!mounted || generation != _generation) return;
    final category = widget.categories.inboxCategory;
    if (category == null) {
      setState(() {
        _loading = false;
        _configurationError = widget.categories.error == null
            ? 'This Suchi server does not define Inbox category 49.'
            : null;
        _error = widget.categories.error;
      });
      return;
    }
    await _loadDocuments(
      generation: generation,
      categoryId: category.id,
      reset: true,
    );
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    final category = widget.categories.inboxCategory;
    if (category == null) {
      await widget.categories.load(force: true);
      if (!mounted || generation != _generation) return;
      return _initialize();
    }
    await _loadDocuments(
      generation: generation,
      categoryId: category.id,
      reset: true,
    );
  }

  Future<void> _loadDocuments({
    required int generation,
    required int categoryId,
    required bool reset,
  }) async {
    if (!reset && (_loading || _loadingMore || !_hasMore)) return;
    if (!reset) {
      setState(() {
        _loadingMore = true;
        _error = null;
      });
    }
    final requestedPage = reset ? 1 : _page + 1;
    try {
      final response = await widget.client.listDocuments(
        page: requestedPage,
        pageSize: 30,
        jdCategoryId: categoryId,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _documents = reset
            ? List.unmodifiable(response.results)
            : List.unmodifiable([..._documents, ...response.results]);
        _count = response.count;
        _page = requestedPage;
        _hasMore = response.next != null;
        _error = null;
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
    final category = widget.categories.inboxCategory;
    if (category == null) return;
    await _loadDocuments(
      generation: _generation,
      categoryId: category.id,
      reset: false,
    );
  }

  Future<void> _chooseFiling(DocumentSummary document) async {
    final category = await showJdCategorySheet(
      context,
      store: widget.categories,
      title: 'File “${document.title}” under',
    );
    if (!mounted || category == null) return;
    if (category.id == widget.categories.inboxCategory?.id) return;
    await _mutate(
      document,
      () => widget.client.patchDocument(document.id, jdCategoryId: category.id),
      successMessage: 'Filed under ${category.label}.',
    );
  }

  Future<void> _trash(DocumentSummary document) async {
    if (_mutating.contains(document.id)) return;
    final index = _documents.indexWhere((item) => item.id == document.id);
    if (index < 0) return;
    setState(() => _mutating.add(document.id));
    try {
      await widget.client.trashDocument(document.id);
      if (!mounted) return;
      setState(() {
        _documents = List.unmodifiable(
          _documents.where((item) => item.id != document.id),
        );
        _count--;
        _mutating.remove(document.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Document moved to Trash.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _restore(document, index),
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.expiresSession) widget.session.expire(error);
      setState(() => _mutating.remove(document.id));
      _showFailure(error, 'The document could not be moved to Trash.');
    }
  }

  Future<void> _restore(DocumentSummary document, int index) async {
    try {
      await widget.client.restoreDocument(document.id);
      if (!mounted || _documents.any((item) => item.id == document.id)) return;
      final restored = [..._documents];
      restored.insert(index.clamp(0, restored.length), document);
      setState(() {
        _documents = List.unmodifiable(restored);
        _count++;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.expiresSession) widget.session.expire(error);
      _showFailure(error, 'The document could not be restored.');
    }
  }

  Future<void> _mutate(
    DocumentSummary document,
    Future<Object?> Function() action, {
    required String successMessage,
  }) async {
    if (_mutating.contains(document.id)) return;
    setState(() => _mutating.add(document.id));
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _documents = List.unmodifiable(
          _documents.where((item) => item.id != document.id),
        );
        _count--;
        _mutating.remove(document.id);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.expiresSession) widget.session.expire(error);
      setState(() => _mutating.remove(document.id));
      _showFailure(error, 'The document could not be filed.');
    }
  }

  void _showFailure(ApiException error, String fallback) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyApiMessage(error, fallback: fallback))),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SuchiPageHeader(
          serverLabel: widget.session.user!.instanceHost,
          userLabel: widget.session.user!.label,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(17, 4, 17, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Inbox',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _documents.isEmpty
                          ? 'Everything has a home.'
                          : 'A few things need a home.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              QuietBadge('$_count waiting'),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    ),
  );

  Widget _body() {
    if (_loading && _documents.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 17),
        children: [ListSkeleton(rows: 4, mode: widget.listMode)],
      );
    }
    final error = _error;
    if (error != null && _documents.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 17),
        children: [
          InlineError(
            message: friendlyApiMessage(
              error,
              fallback: 'Inbox could not be loaded.',
            ),
            requestId: error.requestId,
            onRetry: _initialize,
          ),
        ],
      );
    }
    if (_configurationError != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 17),
        children: [
          InlineError(message: _configurationError!, onRetry: _initialize),
        ],
      );
    }
    if (_documents.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            EmptyState(
              title: 'Inbox clear',
              message: 'New scans arrive here until you file them.',
              icon: Icons.inbox_outlined,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(17, 0, 17, 28),
        itemCount: _documents.length + 2,
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Dismissible(
                    key: ValueKey('inbox-${document.id}'),
                    direction: _mutating.contains(document.id)
                        ? DismissDirection.none
                        : DismissDirection.horizontal,
                    confirmDismiss: (direction) async {
                      if (direction == DismissDirection.startToEnd) {
                        await _chooseFiling(document);
                      } else {
                        await _trash(document);
                      }
                      return false;
                    },
                    background: _SwipeAction(
                      alignment: Alignment.centerLeft,
                      color: SuchiColors.of(context).success,
                      icon: Icons.drive_file_move_outline,
                      label: 'File',
                    ),
                    secondaryBackground: _SwipeAction(
                      alignment: Alignment.centerRight,
                      color: SuchiColors.of(context).danger,
                      icon: Icons.delete_outline,
                      label: 'Trash',
                    ),
                    child: IndexRow(
                      document: document,
                      mode: widget.listMode,
                      client: widget.client,
                      cache: widget.cache,
                      enabled: !_mutating.contains(document.id),
                      onTap: () => widget.onOpenDocument(document.id),
                      onUnauthorized: widget.session.expire,
                    ),
                  ),
                ),
              ),
            );
          }
          if (index == _documents.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 10),
              child: Text(
                'Swipe right to file · left to trash · trash offers Undo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: SuchiColors.of(context).faint,
                  fontSize: 10.5,
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
          if (error != null) {
            return InlineError(
              message: friendlyApiMessage(
                error,
                fallback: 'More Inbox items could not be loaded.',
              ),
              requestId: error.requestId,
              onRetry: _loadMore,
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

class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: SuchiColors.of(context).onAccent),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: SuchiColors.of(context).onAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
