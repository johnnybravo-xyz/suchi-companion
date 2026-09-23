import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../auth/session_controller.dart';
import '../widgets/suchi_widgets.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({
    required this.client,
    required this.session,
    required this.onRestored,
    super.key,
  });

  final SuchiClient client;
  final SessionController session;
  final VoidCallback onRestored;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<DocumentSummary> _documents = const [];
  ApiException? _error;
  ApiException? _restoreError;
  int _count = 0;
  int _page = 0;
  int _generation = 0;
  int? _restoringId;
  bool _loading = false;
  bool _hasMore = false;

  bool get _currentSession =>
      widget.session.state == SessionState.signedIn &&
      identical(widget.session.client, widget.client);

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant TrashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_sessionChanged);
      widget.session.addListener(_sessionChanged);
    }
    if (oldWidget.client != widget.client ||
        oldWidget.session != widget.session) {
      _generation++;
      _restoringId = null;
      _load(reset: true);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    _generation++;
    super.dispose();
  }

  void _sessionChanged() {
    if (_currentSession) return;
    _generation++;
    setState(() {
      _documents = const [];
      _count = 0;
      _error = null;
      _restoreError = null;
      _loading = false;
      _restoringId = null;
      _hasMore = false;
    });
  }

  Future<void> _load({required bool reset}) async {
    if (!_currentSession || _restoringId != null || (!reset && _loading)) {
      return;
    }
    final generation = reset ? ++_generation : _generation;
    final requestedPage = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _documents = const [];
        _restoreError = null;
        _count = 0;
        _page = 0;
        _hasMore = false;
      }
    });
    try {
      final result = await widget.client.listDocuments(
        page: requestedPage,
        pageSize: 30,
        ordering: '-updated_at',
        trashed: true,
      );
      if (!mounted || generation != _generation || !_currentSession) return;
      setState(() {
        _documents = List.unmodifiable([
          if (!reset) ..._documents,
          ...result.results,
        ]);
        _count = result.count;
        _page = requestedPage;
        _hasMore = result.next != null;
      });
    } on ApiException catch (error) {
      if (!mounted || generation != _generation || !_currentSession) return;
      if (error.expiresSession) {
        await widget.session.expire(error);
        return;
      }
      setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _restore(DocumentSummary document) async {
    if (!_currentSession || _restoringId != null || _loading) return;
    final generation = _generation;
    setState(() {
      _restoringId = document.id;
      _restoreError = null;
    });
    try {
      await widget.client.restoreDocument(document.id);
      if (!mounted || generation != _generation || !_currentSession) return;
      setState(() => _restoringId = null);
      widget.onRestored();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restored “${document.title}”.')));
      // Restart paging after removal so shifted rows cannot be skipped.
      await _load(reset: true);
    } on ApiException catch (error) {
      if (!mounted || generation != _generation || !_currentSession) return;
      if (error.expiresSession) {
        await widget.session.expire(error);
        return;
      }
      setState(() => _restoreError = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _restoringId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Trash'),
      actions: [
        IconButton(
          tooltip: 'Refresh Trash',
          onPressed: _currentSession && !_loading && _restoringId == null
              ? () => _load(reset: true)
              : null,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: !_currentSession
        ? const EmptyState(
            title: 'Account changed',
            message: 'Go back to continue with your current Suchi account.',
            icon: Icons.lock_outline,
          )
        : RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(17, 8, 17, 30),
              children: [
                Text(
                  'Documents can be restored for 30 days after deletion. Your server checks whether they are still available.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                if (!_loading || _documents.isNotEmpty)
                  SectionLabel('$_count in Trash'),
                if (_restoreError case final error?) ...[
                  const SizedBox(height: 12),
                  InlineError(
                    message: friendlyApiMessage(
                      error,
                      fallback: 'This document could not be restored. Try Restore again.',
                    ),
                    requestId: error.requestId,
                  ),
                ],
                for (final document in _documents)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SuchiCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            document.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (document.trashedAt case final deletedAt?) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Deleted ${DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(deletedAt * 1000, isUtc: true).toLocal())}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: ValueKey('restore-${document.id}'),
                            onPressed: _restoringId == null && !_loading
                                ? () => _restore(document)
                                : null,
                            icon: const Icon(Icons.restore),
                            label: Text(
                              _restoringId == document.id
                                  ? 'Restoring…'
                                  : 'Restore',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: InlineError(
                      message: friendlyApiMessage(
                        error,
                        fallback: 'Trash could not be loaded.',
                      ),
                      requestId: error.requestId,
                      onRetry: () => _load(reset: _page == 0),
                    ),
                  )
                else if (_documents.isEmpty)
                  const EmptyState(
                    title: 'Trash is empty',
                    message: 'Deleted documents will appear here while they can be recovered.',
                    icon: Icons.delete_outline,
                  )
                else if (_hasMore)
                  TextButton(
                    onPressed: _restoringId == null
                        ? () => _load(reset: false)
                        : null,
                    child: const Text('Load more'),
                  ),
              ],
            ),
          ),
  );
}
