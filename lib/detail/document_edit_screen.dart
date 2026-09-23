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
  late final _client = widget.client;
  late String _sensitivity = widget.document.sensitivity;
  bool _saving = false;
  String? _error;

  bool get _sameAccount =>
      widget.session.state == SessionState.signedIn &&
      identical(widget.session.client, _client);

  bool get _changed =>
      _title.text.trim() != widget.document.title ||
      _sensitivity != widget.document.sensitivity ||
      !listEquals(
        _languageCodes(_languages.text),
        _languageCodes(widget.document.languages),
      );

  @override
  void dispose() {
    _title.dispose();
    _languages.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_sameAccount || !_changed) return;
    if (!_form.currentState!.validate()) return;
    final title = _title.text.trim();
    final languages = _languageCodes(_languages.text);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _client.patchDocument(
        widget.document.id,
        title: title != widget.document.title ? title : null,
        sensitivity: _sensitivity != widget.document.sensitivity
            ? _sensitivity
            : null,
        languages:
            !listEquals(languages, _languageCodes(widget.document.languages))
            ? languages
            : null,
      );
      if (!mounted || !_sameAccount) return;
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (!mounted || !_sameAccount) return;
      if (error.expiresSession) widget.session.expire(error);
      setState(() {
        _error = friendlyApiMessage(error, fallback: error.message);
      });
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
                DropdownButtonFormField<String>(
                  initialValue: _sensitivity,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sensitivity'),
                  items: [
                    for (final entry in const {
                      '': 'Not set',
                      'public': 'Public',
                      'internal': 'Internal',
                      'confidential': 'Confidential',
                      'restricted': 'Restricted',
                    }.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _sensitivity = value ?? ''),
                ),
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
                  onPressed: _saving || !_changed ? null : _save,
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
