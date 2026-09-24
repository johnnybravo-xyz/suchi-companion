import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _contentSecurityPolicy =
    "default-src 'none'; img-src data:; style-src 'unsafe-inline'; "
    "script-src 'none'; connect-src 'none'; font-src 'none'; "
    "media-src 'none'; object-src 'none'; frame-src 'none'; "
    "child-src 'none'; worker-src 'none'; manifest-src 'none'; "
    "base-uri 'none'; form-action 'none'; navigate-to 'none'; sandbox";
const _cspMeta =
    '<meta http-equiv="Content-Security-Policy" '
    'content="$_contentSecurityPolicy">';
const _emptyPage = '<!doctype html><html><head></head><body></body></html>';

String hardenEmailPreviewHtml(String html) {
  final opening = RegExp(
    r'<head(?:\s[^>]*)?>',
    caseSensitive: false,
  ).firstMatch(html);
  if (opening == null) {
    throw const FormatException('Email preview has no HTML head.');
  }
  final prefix = html.substring(0, opening.start);
  if (!RegExp(
    r'^(?:\s|<!doctype[^>]*>|<\?xml[\s\S]*?\?>|<!--[\s\S]*?-->|<html(?:\s[^>]*)?>)*$',
    caseSensitive: false,
  ).hasMatch(prefix)) {
    throw const FormatException('Email preview has content before its head.');
  }
  final closing = RegExp(
    r'</head\s*>',
    caseSensitive: false,
  ).firstMatch(html.substring(opening.end));
  if (closing == null) {
    throw const FormatException('Email preview has no complete HTML head.');
  }
  final body = RegExp(
    r'<body(?:\s[^>]*)?>',
    caseSensitive: false,
  ).firstMatch(html);
  if (body != null && body.start < opening.end + closing.start) {
    throw const FormatException('Email preview has an invalid HTML head.');
  }
  return html.replaceRange(opening.end, opening.end, _cspMeta);
}

final class SandboxedEmailPreview extends StatefulWidget {
  const SandboxedEmailPreview({
    required this.html,
    required this.onOpen,
    super.key,
  });

  final String html;
  final VoidCallback onOpen;

  @override
  State<SandboxedEmailPreview> createState() => _SandboxedEmailPreviewState();
}

final class _SandboxedEmailPreviewState extends State<SandboxedEmailPreview> {
  late final WebViewController _controller;
  bool _ready = false;
  bool _failed = false;
  int _generation = 0;
  late Future<void> _operation;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController(
      onPermissionRequest: (request) => unawaited(request.deny()),
    );
    _operation = _load(widget.html);
    unawaited(_operation);
  }

  @override
  void didUpdateWidget(SandboxedEmailPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) {
      _operation = _operation.then((_) => _load(widget.html));
      unawaited(_operation);
    }
  }

  Future<void> _load(String html) async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _ready = false;
        _failed = false;
      });
    }
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.disabled);
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (_) => NavigationDecision.prevent,
        ),
      );
      await _controller.loadHtmlString(_emptyPage);
      await _controller.clearCache();
      await _controller.clearLocalStorage();
      if (!mounted || generation != _generation) return;
      await _controller.loadHtmlString(html);
      if (!mounted || generation != _generation) return;
      setState(() => _ready = true);
    } on PlatformException {
      if (!mounted || generation != _generation) return;
      await _purge();
      if (mounted && generation == _generation) {
        setState(() => _failed = true);
      }
    }
  }

  Future<void> _purge() async {
    try {
      await _controller.loadHtmlString(_emptyPage);
      await _controller.clearCache();
      await _controller.clearLocalStorage();
    } on PlatformException {
      // The platform view may already be gone. No preview data is retained here.
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_operation.whenComplete(_purge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const SizedBox(
        height: 265,
        child: Center(child: Text('Email preview could not be displayed.')),
      );
    }
    if (!_ready) {
      return const SizedBox(
        height: 265,
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              semanticsLabel: 'Loading email preview',
            ),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: 'Open email document',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        child: SizedBox(
          height: 265,
          child: IgnorePointer(child: WebViewWidget(controller: _controller)),
        ),
      ),
    );
  }
}
