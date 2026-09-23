import 'dart:async';

import 'package:flutter/material.dart';

class LifecyclePrivacyShield extends StatefulWidget {
  const LifecyclePrivacyShield({
    required this.child,
    required this.onConceal,
    required this.onResume,
    super.key,
  });

  final Widget child;
  final VoidCallback onConceal;
  final Future<void> Function() onResume;

  @override
  State<LifecyclePrivacyShield> createState() => _LifecyclePrivacyShieldState();
}

class _LifecyclePrivacyShieldState extends State<LifecyclePrivacyShield>
    with WidgetsBindingObserver {
  late bool _concealed;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _concealed = state != null && state != AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_concealed && mounted) setState(() => _concealed = false);
      unawaited(widget.onResume());
      return;
    }
    if (!_concealed) {
      widget.onConceal();
      if (mounted) setState(() => _concealed = true);
    }
  }

  @override
  void didHaveMemoryPressure() => widget.onConceal();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    alignment: Alignment.topLeft,
    children: [
      widget.child,
      if (_concealed)
        const Positioned.fill(
          child: ExcludeSemantics(
            child: ColoredBox(
              key: ValueKey('lifecycle-privacy-shield'),
              color: Color(0xFF0F1519),
            ),
          ),
        ),
    ],
  );
}
