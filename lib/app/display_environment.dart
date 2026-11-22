import 'dart:async';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const layoutChannelName = 'page.suchi.companion/layout';

enum SuchiVerticalBarEdge { leading, trailing, unspecified }

@immutable
final class DisplayEnvironment {
  const DisplayEnvironment({
    this.divisions = const <Rect>[],
    this.occlusions = const <Rect>[],
    this.verticalBarEdge = SuchiVerticalBarEdge.unspecified,
  });

  static const empty = DisplayEnvironment();

  final List<Rect> divisions;
  final List<Rect> occlusions;
  final SuchiVerticalBarEdge verticalBarEdge;

  static DisplayEnvironment fromMessage(Object? message) {
    try {
      if (message is! Map) throw const FormatException('Expected layout map');
      final rawRegions = message['regions'];
      final rawEdge = message['verticalBarEdge'];
      if (rawRegions is! List || rawEdge is! String) {
        throw const FormatException('Malformed layout snapshot');
      }
      final divisions = <Rect>[];
      final occlusions = <Rect>[];
      for (final rawRegion in rawRegions) {
        if (rawRegion is! Map) {
          throw const FormatException('Malformed reserved region');
        }
        final kind = rawRegion['kind'];
        final x = _finiteDouble(rawRegion['x']);
        final y = _finiteDouble(rawRegion['y']);
        final width = _finiteDouble(rawRegion['width']);
        final height = _finiteDouble(rawRegion['height']);
        if (width <= 0 || height <= 0) {
          throw const FormatException('Empty reserved region');
        }
        final rect = Rect.fromLTWH(x, y, width, height);
        switch (kind) {
          case 'division':
            divisions.add(rect);
          case 'occlusion':
            occlusions.add(rect);
          default:
            throw const FormatException('Unknown reserved region kind');
        }
      }
      final edge = switch (rawEdge) {
        'leading' => SuchiVerticalBarEdge.leading,
        'trailing' => SuchiVerticalBarEdge.trailing,
        'unspecified' => SuchiVerticalBarEdge.unspecified,
        _ => throw const FormatException('Unknown vertical bar edge'),
      };
      return DisplayEnvironment(
        divisions: List.unmodifiable(divisions),
        occlusions: List.unmodifiable(occlusions),
        verticalBarEdge: edge,
      );
    } on FormatException {
      return empty;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DisplayEnvironment &&
      listEquals(divisions, other.divisions) &&
      listEquals(occlusions, other.occlusions) &&
      verticalBarEdge == other.verticalBarEdge;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(divisions),
    Object.hashAll(occlusions),
    verticalBarEdge,
  );
}

double _finiteDouble(Object? value) {
  if (value is! num) throw const FormatException('Expected number');
  final result = value.toDouble();
  if (!result.isFinite) throw const FormatException('Expected finite number');
  return result;
}

List<DisplayFeature> mergeDisplayFeatures(
  List<DisplayFeature> engineFeatures,
  DisplayEnvironment environment,
) {
  final merged = <DisplayFeature>[...engineFeatures];
  for (final bounds in environment.divisions) {
    _addDisplayFeature(
      merged,
      DisplayFeature(
        bounds: bounds,
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    );
  }
  for (final bounds in environment.occlusions) {
    _addDisplayFeature(
      merged,
      DisplayFeature(
        bounds: bounds,
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      ),
    );
  }
  return List.unmodifiable(merged);
}

void _addDisplayFeature(
  List<DisplayFeature> features,
  DisplayFeature candidate,
) {
  if (features.any(
    (feature) =>
        feature.bounds == candidate.bounds &&
        feature.type == candidate.type &&
        feature.state == candidate.state,
  )) {
    return;
  }
  features.add(candidate);
}

final class DisplayEnvironmentScope extends StatefulWidget {
  const DisplayEnvironmentScope({
    required this.child,
    this.channel = const MethodChannel(layoutChannelName),
    super.key,
  });

  final Widget child;
  final MethodChannel channel;

  static DisplayEnvironment of(BuildContext context) {
    return maybeOf(context) ?? DisplayEnvironment.empty;
  }

  static DisplayEnvironment? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_DisplayEnvironmentInherited>()
        ?.environment;
  }

  @override
  State<DisplayEnvironmentScope> createState() =>
      _DisplayEnvironmentScopeState();
}

final class _DisplayEnvironmentScopeState
    extends State<DisplayEnvironmentScope> {
  DisplayEnvironment _environment = DisplayEnvironment.empty;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _startChannel(widget.channel);
  }

  @override
  void didUpdateWidget(DisplayEnvironmentScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel == widget.channel) return;
    oldWidget.channel.setMethodCallHandler(null);
    _environment = DisplayEnvironment.empty;
    _revision++;
    _startChannel(widget.channel);
  }

  void _startChannel(MethodChannel channel) {
    channel.setMethodCallHandler(_handleMethodCall);
    unawaited(_loadCurrent(channel));
  }

  Future<void> _loadCurrent(MethodChannel channel) async {
    final requestRevision = _revision;
    try {
      final message = await channel.invokeMethod<Object?>('currentLayout');
      if (!mounted ||
          channel != widget.channel ||
          requestRevision != _revision) {
        return;
      }
      _apply(DisplayEnvironment.fromMessage(message));
    } on MissingPluginException {
      if (mounted &&
          channel == widget.channel &&
          requestRevision == _revision) {
        _apply(DisplayEnvironment.empty);
      }
    } on PlatformException {
      if (mounted &&
          channel == widget.channel &&
          requestRevision == _revision) {
        _apply(DisplayEnvironment.empty);
      }
    }
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method != 'layoutChanged') return null;
    _revision++;
    _apply(DisplayEnvironment.fromMessage(call.arguments));
    return null;
  }

  void _apply(DisplayEnvironment environment) {
    if (!mounted || environment == _environment) return;
    setState(() => _environment = environment);
  }

  @override
  void dispose() {
    _revision++;
    widget.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ambient = MediaQuery.maybeOf(context);
    final inherited = _DisplayEnvironmentInherited(
      environment: _environment,
      child: widget.child,
    );
    if (ambient == null) return inherited;
    return MediaQuery(
      data: ambient.copyWith(
        displayFeatures: mergeDisplayFeatures(
          ambient.displayFeatures,
          _environment,
        ),
      ),
      child: inherited,
    );
  }
}

final class DisplayEnvironmentMediaQuery extends StatelessWidget {
  const DisplayEnvironmentMediaQuery({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ambient = MediaQuery.maybeOf(context);
    if (ambient == null) return child;
    return MediaQuery(
      data: ambient.copyWith(
        displayFeatures: mergeDisplayFeatures(
          ambient.displayFeatures,
          DisplayEnvironmentScope.of(context),
        ),
      ),
      child: child,
    );
  }
}

final class _DisplayEnvironmentInherited extends InheritedWidget {
  const _DisplayEnvironmentInherited({
    required this.environment,
    required super.child,
  });

  final DisplayEnvironment environment;

  @override
  bool updateShouldNotify(_DisplayEnvironmentInherited oldWidget) {
    return environment != oldWidget.environment;
  }
}
