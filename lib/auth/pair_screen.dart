import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../offline/offline_document_store.dart';
import '../theme/suchi_theme.dart';
import '../widgets/suchi_widgets.dart';
import 'session_controller.dart';
import 'pairing_link.dart';

class PairScreen extends StatefulWidget {
  const PairScreen({required this.session, this.offlineDocuments, super.key});

  final SessionController session;
  final OfflineDocumentStore? offlineDocuments;
  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final _server = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _token = TextEditingController();
  final _serverFocus = FocusNode();
  bool _useToken = false;
  bool _readingPairingLink = false;
  String? _pairingError;
  int _pairingGeneration = 0;
  bool _removingOffline = false;

  @override
  void initState() {
    super.initState();
    _server.text = widget.session.origin?.toString() ?? '';
    widget.session.addListener(_sessionChanged);
  }

  @override
  void didUpdateWidget(covariant PairScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_sessionChanged);
      widget.session.addListener(_sessionChanged);
    }
  }

  void _sessionChanged() {
    _pairingGeneration++;
    if (widget.session.state == SessionState.signedIn) {
      _password.clear();
      _token.clear();
      _email.clear();
    }
  }

  @override
  void dispose() {
    _pairingGeneration++;
    widget.session.removeListener(_sessionChanged);
    _server.dispose();
    _email.dispose();
    _password.dispose();
    _token.dispose();
    _serverFocus.dispose();
    super.dispose();
  }

  Future<void> _verifyServer() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final verified = await widget.session.verifyServerAddress(_server.text);
    if (!mounted) return;
    if (verified) {
      _server.text = widget.session.preparedOrigin.toString();
      setState(() {});
    } else {
      _serverFocus.requestFocus();
    }
  }

  Future<void> _pair() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_useToken) {
      await widget.session.pairWithToken(
        serverAddress: _server.text,
        token: _token.text,
      );
    } else {
      await widget.session.pairWithPassword(
        serverAddress: _server.text,
        email: _email.text,
        password: _password.text,
      );
    }
  }

  Future<String> _readDeviceName() async {
    final fallback = Theme.of(context).platform == TargetPlatform.iOS
        ? 'iPhone'
        : 'Android device';
    try {
      final value = await const MethodChannel('page.suchi.companion/pairing')
          .invokeMethod<String>('deviceName')
          .timeout(const Duration(seconds: 2));
      final name = (value ?? '')
          .replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), ' ')
          .trim();
      return name.isEmpty
          ? fallback
          : String.fromCharCodes(name.runes.take(64));
    } on MissingPluginException {
      return fallback;
    } on PlatformException {
      return fallback;
    } on TimeoutException {
      return fallback;
    }
  }

  Future<void> _readPairingLink({required bool scan}) async {
    if (_readingPairingLink) return;
    final session = widget.session;
    final generation = ++_pairingGeneration;
    setState(() {
      _readingPairingLink = true;
      _pairingError = null;
    });
    bool current() =>
        mounted &&
        identical(widget.session, session) &&
        generation == _pairingGeneration;
    try {
      final String? input;
      if (scan) {
        input = await const MethodChannel('page.suchi.companion/pairing')
            .invokeMethod<String>('scan');
      } else {
        var initialText = '';
        try {
          initialText =
              (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
        } on PlatformException {
          // Native paste controls remain available if clipboard reads fail.
        } on MissingPluginException {
          // Text entry remains available on hosts without a clipboard adapter.
        }
        if (!mounted || !current()) return;
        input = await showDialog<String>(
          context: context,
          builder: (_) => _PastePairingDialog(initialText: initialText),
        );
      }
      if (!mounted || !current() || input == null) return;
      final pairing = PairingLink.parse(input);
      final initialDeviceName = await _readDeviceName();
      if (!mounted || !current()) return;
      final deviceName = await showDialog<String>(
        context: context,
        builder: (context) => _ConfirmPairingDialog(
          server: pairing.origin.toString(),
          insecure: pairing.origin.scheme == 'http',
          initialDeviceName: initialDeviceName,
        ),
      );
      if (!current() || deviceName == null) return;
      _server.text = pairing.origin.toString();
      await session.pairWithLink(pairing, deviceName: deviceName);
    } on FormatException catch (error) {
      if (current()) setState(() => _pairingError = error.message);
    } on MissingPluginException {
      if (current()) {
        setState(
          () => _pairingError = 'QR scanning is unavailable. Use Paste pairing link or enter your server below.',
        );
      }
    } on PlatformException {
      if (current()) {
        setState(
          () => _pairingError = 'The camera could not scan a pairing code. Use Paste pairing link or enter your server below.',
        );
      }
    } finally {
      if (mounted) setState(() => _readingPairingLink = false);
    }
  }

  Future<void> _removeOfflineCopies() async {
    final store = widget.offlineDocuments;
    if (store == null || _removingOffline || store.totalCount == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove saved offline copies?'),
        content: const Text(
          'This permanently removes offline copies left by signed-out or expired accounts. Queued uploads are not removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove copies'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removingOffline = true);
    try {
      await store.clearAll();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline copies could not be removed. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _removingOffline = false);
    }
  }

  Widget _offlineCleanup() {
    final store = widget.offlineDocuments;
    if (store == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final count = store.totalCount;
        if (count == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: SuchiCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Protected offline copies'),
                const SizedBox(height: 10),
                Text(
                  '$count ${count == 1 ? 'copy remains' : 'copies remain'} on this device from a signed-out or expired account.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('remove-unpaired-offline'),
                  onPressed: _removingOffline ? null : _removeOfflineCopies,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Remove offline copies'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final session = widget.session;
      final colors = SuchiColors.of(context);
      final authenticating = session.state == SessionState.verifying;
      final busy = authenticating || _readingPairingLink;
      final prepared = session.preparedOrigin;
      return Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(23, 22, 23, 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    MediaQuery.sizeOf(context).height -
                    MediaQuery.paddingOf(context).vertical -
                    50,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const BrandMark(size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Pair with Suchi',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Your documents stay between this phone and your Suchi server.',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: colors.muted),
                  ),
                  if (session.state == SessionState.expired) ...[
                    const SizedBox(height: 18),
                    const InlineError(
                      message: 'Your session expired. Verify your server and pair this device again.',
                    ),
                  ],
                  _offlineCleanup(),
                  const SizedBox(height: 22),
                  SuchiCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SectionLabel('Quick pairing'),
                        const SizedBox(height: 10),
                        const Text(
                          'Generate a pairing code in the Suchi web app Settings.',
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () => _readPairingLink(scan: true),
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan QR code'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => _readPairingLink(scan: false),
                          icon: const Icon(Icons.content_paste),
                          label: const Text('Paste pairing link'),
                        ),
                        if (_pairingError != null) ...[
                          const SizedBox(height: 12),
                          InlineError(message: _pairingError!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SuchiCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SectionLabel('Enter server manually'),
                        const SizedBox(height: 12),
                        TextField(
                          key: const ValueKey('pair-server'),
                          controller: _server,
                          focusNode: _serverFocus,
                          enabled: !busy && prepared == null,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.go,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Server address',
                            hintText: 'https://suchi.example.com',
                            prefixIcon: Icon(Icons.dns_outlined),
                          ),
                          onSubmitted: prepared == null && !busy
                              ? (_) => _verifyServer()
                              : null,
                        ),
                        if (prepared == null) ...[
                          const SizedBox(height: 13),
                          OutlinedButton.icon(
                            key: const ValueKey('verify-server'),
                            onPressed: busy ? null : _verifyServer,
                            icon: authenticating
                                ? SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.accent,
                                    ),
                                  )
                                : const Icon(Icons.verified_user_outlined),
                            label: Text(
                              authenticating
                                  ? 'Verifying server…'
                                  : 'Verify server',
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 18,
                                color: colors.success,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  prepared.scheme == 'http'
                                      ? 'Verified development connection · traffic is not encrypted'
                                      : 'Verified Suchi server',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: prepared.scheme == 'http'
                                            ? colors.warning
                                            : colors.success,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () {
                                        widget.session.clearPreparedServer();
                                        _serverFocus.requestFocus();
                                      },
                                child: const Text('Change'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                value: false,
                                label: Text('Email'),
                                icon: Icon(Icons.person_outline),
                              ),
                              ButtonSegment(
                                value: true,
                                label: Text('API token'),
                                icon: Icon(Icons.key_outlined),
                              ),
                            ],
                            selected: {_useToken},
                            onSelectionChanged: busy
                                ? null
                                : (selection) => setState(() {
                                    _useToken = selection.single;
                                    _password.clear();
                                    _token.clear();
                                  }),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Email pairing uses a local Suchi password. OIDC accounts pair with a scoped API token created in the web app.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 13),
                          if (_useToken)
                            TextField(
                              key: const ValueKey('pair-token'),
                              controller: _token,
                              enabled: !busy,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              keyboardType: TextInputType.visiblePassword,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: 'Suchi API token',
                                prefixIcon: Icon(Icons.key_outlined),
                              ),
                              onSubmitted: busy ? null : (_) => _pair(),
                            )
                          else ...[
                            TextField(
                              key: const ValueKey('pair-email'),
                              controller: _email,
                              enabled: !busy,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Email address',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              key: const ValueKey('pair-password'),
                              controller: _password,
                              enabled: !busy,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              onSubmitted: busy ? null : (_) => _pair(),
                            ),
                          ],
                          const SizedBox(height: 13),
                          FilledButton(
                            key: const ValueKey('pair-submit'),
                            onPressed: busy ? null : _pair,
                            child: Text(
                              authenticating ? 'Pairing…' : 'Pair this device',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (session.errorMessage != null) ...[
                    const SizedBox(height: 14),
                    InlineError(
                      message: session.errorMessage!,
                      requestId: session.requestId,
                      onRetry: session.canRetryStoredCredentials && !busy
                          ? session.retryStoredCredentials
                          : null,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline, size: 18, color: colors.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Suchi Companion verifies product identity and API compatibility before credentials leave this device. Passwords are never stored.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ConfirmPairingDialog extends StatefulWidget {
  const _ConfirmPairingDialog({
    required this.server,
    required this.insecure,
    required this.initialDeviceName,
  });

  final String server;
  final bool insecure;
  final String initialDeviceName;

  @override
  State<_ConfirmPairingDialog> createState() => _ConfirmPairingDialogState();
}

class _ConfirmPairingDialogState extends State<_ConfirmPairingDialog> {
  final _form = GlobalKey<FormState>();
  late final _deviceName = TextEditingController(
    text: widget.initialDeviceName,
  );

  @override
  void dispose() {
    _deviceName.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _deviceName.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Pair with this server?'),
    scrollable: true,
    content: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(widget.server),
          const SizedBox(height: 14),
          const Text(
            'Continue only if this is your Suchi server. The pairing code and device name will be sent to this address.',
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const ValueKey('pair-device-name'),
            controller: _deviceName,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            maxLength: 64,
            decoration: const InputDecoration(labelText: 'Device name'),
            validator: (value) {
              final name = (value ?? '').trim();
              if (name.isEmpty) return 'Enter a device name.';
              if (name.runes.length > 64) return 'Use 64 characters or fewer.';
              if (RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(name)) {
                return 'Use a name without control characters.';
              }
              return null;
            },
            onFieldSubmitted: (_) => _confirm(),
          ),
          const SizedBox(height: 6),
          const Text('Shown under Mobile app in the web settings.'),
          if (widget.insecure) ...[
            const SizedBox(height: 10),
            const Text('This local HTTP connection is not encrypted.'),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _confirm, child: const Text('Pair this device')),
    ],
  );
}

class _PastePairingDialog extends StatefulWidget {
  const _PastePairingDialog({required this.initialText});

  final String initialText;

  @override
  State<_PastePairingDialog> createState() => _PastePairingDialogState();
}

class _PastePairingDialogState extends State<_PastePairingDialog> {
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Paste pairing link'),
    scrollable: true,
    content: TextField(
      controller: _controller,
      autofocus: true,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      decoration: const InputDecoration(labelText: 'Pairing link'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Review server'),
      ),
    ],
  );
}
