import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../auth/account_identity.dart';
import '../auth/session_controller.dart';
import '../documents/thumbnail_cache.dart';
import '../theme/suchi_theme.dart';
import '../widgets/suchi_widgets.dart';
import 'saved_views.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    required this.client,
    required this.session,
    required this.cache,
    required this.onOpenDocument,
    required this.onOpenSavedView,
    this.savedViews,
    this.focusRequest,
    this.active = true,
    super.key,
  });

  final SuchiClient client;
  final SessionController session;
  final ThumbnailMemoryCache cache;
  final ValueChanged<int> onOpenDocument;
  final ValueChanged<SavedView> onOpenSavedView;
  final SavedViewController? savedViews;

  /// Whether the IndexedStack currently displays Search.
  final bool active;

  /// A Documents shortcut request; ordinary tab selection leaves this null.
  final int? focusRequest;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  final _focusNode = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounce;
  List<SearchHit> _results = const [];
  ApiException? _error;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 0;
  int _generation = 0;
  int _identityGeneration = 0;
  AccountIdentity? _identity;

  @override
  void initState() {
    super.initState();
    _query.addListener(_queryChanged);
    _scroll.addListener(_onScroll);
    _identity = _currentIdentity;
    widget.session.addListener(_sessionChanged);
    widget.savedViews?.addListener(_savedViewsChanged);
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_sessionChanged);
      widget.session.addListener(_sessionChanged);
      _sessionChanged();
    }
    if (oldWidget.savedViews != widget.savedViews) {
      oldWidget.savedViews?.removeListener(_savedViewsChanged);
      widget.savedViews?.addListener(_savedViewsChanged);
    }
    if (!widget.active) {
      _focusNode.unfocus();
    } else if (widget.focusRequest != null &&
        widget.focusRequest != oldWidget.focusRequest) {
      final request = widget.focusRequest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.active &&
            widget.focusRequest == request &&
            widget.session.user != null) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _query.dispose();
    _focusNode.dispose();
    _scroll.dispose();
    widget.session.removeListener(_sessionChanged);
    widget.savedViews?.removeListener(_savedViewsChanged);
    super.dispose();
  }

  AccountIdentity? get _currentIdentity => widget.session.identity;

  void _sessionChanged() {
    final identity = _currentIdentity;
    if (identity == _identity) return;
    _identity = identity;
    _identityGeneration++;
    _focusNode.unfocus();
    _query.clear();
    _queryChanged();
  }

  void _savedViewsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _saveView() async {
    final savedViews = widget.savedViews;
    final query = _query.text.trim();
    if (savedViews == null || query.isEmpty || !savedViews.ready) return;
    final identityGeneration = _identityGeneration;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _SaveViewDialog(),
    );
    if (!mounted ||
        name == null ||
        identityGeneration != _identityGeneration ||
        savedViews != widget.savedViews) {
      return;
    }
    final saved = await savedViews.save(name: name, query: query);
    if (mounted &&
        !saved &&
        identityGeneration == _identityGeneration &&
        savedViews.errorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(savedViews.errorMessage!)));
    }
  }

  Future<void> _removeView(SavedView view) async {
    final savedViews = widget.savedViews;
    if (savedViews == null || !savedViews.ready) return;
    final identityGeneration = _identityGeneration;
    final removed = await savedViews.remove(view.id);
    if (mounted &&
        !removed &&
        identityGeneration == _identityGeneration &&
        savedViews == widget.savedViews &&
        savedViews.errorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(savedViews.errorMessage!)));
    }
  }

  void _queryChanged() {
    _debounce?.cancel();
    final generation = ++_generation;
    final query = _query.text.trim();
    setState(() {
      _results = const [];
      _error = null;
      _loading = query.isNotEmpty;
      _loadingMore = false;
      _hasMore = false;
      _page = 0;
    });
    if (query.isEmpty) return;
    _debounce = Timer(
      const Duration(milliseconds: 320),
      () => _search(query: query, page: 1, generation: generation),
    );
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 260 &&
        _hasMore &&
        !_loading &&
        !_loadingMore) {
      _search(
        query: _query.text.trim(),
        page: _page + 1,
        generation: _generation,
      );
    }
  }

  Future<void> _search({
    required String query,
    required int page,
    required int generation,
  }) async {
    if (query.isEmpty || generation != _generation) return;
    setState(() {
      if (page == 1) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });
    try {
      final response = await widget.client.search(
        query: query,
        page: page,
        pageSize: 25,
      );
      if (!mounted ||
          generation != _generation ||
          query != _query.text.trim()) {
        return;
      }
      setState(() {
        _results = page == 1
            ? List.unmodifiable(response.results)
            : List.unmodifiable([..._results, ...response.results]);
        _page = page;
        _hasMore = response.next != null;
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

  void _retry() {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    final generation = ++_generation;
    _search(query: query, page: 1, generation: generation);
  }

  @override
  Widget build(BuildContext context) => widget.session.user == null
      ? const SizedBox.shrink()
      : SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SuchiPageHeader(
                serverLabel: widget.session.user!.instanceHost,
                userLabel: widget.session.user!.label,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 4, 17, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Search',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('archive-search'),
                      controller: _query,
                      focusNode: _focusNode,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search every word in your archive',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: _query.clear,
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                    if (widget.savedViews != null &&
                        _query.text.trim().isNotEmpty)
                      TextButton.icon(
                        key: const ValueKey('save-view'),
                        onPressed: widget.savedViews!.ready ? _saveView : null,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                        label: const Text('Save as Saved View'),
                      ),
                  ],
                ),
              ),
              Expanded(child: _body()),
            ],
          ),
        );

  Widget _body() {
    final colors = SuchiColors.of(context);
    final query = _query.text.trim();
    final searches = widget.savedViews;
    if (query.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(17, 5, 17, 28),
        children: [
          Text(
            'Search titles and document text. Sensitive excerpts stay hidden.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.muted),
          ),
          if (searches != null) ...[
            const SizedBox(height: 22),
            const SectionLabel('Saved Views'),
            const SizedBox(height: 8),
            Text(
              'Synced with your Suchi server.',
              style: TextStyle(color: colors.muted),
            ),
            const SizedBox(height: 12),
            if (searches.errorMessage case final message?) ...[
              InlineError(message: message, onRetry: searches.reload),
              const SizedBox(height: 12),
            ],
            if (searches.loading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            if (searches.entries.isEmpty &&
                !searches.loading &&
                searches.errorMessage == null)
              Text(
                'Run a search, then save it as a Saved View.',
                style: TextStyle(color: colors.muted),
              ),
            for (final entry in searches.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: SuchiCard(
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: InkWell(
                          key: ValueKey('saved-view-${entry.id}'),
                          onTap: () => widget.onOpenSavedView(entry),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  entry.available
                                      ? entry.filter!.summary
                                      : 'Unavailable on this app version',
                                  style: TextStyle(
                                    color: entry.available
                                        ? colors.muted
                                        : Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete ${entry.name}',
                        onPressed: searches.ready && entry.ownerId == null
                            ? () => _removeView(entry)
                            : null,
                        icon: const Icon(Icons.delete_outline, size: 21),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      );
    }
    if (_loading && _results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 17),
        child: ListSkeleton(rows: 4),
      );
    }
    final error = _error;
    if (error != null && _results.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 17),
        children: [
          InlineError(
            message: error.statusCode == 400
                ? 'That search was not accepted. Try fewer or simpler terms.'
                : friendlyApiMessage(
                    error,
                    fallback: 'Search results could not be loaded.',
                  ),
            requestId: error.requestId,
            onRetry: _retry,
          ),
        ],
      );
    }
    if (_results.isEmpty) {
      return ListView(
        children: const [
          EmptyState(
            title: 'No matches',
            message: 'Try another name, date, sender, or phrase.',
            icon: Icons.search_off,
          ),
        ],
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(17, 0, 17, 28),
      itemCount: _results.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 9),
            child: SectionLabel('${_results.length} results'),
          );
        }
        final resultIndex = index - 1;
        if (resultIndex < _results.length) {
          final hit = _results[resultIndex];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SuchiCard(
              child: _SearchRow(
                hit: hit,
                client: widget.client,
                cache: widget.cache,
                onTap: () => widget.onOpenDocument(hit.id),
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
        if (error != null) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: InlineError(
              message: friendlyApiMessage(
                error,
                fallback: 'More results could not be loaded.',
              ),
              requestId: error.requestId,
              onRetry: () => _search(
                query: query,
                page: _page + 1,
                generation: _generation,
              ),
            ),
          );
        }
        if (_hasMore) {
          return Center(
            child: TextButton(
              onPressed: () => _search(
                query: query,
                page: _page + 1,
                generation: _generation,
              ),
              child: const Text('Load more'),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _SaveViewDialog extends StatefulWidget {
  const _SaveViewDialog();

  @override
  State<_SaveViewDialog> createState() => _SaveViewDialogState();
}

class _SaveViewDialogState extends State<_SaveViewDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save as Saved View'),
    scrollable: true,
    content: TextField(
      key: const ValueKey('saved-view-name'),
      controller: _name,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(labelText: 'Name'),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _name.text.trim().isEmpty ? null : _save,
        child: const Text('Save'),
      ),
    ],
  );
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.hit,
    required this.client,
    required this.cache,
    required this.onTap,
    required this.onUnauthorized,
  });

  final SearchHit hit;
  final SuchiClient client;
  final ThumbnailMemoryCache cache;
  final VoidCallback onTap;
  final void Function(ApiException error) onUnauthorized;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 82),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            DocumentThumb(
              client: client,
              cache: cache,
              documentId: hit.id,
              sensitive: hit.isSensitive,
              onUnauthorized: onUnauthorized,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hit.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  if (hit.isSensitive)
                    Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: SuchiColors.of(context).muted,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '${sensitivityLabel(hit.sensitivity)} excerpt hidden',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    )
                  else if (hit.snippet.isNotEmpty)
                    Text.rich(
                      TextSpan(
                        children: sanitizedHighlightSpans(
                          hit.snippet,
                          highlightStyle: TextStyle(
                            color: SuchiColors.of(context).ink,
                            backgroundColor: SuchiColors.of(context).manila,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: SuchiColors.of(context).muted),
          ],
        ),
      ),
    ),
  );
}

List<InlineSpan> sanitizedHighlightSpans(
  String snippet, {
  required TextStyle highlightStyle,
}) {
  final spans = <InlineSpan>[];
  final tags = RegExp(r'</?mark>');
  var cursor = 0;
  var highlighted = false;
  for (final match in tags.allMatches(snippet)) {
    if (match.start > cursor) {
      spans.add(
        TextSpan(
          text: snippet.substring(cursor, match.start),
          style: highlighted ? highlightStyle : null,
        ),
      );
    }
    highlighted = match.group(0) == '<mark>';
    cursor = match.end;
  }
  if (cursor < snippet.length) {
    spans.add(
      TextSpan(
        text: snippet.substring(cursor),
        style: highlighted ? highlightStyle : null,
      ),
    );
  }
  return spans;
}
