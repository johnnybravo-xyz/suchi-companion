import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../auth/session_controller.dart';
import '../widgets/suchi_widgets.dart';

class DocumentEditScreen extends StatefulWidget {
  const DocumentEditScreen({
    required this.document,
    required this.client,
    required this.session,
    super.key,
  });

  final DocumentDetail document;
  final SuchiClient client;
  final SessionController session;

  @override
  State<DocumentEditScreen> createState() => _DocumentEditScreenState();
}

class _DocumentEditScreenState extends State<DocumentEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.document.title);
  late final _languages = TextEditingController(
    text: widget.document.languages,
  );
  final _tagSearch = TextEditingController();
  late final _client = widget.client;
  late String _savedTitle = widget.document.title;
  late List<String> _savedLanguages = _languageCodes(widget.document.languages);
  late Set<String> _serverTags = widget.document.tags.toSet();
  late final Set<String> _selectedTags = widget.document.tags.toSet();
  List<TagView> _tags = const [];
  bool _loadingTags = true;
  bool _saving = false;
  bool _needsReconcile = false;
  String? _catalogError;
  String? _error;

  bool get _sameAccount =>
      widget.session.state == SessionState.signedIn &&
      identical(widget.session.client, _client);

  bool get _tagsChanged => !setEquals(_selectedTags, _serverTags);

  bool get _changed =>
      _title.text.trim() != _savedTitle ||
      _tagsChanged ||
      !listEquals(_languageCodes(_languages.text), _savedLanguages);

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  @override
  void dispose() {
    _title.dispose();
    _languages.dispose();
    _tagSearch.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    setState(() {
      _loadingTags = true;
      _catalogError = null;
    });
    try {
      final tags = <TagView>[];
      final ids = <int>{};
      final slugs = <String>{};
      var page = 1;
      int? count;
      while (true) {
        final result = await _client.listTags(page: page);
        if (!mounted || !_sameAccount) return;
        count ??= result.count;
        if (count != result.count ||
            result.results.any(
              (tag) => !ids.add(tag.id) || !slugs.add(tag.slug),
            )) {
          throw const ApiException(
            kind: ApiFailureKind.malformedResponse,
            message: 'Suchi returned an inconsistent tag catalog.',
          );
        }
        tags.addAll(result.results);
        if (tags.length == count) break;
        if (tags.length > count || result.results.isEmpty) {
          throw const ApiException(
            kind: ApiFailureKind.malformedResponse,
            message: 'Suchi returned an incomplete tag catalog.',
          );
        }
        page++;
      }
      tags.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted || !_sameAccount) return;
      setState(() {
        _tags = tags;
        _loadingTags = false;
      });
    } on ApiException catch (error) {
      if (!mounted || !_sameAccount) return;
      if (error.expiresSession) widget.session.expire(error);
      setState(() {
        _loadingTags = false;
        _catalogError = friendlyApiMessage(error, fallback: error.message);
      });
    }
  }

  Future<void> _reconcile() async {
    final current = await _client.document(widget.document.id);
    if (!mounted || !_sameAccount) return;
    setState(() {
      _savedTitle = current.title;
      _savedLanguages = _languageCodes(current.languages);
      _serverTags = current.tags.toSet();
      _needsReconcile = false;
    });
  }

  Future<void> _save() async {
    if (_saving || !_sameAccount || !_changed) return;
    if (!_form.currentState!.validate()) return;
    if (_tagsChanged && (_loadingTags || _catalogError != null)) return;
    final title = _title.text.trim();
    final languages = _languageCodes(_languages.text);
    setState(() {
      _saving = true;
      _error = null;
    });
    var writeStarted = false;
    try {
      if (_needsReconcile) await _reconcile();
      if (!mounted || !_sameAccount) return;
      final changedTitle = title != _savedTitle;
      final changedLanguages = !listEquals(languages, _savedLanguages);
      if (changedTitle || changedLanguages) {
        writeStarted = true;
        await _client.patchDocument(
          widget.document.id,
          title: changedTitle ? title : null,
          languages: changedLanguages ? languages : null,
        );
        if (!mounted || !_sameAccount) return;
        _savedTitle = title;
        _savedLanguages = languages;
      }
      final bySlug = {for (final tag in _tags) tag.slug: tag};
      for (final slug in _serverTags.difference(_selectedTags).toList()) {
        if (!mounted || !_sameAccount) return;
        final tag = bySlug[slug];
        if (tag == null) {
          throw const ApiException(
            kind: ApiFailureKind.rejected,
            message: 'A selected tag is no longer in the catalog. Reload tags.',
          );
        }
        writeStarted = true;
        await _client.changeDocumentTag(
          widget.document.id,
          tagId: tag.id,
          add: false,
        );
        if (!mounted || !_sameAccount) return;
        _serverTags.remove(slug);
      }
      for (final slug in _selectedTags.difference(_serverTags).toList()) {
        if (!mounted || !_sameAccount) return;
        final tag = bySlug[slug];
        if (tag == null) {
          throw const ApiException(
            kind: ApiFailureKind.rejected,
            message: 'A selected tag is no longer in the catalog. Reload tags.',
          );
        }
        writeStarted = true;
        await _client.changeDocumentTag(
          widget.document.id,
          tagId: tag.id,
          add: true,
        );
        if (!mounted || !_sameAccount) return;
        _serverTags.add(slug);
      }
      if (!mounted || !_sameAccount) return;
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (!mounted || !_sameAccount) return;
      if (error.expiresSession) {
        widget.session.expire(error);
        return;
      }
      var message = friendlyApiMessage(error, fallback: error.message);
      if (writeStarted) {
        _needsReconcile = true;
        try {
          await _reconcile();
        } on ApiException catch (refreshError) {
          if (!mounted || !_sameAccount) return;
          if (refreshError.expiresSession) {
            widget.session.expire(refreshError);
            return;
          }
          message += ' Could not refresh current tags. Retry to reconcile before saving.';
        }
      }
      if (!mounted || !_sameAccount) return;
      setState(() => _error = message);
    } finally {
      if (mounted && _sameAccount) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Edit document', overflow: TextOverflow.ellipsis),
    ),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) {
          if (!_sameAccount) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'The account changed. Reopen the document to edit it.',
              ),
            );
          }
          final bySlug = {for (final tag in _tags) tag.slug: tag};
          final search = _tagSearch.text.trim().toLowerCase();
          final matches = search.isEmpty
              ? <TagView>[]
              : _tags
                    .where(
                      (tag) =>
                          !_selectedTags.contains(tag.slug) &&
                          (tag.name.toLowerCase().contains(search) ||
                              tag.slug.toLowerCase().contains(search)),
                    )
                    .toList();
          return Form(
            key: _form,
            onChanged: () => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextFormField(
                  controller: _title,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'Title'),
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 1,
                  maxLines: 3,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a document title.'
                      : null,
                ),
                const SizedBox(height: 20),
                Text('Tags', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_selectedTags.isEmpty) const Text('No tags assigned.'),
                if (_selectedTags.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final slug in _selectedTags)
                        InputChip(
                          label: Text(bySlug[slug]?.name ?? slug),
                          deleteIcon: const Icon(Icons.close),
                          deleteButtonTooltipMessage:
                              'Remove ${bySlug[slug]?.name ?? slug}',
                          onDeleted:
                              _saving ||
                                  _loadingTags ||
                                  _catalogError != null ||
                                  !bySlug.containsKey(slug)
                              ? null
                              : () =>
                                    setState(() => _selectedTags.remove(slug)),
                        ),
                    ],
                  ),
                if (_loadingTags)
                  const Text('Loading available tags…')
                else if (_catalogError != null) ...[
                  Text(_catalogError!),
                  TextButton(
                    onPressed: _loadTags,
                    child: const Text('Retry tags'),
                  ),
                ] else ...[
                  TextField(
                    controller: _tagSearch,
                    enabled: !_saving,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Find existing tags',
                      hintText: 'Search by name or slug',
                    ),
                  ),
                  if (search.isEmpty)
                    const Text('Type to find existing tags.')
                  else if (matches.isEmpty)
                    const Text('No matching tags.'),
                  for (final tag in matches.take(20))
                    ListTile(
                      dense: true,
                      title: Text(tag.name),
                      subtitle: tag.slug == tag.name ? null : Text(tag.slug),
                      onTap: _saving
                          ? null
                          : () => setState(() => _selectedTags.add(tag.slug)),
                    ),
                  if (matches.length > 20)
                    Text(
                      'Showing 20 of ${matches.length} matches. Refine your search.',
                    ),
                ],
                const SizedBox(height: 20),
                TextFormField(
                  controller: _languages,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Languages',
                    hintText: 'en, de',
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.document.languagesLocked
                      ? 'These languages were set manually.'
                      : 'These languages were detected automatically.',
                ),
                const SizedBox(height: 6),
                const Text(
                  'Use language codes separated by commas. Changes keep your '
                  'choice during processing. Clear this field to allow '
                  'automatic detection again.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed:
                      _saving ||
                          !_changed ||
                          (_tagsChanged &&
                              (_loadingTags || _catalogError != null))
                      ? null
                      : _save,
                  child: Text(_saving ? 'Saving…' : 'Save changes'),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

List<String> _languageCodes(String value) =>
    value
        .split(',')
        .map((code) => code.trim().toLowerCase())
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
