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

  testWidgets('filters paginated tags and stages selection and removal', (
    tester,
  ) async {
    final methods = <String>[];
    final pages = <int>[];
    final session = await _session(
      (_) async => _json({'id': 91}),
      tags: (request) async {
        final page = int.parse(request.url.queryParameters['page']!);
        pages.add(page);
        expect(request.url.queryParameters['page_size'], '500');
        return _json({
          'count': 502,
          'results': [
            if (page == 1) ...[
              _tag(1, 'Utilities', 'utilities'),
              _tag(2, 'Electricity', 'electricity'),
              for (var i = 3; i <= 500; i++) _tag(i, 'Other $i', 'other-$i'),
            ] else ...[
              _tag(501, 'Travel', 'travel'),
              _tag(502, 'Transit', 'transit'),
            ],
          ],
        });
      },
      bulk: (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        methods.add('${body['method']}:${body['parameters']['tag_id']}');
        expect(body['documents'], [91]);
        return _bulkOk(body);
      },
    );
    final result = await _openEditor(tester, session);
    expect(pages, [1, 2]);
    await tester.enterText(
      find.widgetWithText(TextField, 'Find existing tags'),
      'trav',
    );
    await tester.pump();
    expect(find.text('Travel'), findsOneWidget);
    await tester.tap(find.text('Travel'));
    await tester.pump();
    expect(methods, isEmpty);
    final utilities = find.widgetWithText(InputChip, 'Utilities');
    await tester.ensureVisible(utilities);
    await tester.pump();
    await tester.tap(find.byTooltip('Remove Utilities'));
    await tester.pump();
    expect(methods, isEmpty);
    await _save(tester);
    expect(methods, ['remove_tag:1', 'add_tag:501']);
    expect(result.value, isTrue);
  });

  testWidgets('a 200 per-document refusal stays visible and can be retried', (
    tester,
  ) async {
    var attempts = 0;
    var current = {'utilities', 'electricity'};
    final session = await _session(
      (_) async => _json({'id': 91}),
      detail: () => _detailWithTags(current),
      bulk: (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        attempts++;
        if (attempts == 1) {
          return _json({
            'method': body['method'],
            'total': 1,
            'applied': 0,
            'results': [
              {'id': 91, 'ok': false, 'code': 'forbidden'},
            ],
          });
        }
        current = {...current, 'travel'};
        return _bulkOk(body);
      },
    );
    final result = await _openEditor(tester, session);
    await tester.enterText(
      find.widgetWithText(TextField, 'Find existing tags'),
      'travel',
    );
    await tester.pump();
    await tester.tap(find.text('Travel'));
    await _save(tester);
    expect(find.textContaining('refused the tag change'), findsOneWidget);
    expect(result.value, isNull);
    await _save(tester);
    expect(attempts, 2);
    expect(result.value, isTrue);
  });

  testWidgets(
    'reconciles partial writes without replaying successful changes',
    (tester) async {
      final methods = <String>[];
      var current = {'utilities', 'electricity'};
      final session = await _session(
        (_) async => _json({'id': 91}),
        detail: () => _detailWithTags(current),
        bulk: (request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          methods.add(body['method'] as String);
          if (body['method'] == 'remove_tag') {
            current = {'electricity'};
            return _bulkOk(body);
          }
          if (methods.length == 2) {
            return _json({'error': 'write refused'}, status: 403);
          }
          current = {'electricity', 'travel'};
          return _bulkOk(body);
        },
      );
      final result = await _openEditor(tester, session);
      await tester.enterText(
        find.widgetWithText(TextField, 'Find existing tags'),
        'travel',
      );
      await tester.pump();
      await tester.tap(find.text('Travel'));
      final utilities = find.widgetWithText(InputChip, 'Utilities');
      await tester.ensureVisible(utilities);
      await tester.pump();
      await tester.tap(find.byTooltip('Remove Utilities'));
      await _save(tester);
      expect(result.value, isNull);
      expect(
        find.text('Your token does not permit this action.'),
        findsOneWidget,
      );
      await _save(tester);
      expect(methods, ['remove_tag', 'add_tag', 'add_tag']);
      expect(result.value, isTrue);
    },
  );

  testWidgets(
    'stops remaining tag writes when the original account signs out',
    (tester) async {
      final pending = Completer<http.Response>();
      final methods = <String>[];
      final session = await _session(
        (_) async => _json({'id': 91}),
        bulk: (request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          methods.add(body['method'] as String);
          return pending.future;
        },
      );
      final result = await _openEditor(tester, session);
      await tester.enterText(
        find.widgetWithText(TextField, 'Find existing tags'),
        'travel',
      );
      await tester.pump();
      await tester.tap(find.text('Travel'));
      final utilities = find.widgetWithText(InputChip, 'Utilities');
      await tester.ensureVisible(utilities);
      await tester.pump();
      await tester.tap(find.byTooltip('Remove Utilities'));
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(methods, ['remove_tag']);
      await session.signOut();
      pending.complete(
        _json({
          'method': 'remove_tag',
          'total': 1,
          'applied': 1,
          'results': [
            {'id': 91, 'ok': true},
          ],
        }),
      );
      await tester.pumpAndSettle();
      expect(methods, ['remove_tag']);
      expect(result.value, isNull);
      expect(
        find.text('The account changed. Reopen the document to edit it.'),
        findsOneWidget,
      );
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('searches tags with 200% text on $platform', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = await _session((_) async => _json({'id': 91}));
      await _openEditor(tester, session, platform: platform, textScale: 2);
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'Find existing tags'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Find existing tags'),
        'trav',
      );
      await tester.pump();
      expect(find.text('Travel'), findsOneWidget);
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
  Future<http.Response> Function(http.Request) patch, {
  Future<http.Response> Function(http.Request)? tags,
  Future<http.Response> Function(http.Request)? bulk,
  Map<String, dynamic> Function()? detail,
}) async {
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
    if (request.method == 'GET' && request.url.path == '/api/tags/') {
      return tags == null
          ? _json({
              'count': 3,
              'results': [
                _tag(1, 'Utilities', 'utilities'),
                _tag(2, 'Electricity', 'electricity'),
                _tag(3, 'Travel', 'travel'),
              ],
            })
          : tags(request);
    }
    if (request.method == 'GET' && request.url.path == '/api/documents/91') {
      return _json(
        detail?.call() ?? jsonDecode(_fixture('document-detail.json')),
      );
    }
    if (request.method == 'POST' &&
        request.url.path == '/api/documents/bulk_edit') {
      return bulk == null
          ? _bulkOk(jsonDecode(request.body) as Map<String, dynamic>)
          : bulk(request);
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

Map<String, Object?> _tag(int id, String name, String slug) => {
  'id': id,
  'name': name,
  'slug': slug,
  'color': '#a6cee3',
  'parent_id': null,
  'child_count': 0,
};

Map<String, dynamic> _detailWithTags(Set<String> tags) =>
    (jsonDecode(_fixture('document-detail.json')) as Map<String, dynamic>)
      ..['tags'] = tags.toList();

http.Response _bulkOk(Map<String, dynamic> body) => _json({
  'method': body['method'],
  'total': 1,
  'applied': 1,
  'results': [
    {'id': 91, 'ok': true},
  ],
});

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
