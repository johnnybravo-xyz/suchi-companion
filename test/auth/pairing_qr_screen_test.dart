import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';
import 'package:suchi_mobile/auth/pair_screen.dart';
import 'package:suchi_mobile/auth/session_controller.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _code =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _link =
    'suchi://pair?v=1&server=https%3A%2F%2Fsuchi.example.com&code=$_code';
const _channel = MethodChannel('app.suchi.page/pairing');

void main() {
  testWidgets(
    'a scanned QR requires server confirmation before any network request',
    (tester) async {
      final requests = <http.Request>[];
      final session = await _showPairing(tester, requests: requests);
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      expect(find.text('Pair with this server?'), findsOneWidget);
      expect(
        find.widgetWithText(SelectableText, 'https://suchi.example.com'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
      expect(find.text('Ritesh’s iPhone'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('pair-device-name')),
        'My work iPhone',
      );
      await tester.tap(find.text('Pair this device'));
      await tester.pumpAndSettle();
      expect(session.state, SessionState.signedIn);
      expect(jsonDecode(requests[1].body), {
        'code': _code,
        'device_name': 'My work iPhone',
      });
      expect(requests.map((request) => request.url.path), [
        '/api/handshake',
        '/api/mobile/pairing/exchange',
        '/api/whoami',
      ]);
    },
  );

  testWidgets('uses the native device name without requiring an edit', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await _showPairing(
      tester,
      requests: requests,
      deviceName: () async => '  Family Pixel  ',
    );
    await tester.tap(find.text('Scan QR code'));
    await tester.pumpAndSettle();
    expect(find.text('Family Pixel'), findsOneWidget);
    expect(requests, isEmpty);
    await tester.tap(find.text('Pair this device'));
    await tester.pumpAndSettle();
    expect(jsonDecode(requests[1].body), {
      'code': _code,
      'device_name': 'Family Pixel',
    });
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('unavailable device name stays editable on $platform', (
      tester,
    ) async {
      final requests = <http.Request>[];
      await _showPairing(
        tester,
        requests: requests,
        platform: platform,
        deviceName: () async =>
            throw PlatformException(code: 'device_name_unavailable'),
      );
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      expect(
        find.text(platform == TargetPlatform.iOS ? 'iPhone' : 'Android device'),
        findsOneWidget,
      );
      final name = find.byKey(const ValueKey('pair-device-name'));
      await tester.enterText(name, '   ');
      await tester.tap(find.text('Pair this device'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a device name.'), findsOneWidget);
      expect(requests, isEmpty);
      await tester.enterText(name, '家族の電話');
      await tester.tap(find.text('Pair this device'));
      await tester.pumpAndSettle();
      expect(jsonDecode(requests[1].body), {
        'code': _code,
        'device_name': '家族の電話',
      });
    });
  }

  testWidgets(
    'a device name returned after an account change cannot start pairing',
    (tester) async {
      final requests = <http.Request>[];
      final pending = Completer<String?>();
      final session = await _showPairing(
        tester,
        requests: requests,
        deviceName: () => pending.future,
      );
      await tester.tap(find.text('Scan QR code'));
      await tester.pump();
      await session.signOut();
      pending.complete('Previous account phone');
      await tester.pumpAndSettle();
      expect(find.text('Pair with this server?'), findsNothing);
      expect(requests, isEmpty);
    },
  );

  testWidgets(
    'device-name timeout keeps pairing usable and ignores late results',
    (tester) async {
      final requests = <http.Request>[];
      final pending = Completer<String?>();
      await _showPairing(
        tester,
        requests: requests,
        deviceName: () => pending.future,
      );
      await tester.tap(find.text('Scan QR code'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Pair with this server?'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('pair-device-name')),
        'My tablet',
      );
      pending.complete('Late native name');
      await tester.pumpAndSettle();
      expect(find.text('My tablet'), findsOneWidget);
      await tester.tap(find.text('Pair this device'));
      await tester.pumpAndSettle();
      expect(jsonDecode(requests[1].body), {
        'code': _code,
        'device_name': 'My tablet',
      });
    },
  );

  testWidgets('invalid scans and scanner cancellation make no request', (
    tester,
  ) async {
    final requests = <http.Request>[];
    var scans = 0;
    await _showPairing(
      tester,
      requests: requests,
      scan: () async => scans++ == 0 ? null : 'https://example.com/unrelated',
    );
    await tester.tap(find.text('Scan QR code'));
    await tester.pumpAndSettle();
    expect(find.text('Pair with this server?'), findsNothing);
    expect(find.textContaining('valid Suchi pairing link'), findsNothing);
    await tester.tap(find.text('Scan QR code'));
    await tester.pumpAndSettle();
    expect(scans, 2);
    expect(find.textContaining('valid Suchi pairing link'), findsOneWidget);
    expect(requests, isEmpty);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'camera refusal keeps paste and manual pairing usable at 200% on $platform',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final requests = <http.Request>[];
        final session = await _showPairing(
          tester,
          requests: requests,
          platform: platform,
          textScale: 2,
          scan: () async => throw PlatformException(code: 'camera_denied'),
        );
        await tester.ensureVisible(find.text('Scan QR code'));
        await tester.tap(find.text('Scan QR code'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Use Paste pairing link'), findsOneWidget);
        expect(find.byKey(const ValueKey('pair-server')), findsOneWidget);
        await tester.ensureVisible(find.text('Paste pairing link'));
        await tester.tap(find.text('Paste pairing link'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, 'Pairing link'), findsOneWidget);
        await tester.tap(find.text('Review server'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(SelectableText, 'https://suchi.example.com'),
          findsOneWidget,
        );
        expect(requests, isEmpty);
        await tester.tap(find.text('Pair this device'));
        await tester.pumpAndSettle();
        expect(session.state, SessionState.signedIn);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('clipboard refusal still permits entering a pairing link', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await _showPairing(tester, requests: requests);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          throw PlatformException(code: 'clipboard_denied');
        }
        return null;
      },
    );
    await tester.tap(find.text('Paste pairing link'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Pairing link'),
      _link,
    );
    await tester.tap(find.text('Review server'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(SelectableText, 'https://suchi.example.com'),
      findsOneWidget,
    );
    expect(requests, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
  });

  testWidgets('a scan returned after a session transition is ignored', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final pending = Completer<String?>();
    final session = await _showPairing(
      tester,
      requests: requests,
      scan: () => pending.future,
    );
    await tester.tap(find.text('Scan QR code'));
    await tester.pump();
    await session.signOut();
    pending.complete(_link);
    await tester.pumpAndSettle();
    expect(find.text('Pair with this server?'), findsNothing);
    expect(requests, isEmpty);
  });
}

Future<SessionController> _showPairing(
  WidgetTester tester, {
  required List<http.Request> requests,
  Future<String?> Function()? scan,
  Future<String?> Function()? deviceName,
  TargetPlatform platform = TargetPlatform.android,
  double textScale = 1,
}) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
    call,
  ) async {
    if (call.method == 'deviceName') {
      return deviceName == null ? 'Ritesh’s iPhone' : await deviceName();
    }
    expect(call.method, 'scan');
    return scan == null ? _link : await scan();
  });
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.getData') return {'text': _link};
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
  final transport = MockClient((request) async {
    requests.add(request);
    if (request.url.path == '/api/mobile/pairing/exchange') {
      return http.Response(
        jsonEncode({'token': _token}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    final fixture = request.url.path == '/api/handshake'
        ? 'handshake.json'
        : 'whoami.json';
    return http.Response(
      File('test/fixtures/api/v1/$fixture').readAsStringSync(),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  final session = SessionController(
    vault: _MemoryVault(),
    clientFactory: (origin, token) =>
        SuchiClient(origin: origin, token: token, httpClient: transport),
  );
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: SuchiTheme.light.copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: PairScreen(session: session),
    ),
  );
  return session;
}

final class _MemoryVault implements CredentialVault {
  @override
  Future<void> clear() async {}
  @override
  Future<StoredCredentials?> read() async => null;
  @override
  Future<void> save(StoredCredentials credentials) async {}
}
