import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_companion/api/suchi_client.dart';
import 'package:suchi_companion/auth/credential_vault.dart';
import 'package:suchi_companion/auth/session_controller.dart';
import 'package:suchi_companion/detail/document_text_screen.dart';
import 'package:suchi_companion/theme/suchi_theme.dart';

void main() {
  testWidgets(
    'sensitive text waits for confirmation and cancel never fetches',
    (tester) async {
      var reads = 0;
      await _show(
        tester,
        sensitivity: 'restricted',
        respond: (_) async {
          reads++;
          return _text('private text', sensitivity: 'restricted');
        },
      );
      await tester.pump();
      expect(find.text('Read sensitive text?'), findsOneWidget);
      expect(reads, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(reads, 0);
      await tester.tap(find.text('Load text'));
      await tester.pump();
      await tester.tap(find.text('Reveal text'));
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(
        find.widgetWithText(SelectableText, 'private text'),
        findsOneWidget,
      );
    },
  );

  testWidgets('server reclassification asks for consent before rendering', (
    tester,
  ) async {
    var reads = 0;
    await _show(
      tester,
      respond: (_) async {
        reads++;
        return _text('newly confidential', sensitivity: 'confidential');
      },
    );
    await tester.pump();
    expect(reads, 1);
    expect(find.text('Read sensitive text?'), findsOneWidget);
    expect(
      find.widgetWithText(SelectableText, 'newly confidential'),
      findsNothing,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(SelectableText, 'newly confidential'),
      findsNothing,
    );
    await tester.tap(find.text('Load text'));
    await tester.pump();
    expect(reads, 1);
    await tester.tap(find.text('Reveal text'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(
      find.widgetWithText(SelectableText, 'newly confidential'),
      findsOneWidget,
    );
  });

  for (final status in [403, 503]) {
    testWidgets('$status has a truthful error and retry can show empty text', (
      tester,
    ) async {
      var reads = 0;
      final session = await _show(
        tester,
        respond: (_) async {
          reads++;
          return reads == 1
              ? http.Response(
                  '{}',
                  status,
                  headers: {'content-type': 'application/json'},
                )
              : _text('');
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
      expect(session.state, SessionState.signedIn);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(
        find.textContaining('No extracted text is available yet.'),
        findsOneWidget,
      );
    });
  }

  testWidgets('background clears text, drops late reads and never auto-loads', (
    tester,
  ) async {
    var reads = 0;
    final pending = Completer<http.Response>();
    await _show(
      tester,
      respond: (_) async {
        reads++;
        return reads == 1 ? pending.future : _text('fresh text');
      },
    );
    await tester.pump();
    expect(reads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    pending.complete(_text('late text'));
    await tester.pumpAndSettle();
    expect(find.text('late text'), findsNothing);
    final inactiveLoad = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Load text'),
    );
    expect(inactiveLoad.onPressed, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(reads, 1);
    await tester.tap(find.text('Load text'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SelectableText, 'fresh text'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.text('fresh text'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(reads, 2);
  });

  testWidgets('leaving during a consent dialog cannot fetch on return', (
    tester,
  ) async {
    var reads = 0;
    await _show(
      tester,
      sensitivity: 'restricted',
      respond: (_) async {
        reads++;
        return _text('private text');
      },
    );
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.tap(find.text('Reveal text'));
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(find.text('Load text'), findsOneWidget);
  });

  testWidgets('logout drops a pending result and prevents another read', (
    tester,
  ) async {
    var reads = 0;
    final pending = Completer<http.Response>();
    final session = await _show(
      tester,
      respond: (_) async {
        reads++;
        return pending.future;
      },
    );
    await tester.pump();
    await session.signOut();
    pending.complete(_text('old account text'));
    await tester.pumpAndSettle();
    expect(find.text('old account text'), findsNothing);
    expect(find.text('Load text'), findsNothing);
    expect(find.textContaining('The account changed.'), findsOneWidget);
    expect(reads, 1);
  });

  testWidgets(
    'unauthorized text expires the session without displaying content',
    (tester) async {
      final session = await _show(
        tester,
        respond: (_) async => http.Response(
          '{"message":"Token expired"}',
          401,
          headers: {'content-type': 'application/json'},
        ),
      );
      await tester.pumpAndSettle();
      expect(session.state, SessionState.expired);
      expect(find.byType(SelectableText), findsNothing);
      expect(find.text('Retry'), findsNothing);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform renders selectable text at 200% without interpreting markup',
      (tester) async {
        await _show(
          tester,
          platform: platform,
          scale: 2,
          sensitivity: 'restricted',
          respond: (_) async => _text('<b>Plain text</b>\nदस्तावेज 📄'),
        );
        await tester.pump();
        await tester.ensureVisible(find.text('Reveal text'));
        await tester.tap(find.text('Reveal text'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(SelectableText, '<b>Plain text</b>\nदस्तावेज 📄'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('long text pages preserve a Unicode character at the boundary', (
    tester,
  ) async {
    final firstPage = 'x' * 11999;
    await _show(tester, respond: (_) async => _text('$firstPage📄end'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      firstPage,
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      '📄end',
    );
    expect(find.text('Part 2 of 2'), findsOneWidget);
  });
}

Future<SessionController> _show(
  WidgetTester tester, {
  required Future<http.Response> Function(http.Request) respond,
  String sensitivity = '',
  TargetPlatform platform = TargetPlatform.android,
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final transport = MockClient((request) async {
    if (request.url.path == '/api/handshake' ||
        request.url.path == '/api/whoami') {
      final fixture = request.url.path.split('/').last;
      return http.Response(
        File('test/fixtures/api/v1/$fixture.json').readAsStringSync(),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.url.path == '/api/auth/logout') return http.Response('{}', 200);
    expect(request.url.path, '/api/documents/91');
    expect(request.url.queryParameters, {'include_content': '1'});
    return respond(request);
  });
  final session = SessionController(
    vault: _MemoryVault(),
    clientFactory: (origin, token) =>
        SuchiClient(origin: origin, token: token, httpClient: transport),
  );
  await session.pairWithToken(
    serverAddress: 'https://suchi.example.com',
    token: 'a' * 64,
  );
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: SuchiTheme.light.copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: DocumentTextScreen(
        documentId: 91,
        title: 'Electricity bill',
        sensitivity: sensitivity,
        client: session.client!,
        session: session,
      ),
    ),
  );
  return session;
}

http.Response _text(String text, {String sensitivity = ''}) => http.Response(
  jsonEncode({
    'id': 91,
    'content': text,
    if (sensitivity.isNotEmpty) 'sensitivity': sensitivity,
  }),
  200,
  headers: {'content-type': 'application/json'},
);

final class _MemoryVault implements CredentialVault {
  @override
  Future<void> clear() async {}
  @override
  Future<StoredCredentials?> read() async => null;
  @override
  Future<void> save(StoredCredentials credentials) async {}
}
