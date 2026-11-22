import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_companion/app/display_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('display-environment-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('loads and merges the initial native layout exactly once', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'currentLayout');
      return _snapshot(
        edge: 'trailing',
        regions: [
          _region('division', const Rect.fromLTWH(390, 0, 12, 844)),
          _region('occlusion', const Rect.fromLTWH(700, 0, 80, 44)),
        ],
      );
    });
    const existingFold = DisplayFeature(
      bounds: Rect.fromLTWH(390, 0, 12, 844),
      type: DisplayFeatureType.fold,
      state: DisplayFeatureState.postureHalfOpened,
    );
    const existingHinge = DisplayFeature(
      bounds: Rect.fromLTWH(200, 0, 8, 844),
      type: DisplayFeatureType.hinge,
      state: DisplayFeatureState.postureFlat,
    );
    DisplayEnvironment? environment;
    List<DisplayFeature>? features;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(780, 844),
          displayFeatures: [existingFold, existingHinge],
        ),
        child: DisplayEnvironmentScope(
          channel: channel,
          child: Builder(
            builder: (context) {
              environment = DisplayEnvironmentScope.of(context);
              features = MediaQuery.displayFeaturesOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(environment?.verticalBarEdge, SuchiVerticalBarEdge.trailing);
    expect(environment?.divisions, [const Rect.fromLTWH(390, 0, 12, 844)]);
    expect(environment?.occlusions, [const Rect.fromLTWH(700, 0, 80, 44)]);
    expect(features, hasLength(3));
    expect(features, contains(existingFold));
    expect(features, contains(existingHinge));
    expect(
      features,
      contains(
        const DisplayFeature(
          bounds: Rect.fromLTWH(700, 0, 80, 44),
          type: DisplayFeatureType.cutout,
          state: DisplayFeatureState.unknown,
        ),
      ),
    );
  });

  testWidgets('channel owner survives replacement below the app root', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (_) async => _snapshot());
    var firstChild = true;
    late StateSetter replaceChild;
    DisplayEnvironment? environment;

    await tester.pumpWidget(
      DisplayEnvironmentScope(
        channel: channel,
        child: StatefulBuilder(
          builder: (context, setState) {
            replaceChild = setState;
            final content = Builder(
              builder: (context) {
                environment = DisplayEnvironmentScope.of(context);
                return const SizedBox();
              },
            );
            return firstChild
                ? MediaQuery(
                    data: const MediaQueryData(size: Size(390, 844)),
                    child: DisplayEnvironmentMediaQuery(child: content),
                  )
                : Directionality(
                    textDirection: TextDirection.ltr,
                    child: MediaQuery(
                      data: const MediaQueryData(size: Size(780, 844)),
                      child: DisplayEnvironmentMediaQuery(child: content),
                    ),
                  );
          },
        ),
      ),
    );
    await tester.pump();
    replaceChild(() => firstChild = false);
    await tester.pump();
    await _sendLayout(messenger, channel, _snapshot(edge: 'trailing'));
    await tester.pump();

    expect(environment?.verticalBarEdge, SuchiVerticalBarEdge.trailing);
  });

  testWidgets('layoutChanged wins over a late initial response', (
    tester,
  ) async {
    final initial = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => initial.future);
    DisplayEnvironment? environment;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(780, 844)),
        child: DisplayEnvironmentScope(
          channel: channel,
          child: Builder(
            builder: (context) {
              environment = DisplayEnvironmentScope.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await _sendLayout(
      messenger,
      channel,
      _snapshot(
        edge: 'leading',
        regions: [_region('division', const Rect.fromLTWH(390, 0, 12, 844))],
      ),
    );
    await tester.pump();
    initial.complete(_snapshot(edge: 'trailing'));
    await tester.pump();

    expect(environment?.verticalBarEdge, SuchiVerticalBarEdge.leading);
    expect(environment?.divisions, isNotEmpty);
  });

  testWidgets('missing plugin and disposal fail closed', (tester) async {
    DisplayEnvironment? environment;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: DisplayEnvironmentScope(
          channel: channel,
          child: Builder(
            builder: (context) {
              environment = DisplayEnvironmentScope.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(environment, DisplayEnvironment.empty);
    await tester.pumpWidget(const SizedBox());
    await _sendLayout(messenger, channel, _snapshot(edge: 'leading'));
    expect(tester.takeException(), isNull);
  });

  test('rejects malformed and nonfinite snapshots', () {
    for (final message in <Object?>[
      null,
      <String, Object?>{},
      _snapshot(
        regions: [_region('division', const Rect.fromLTWH(0, 0, 0, 10))],
      ),
      {
        'verticalBarEdge': 'leading',
        'regions': [
          {
            'kind': 'division',
            'x': double.nan,
            'y': 0,
            'width': 10,
            'height': 10,
          },
        ],
      },
      _snapshot(edge: 'sideways'),
      _snapshot(
        regions: [_region('unknown', const Rect.fromLTWH(0, 0, 10, 10))],
      ),
    ]) {
      expect(DisplayEnvironment.fromMessage(message), DisplayEnvironment.empty);
    }
  });
}

Map<String, Object?> _snapshot({
  String edge = 'unspecified',
  List<Map<String, Object?>> regions = const [],
}) => {'verticalBarEdge': edge, 'regions': regions};

Map<String, Object?> _region(String kind, Rect rect) => {
  'kind': kind,
  'x': rect.left,
  'y': rect.top,
  'width': rect.width,
  'height': rect.height,
};

Future<void> _sendLayout(
  TestDefaultBinaryMessenger messenger,
  MethodChannel channel,
  Object? arguments,
) async {
  final completer = Completer<void>();
  await messenger.handlePlatformMessage(
    channel.name,
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('layoutChanged', arguments),
    ),
    (_) => completer.complete(),
  );
  await completer.future;
}
