import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/api_models.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';
import 'package:suchi_mobile/auth/session_controller.dart';
import 'package:suchi_mobile/detail/document_edit_screen.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';

void main() {
  testWidgets('saves only the changed title and returns a refresh result', (
    tester,
  ) async {
    final patches = <Map<String, dynamic>>[];
    final session = await _session((request) async {
      patches.add(jsonDecode(request.body) as Map<String, dynamic>);
      return _json({'id': 91});
    });
    final result = await _openEditor(tester, session);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      '  Corrected receipt  ',
    );
    await _save(tester);
    expect(patches, [
      {'title': 'Corrected receipt'},
    ]);
    expect(result.value, isTrue);
    expect(find.text('Edit document'), findsNothing);
  });

  testWidgets(
    'requires a title and keeps edits after a refused save for retry',
    (tester) async {
      final patches = <Map<String, dynamic>>[];
      final session = await _session((request) async {
        patches.add(jsonDecode(request.body) as Map<String, dynamic>);
        return patches.length == 1
            ? _json({'error': 'not permitted'}, status: 403)
            : _json({'id': 91});
      });
      final result = await _openEditor(tester, session);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        '   ',
      );
      await _save(tester);
      expect(find.text('Enter a document title.'), findsOneWidget);
      expect(patches, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Retry this receipt',
      );
      await _save(tester);
      expect(
        find.text('Your token does not permit this action.'),
        findsOneWidget,
      );
      expect(find.text('Retry this receipt'), findsOneWidget);
      expect(result.value, isNull);
      await _save(tester);
      expect(patches, [
        {'title': 'Retry this receipt'},
        {'title': 'Retry this receipt'},
      ]);
      expect(result.value, isTrue);
    },
  );

  testWidgets('clearing languages sends an empty array to restore detection', (
    tester,
  ) async {
    final patches = <Map<String, dynamic>>[];
    final session = await _session((request) async {
      patches.add(jsonDecode(request.body) as Map<String, dynamic>);
      return _json({'id': 91});
    });
    await _openEditor(tester, session, languagesLocked: true);
    expect(find.text('These languages were set manually.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Languages'), '');
    await _save(tester);
    expect(patches, [
      {'languages': <String>[]},
    ]);
  });

  testWidgets('ignores a save result after the original account signs out', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final session = await _session((request) => pending.future);
    final result = await _openEditor(tester, session);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Private correction',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    await session.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Private correction'), findsNothing);
    expect(
      find.text('The account changed. Reopen the document to edit it.'),
      findsOneWidget,
    );
    pending.complete(_json({'id': 91}));
    await tester.pumpAndSettle();
    expect(result.value, isNull);
    expect(find.text('Edit document'), findsOneWidget);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('edits sensitivity with 200% text on $platform', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final patches = <Map<String, dynamic>>[];
      final session = await _session((request) async {
        patches.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _json({'id': 91});
      });
      final result = await _openEditor(
        tester,
        session,
        platform: platform,
        textScale: 2,
      );
      await tester.ensureVisible(find.text('Not set'));
      await tester.tap(find.text('Not set'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restricted').last);
      await tester.pumpAndSettle();
      await _save(tester);
      expect(patches, [
        {'sensitivity': 'restricted'},
      ]);
      expect(result.value, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _save(WidgetTester tester) async {
  await tester.pump();
  await tester.scrollUntilVisible(
    find.text('Save changes'),
    250,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(find.text('Save changes'));
  await tester.pumpAndSettle();
}

Future<ValueNotifier<bool?>> _openEditor(
  WidgetTester tester,
  SessionController session, {
  bool languagesLocked = false,
  TargetPlatform platform = TargetPlatform.android,
  double textScale = 1,
}) async {
  final result = ValueNotifier<bool?>(null);
  final detail =
      jsonDecode(_fixture('document-detail.json')) as Map<String, dynamic>;
  detail['languages_locked'] = languagesLocked;
  await tester.pumpWidget(
    MaterialApp(
      theme: SuchiTheme.light.copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result.value = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => DocumentEditScreen(
                    document: DocumentDetail.fromJson(detail),
                    client: session.client!,
                    session: session,
                  ),
                ),
              );
            },
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
  return result;
}

Future<SessionController> _session(
  Future<http.Response> Function(http.Request) patch,
) async {
  final transport = MockClient((request) async {
    if (request.url.path == '/api/handshake') {
      return _fixtureResponse('handshake.json');
    }
    if (request.url.path == '/api/whoami') {
      return _fixtureResponse('whoami.json');
    }
    if (request.url.path == '/api/logout') return http.Response('', 204);
    if (request.method == 'PATCH' && request.url.path == '/api/documents/91') {
      return patch(request);
    }
    return http.Response('', 404);
  });
  final session = SessionController(
    vault: _MemoryVault(),
    clientFactory: (origin, token) =>
        SuchiClient(origin: origin, token: token, httpClient: transport),
  );
  await session.pairWithToken(
    serverAddress: 'https://suchi.example.com',
    token: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );
  addTearDown(session.dispose);
  return session;
}

String _fixture(String name) =>
    File('test/fixtures/api/v1/$name').readAsStringSync();
http.Response _fixtureResponse(String name) => http.Response(
  _fixture(name),
  200,
  headers: {'content-type': 'application/json'},
);
http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
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
