import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_error.dart';
import '../api/suchi_client.dart';
import '../auth/session_controller.dart';
import '../widgets/suchi_widgets.dart';

class DocumentTextScreen extends StatefulWidget {
  const DocumentTextScreen({
    required this.documentId,
    required this.title,
    required this.sensitivity,
    required this.client,
    required this.session,
    super.key,
  });

  final int documentId;
  final String title;
  final String sensitivity;
  final SuchiClient client;
  final SessionController session;

  @override
  State<DocumentTextScreen> createState() => _DocumentTextScreenState();
}

class _DocumentTextScreenState extends State<DocumentTextScreen>
    with WidgetsBindingObserver {
  static const _pageSize = 12000;
  late final _client = widget.client;
  late String _sensitivity = widget.sensitivity;
  String? _text;
  ApiException? _error;
  bool _loading = false;
  bool _active = true;
  int _generation = 0;
  int _page = 0;

  bool get _sameAccount =>
      widget.session.state == SessionState.signedIn &&
      identical(widget.session.client, _client);

  bool _current(int generation) =>
      mounted && _sameAccount && _active && generation == _generation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_sessionChanged);
    _active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _generation++;
    _text = null;
    widget.session.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      _clear();
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void didHaveMemoryPressure() => _clear();

  void _sessionChanged() {
    if (!_sameAccount) _clear();
  }

  void _clear() {
    _generation++;
    if (!mounted) return;
    setState(() {
      _text = null;
      _error = null;
      _loading = false;
      _page = 0;
    });
  }

  bool _isSensitive(String sensitivity) =>
      sensitivity == 'confidential' || sensitivity == 'restricted';

  Future<bool> _confirm(String sensitivity) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Read sensitive text?'),
          content: Text(
            'This document is $sensitivity. Its extracted text will be shown '
            'on this device until you leave or background the app. '
            'Text you choose to copy can remain in the system clipboard.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reveal text'),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _load() async {
    if (!_sameAccount || !_active || _loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _text = null;
      _page = 0;
    });
    try {
      final confirmedSensitive = _isSensitive(_sensitivity);
      if (confirmedSensitive && !await _confirm(_sensitivity)) return;
      if (!_current(generation)) return;
      final result = await _client.documentText(widget.documentId);
      if (!_current(generation)) return;
      _sensitivity = result.sensitivity;
      // Classification can change between the metadata and explicit text read.
      if (_isSensitive(result.sensitivity) && !confirmedSensitive) {
        if (!await _confirm(result.sensitivity) || !_current(generation)) {
          return;
        }
      }
      setState(() => _text = result.text);
    } on ApiException catch (error) {
      if (!_current(generation)) return;
      if (error.expiresSession) {
        widget.session.expire(error);
        return;
      }
      setState(() => _error = error);
    } finally {
      if (_current(generation)) setState(() => _loading = false);
    }
  }

  int _textOffset(int page) {
    final text = _text!;
    final offset = math.min(page * _pageSize, text.length);
    // Never divide a UTF-16 surrogate pair between reader pages.
    if (offset > 0 &&
        offset < text.length &&
        text.codeUnitAt(offset) >= 0xdc00 &&
        text.codeUnitAt(offset) <= 0xdfff &&
        text.codeUnitAt(offset - 1) >= 0xd800 &&
        text.codeUnitAt(offset - 1) <= 0xdbff) {
      return offset - 1;
    }
    return offset;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Extracted text', overflow: TextOverflow.ellipsis),
    ),
    body: SafeArea(child: _body()),
  );

  Widget _body() {
    if (!_sameAccount) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('The account changed. Reopen the document to read it.'),
      );
    }
    final text = _text;
    final error = _error;
    final pages = text == null ? 0 : (text.length / _pageSize).ceil();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (error != null)
          InlineError(
            message: friendlyApiMessage(
              error,
              fallback: 'Extracted text could not be loaded.',
            ),
            requestId: error.requestId,
            onRetry: _active ? _load : null,
          )
        else if (text == null) ...[
          Text(
            _active
                ? 'Load text when you are ready to read it. Text is cleared when you leave or background the app.'
                : 'Text is hidden while the app is inactive.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _active ? _load : null,
            child: const Text('Load text'),
          ),
        ] else if (text.trim().isEmpty)
          const Text(
            'No extracted text is available yet. Processing may still be running, or this document may not contain readable text.',
          )
        else ...[
          const Text(
            'Extracted text can contain recognition errors. Check the original document for accuracy.',
          ),
          if (pages > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Part ${_page + 1} of $pages'),
                OutlinedButton(
                  onPressed: _page > 0 ? () => setState(() => _page--) : null,
                  child: const Text('Previous'),
                ),
                OutlinedButton(
                  onPressed: _page + 1 < pages
                      ? () => setState(() => _page++)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SelectableText(
            text.substring(_textOffset(_page), _textOffset(_page + 1)),
            key: ValueKey(_page),
          ),
        ],
      ],
    );
  }
}
