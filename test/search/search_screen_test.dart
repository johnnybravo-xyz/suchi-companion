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
import 'package:suchi_mobile/documents/thumbnail_cache.dart';
import 'package:suchi_mobile/search/search_screen.dart';
import 'package:suchi_mobile/search/saved_views.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _origin = Uri.parse('https://suchi.example.com');
String _fixture(String name) =>
    File('test/fixtures/api/v1/$name').readAsStringSync();

void main() {
  test('snippet renderer interprets only exact mark tags', () {
    final spans = sanitizedHighlightSpans(
      'before <mark>match</mark> <script>unsafe</script>',
      highlightStyle: const TextStyle(fontWeight: FontWeight.w700),
    ).whereType<TextSpan>().toList();

    expect(
      spans.map((span) => span.text).join(),
      'before match <script>unsafe</script>',
    );
    expect(
      spans.singleWhere((span) => span.text == 'match').style?.fontWeight,
      FontWeight.w700,
    );
    expect(spans.last.text, contains('<script>'));
  });

  testWidgets('a late response cannot replace a newer query', (tester) async {
    final first = Completer<http.Response>();
    final transport = MockClient((request) async {
      if (request.url.path == '/api/handshake') {
        return http.Response(
          _fixture('handshake.json'),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/whoami') {
        return http.Response(
          _fixture('whoami.json'),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final query = request.url.queryParameters['q'];
      if (query == 'first') return first.future;
      return _searchResponse(title: 'Newer result');
    });
    final session = SessionController(
      vault: _MemoryVault(),
      clientFactory: (origin, token) =>
          SuchiClient(origin: origin, token: token, httpClient: transport),
    );
    await session.pairWithToken(
      serverAddress: _origin.toString(),
      token: _token,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: SuchiTheme.light,
        home: Scaffold(
          body: SearchScreen(
            client: session.client!,
            session: session,
            cache: ThumbnailMemoryCache(),
            onOpenDocument: (_) {},
            onOpenSavedView: (_) {},
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('archive-search')),
      'first',
    );
    await tester.pump(const Duration(milliseconds: 321));
    await tester.enterText(
      find.byKey(const ValueKey('archive-search')),
      'second',
    );
    await tester.pump(const Duration(milliseconds: 321));
    await tester.pump();

    expect(find.text('Newer result'), findsOneWidget);

    first.complete(_searchResponse(title: 'Stale result'));
    await tester.pumpAndSettle();

    expect(find.text('Newer result'), findsOneWidget);
    expect(find.text('Stale result'), findsNothing);
  });

  testWidgets('Saved Views sync, open, create, and delete through the server', (
    tester,
  ) async {
    final server = _SavedViewServer()
      ..viewsBySystem[1] = [
        _savedView(
          id: 7,
          name: 'Annual statements',
          filterJson: '{"q":"annual statements"}',
        ),
      ];
    final session = await _pairedSession(server);
    addTearDown(session.dispose);
    final views = SavedViewController(session: session);
    addTearDown(views.dispose);
    await views.reload();
    SavedView? opened;

    await tester.pumpWidget(
      MaterialApp(
        theme: SuchiTheme.light,
        home: Scaffold(
          body: SearchScreen(
            client: session.client!,
            session: session,
            cache: ThumbnailMemoryCache(),
            savedViews: views,
            onOpenDocument: (_) {},
            onOpenSavedView: (view) => opened = view,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SAVED VIEWS'), findsOneWidget);
    expect(find.text('Synced with your Suchi server.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('saved-view-7')));
    expect(opened?.id, 7);
    expect(opened?.filter?.query, 'annual statements');

    await tester.enterText(
      find.byKey(const ValueKey('archive-search')),
      'quarterly tax',
    );
    await tester.pump(const Duration(milliseconds: 321));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-view')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('saved-view-name')),
      'Quarterly review',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final create = server.requests.lastWhere(
      (request) =>
          request.method == 'POST' && request.url.path == '/api/saved_views/',
    );
    expect(jsonDecode(create.body), {
      'name': 'Quarterly review',
      'filter_json': '{"q":"quarterly tax"}',
      'display': 'list',
      'position': 1,
      'shared': false,
    });
    expect(
      views.entries.map((view) => view.name),
      contains('Quarterly review'),
    );

    await tester.enterText(find.byKey(const ValueKey('archive-search')), '');
    await tester.pumpAndSettle();
    expect(find.text('Quarterly review'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete Quarterly review'));
    await tester.pumpAndSettle();
    expect(
      views.entries.map((view) => view.name),
      isNot(contains('Quarterly review')),
    );
    expect(
      server.requests.any(
        (request) =>
            request.method == 'DELETE' &&
            request.url.path == '/api/saved_views/8',
      ),
      isTrue,
    );
  });

  test('Saved View failures retain the last server-backed list', () async {
    final server = _SavedViewServer()
      ..viewsBySystem[1] = [
        _savedView(
          id: 7,
          name: 'Annual statements',
          filterJson: '{"q":"annual statements"}',
        ),
      ];
    final session = await _pairedSession(server);
    addTearDown(session.dispose);
    final views = SavedViewController(session: session);
    addTearDown(views.dispose);
    await views.reload();

    server.failDelete = true;
    expect(await views.remove(7), isFalse);
    expect(views.entries.single.id, 7);
    expect(views.errorMessage, contains('could not be deleted'));

    server.failDelete = false;
    server.failCreate = true;
    expect(await views.save(name: 'New View', query: 'tax'), isFalse);
    expect(views.entries.single.id, 7);
    expect(views.errorMessage, contains('could not be created'));

    server.failCreate = false;
    server.failList = true;
    await views.reload();
    expect(views.entries.single.id, 7);
    expect(views.errorMessage, contains('could not be loaded'));
  });

  test('late Saved View reads cannot cross account transitions', () async {
    var systemId = 1;
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final server = _SavedViewServer(systemId: () => systemId)
      ..viewsBySystem[2] = [
        _savedView(
          id: 22,
          name: 'Family archive',
          filterJson: '{"q":"family"}',
        ),
      ]
      ..nextList = pending
      ..nextListStarted = started;
    final session = await _pairedSession(server);
    addTearDown(session.dispose);
    final views = SavedViewController(session: session);
    addTearDown(views.dispose);
    await started.future;

    await session.signOut();
    expect(views.entries, isEmpty);
    systemId = 2;
    await session.pairWithToken(
      serverAddress: _origin.toString(),
      token: _token,
    );
    await views.reload();
    expect(views.entries.single.name, 'Family archive');

    pending.complete(
      _savedViewsResponse([
        _savedView(
          id: 7,
          name: 'Private archive',
          filterJson: '{"q":"private"}',
        ),
      ]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(views.entries.single.name, 'Family archive');
  });
}

Future<SessionController> _pairedSession(_SavedViewServer server) async {
  final session = SessionController(
    vault: _MemoryVault(),
    clientFactory: (origin, token) => SuchiClient(
      origin: origin,
      token: token,
      httpClient: MockClient(server.handle),
    ),
  );
  await session.pairWithToken(serverAddress: _origin.toString(), token: _token);
  return session;
}

final class _SavedViewServer {
  _SavedViewServer({int Function()? systemId})
    : _systemId = systemId ?? (() => 1);

  final int Function() _systemId;
  final viewsBySystem = <int, List<Map<String, Object?>>>{};
  final requests = <http.Request>[];
  bool failList = false;
  bool failCreate = false;
  bool failDelete = false;
  int nextId = 8;
  Completer<http.Response>? nextList;
  Completer<void>? nextListStarted;

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/api/handshake') {
      return http.Response(
        _fixture('handshake.json'),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path == '/api/whoami') {
      final who = jsonDecode(_fixture('whoami.json')) as Map<String, dynamic>;
      final systemId = _systemId();
      who['system_id'] = systemId;
      who['system_name'] = systemId == 1 ? 'Archive' : 'Family archive';
      who['system_code'] = systemId == 1 ? '' : 'F02';
      return _jsonResponse(who);
    }
    if (path == '/api/logout') return http.Response('', 204);
    if (path == '/api/search/') {
      return _searchResponse(title: 'Saved-query result');
    }
    if (path == '/api/saved_views/' && request.method == 'GET') {
      final pending = nextList;
      nextList = null;
      final started = nextListStarted;
      nextListStarted = null;
      if (started != null && !started.isCompleted) started.complete();
      if (pending != null) return pending.future;
      if (failList) {
        return _jsonResponse({
          'message': 'Saved Views are unavailable.',
        }, status: 503);
      }
      return _savedViewsResponse(viewsBySystem[_systemId()] ?? const []);
    }
    if (path == '/api/saved_views/' && request.method == 'POST') {
      if (failCreate) {
        return _jsonResponse({
          'message': 'Saved View already exists.',
        }, status: 409);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final id = nextId++;
      (viewsBySystem[_systemId()] ??= []).add(
        _savedView(
          id: id,
          name: body['name'] as String,
          filterJson: body['filter_json'] as String,
          position: body['position'] as int,
        ),
      );
      return _jsonResponse({'id': id}, status: 201);
    }
    final delete = RegExp(r'^/api/saved_views/(\d+)$').firstMatch(path);
    if (delete != null && request.method == 'DELETE') {
      if (failDelete) {
        return _jsonResponse({
          'message': 'Saved View could not be deleted.',
        }, status: 503);
      }
      final id = int.parse(delete.group(1)!);
      viewsBySystem[_systemId()]?.removeWhere((view) => view['id'] == id);
      return http.Response('', 204);
    }
    return http.Response('', 404);
  }
}

Map<String, Object?> _savedView({
  required int id,
  required String name,
  required String filterJson,
  int position = 0,
}) => {
  'id': id,
  'name': name,
  'filter_json': filterJson,
  'display': 'list',
  'position': position,
  'shared': false,
  'created_at': 1770000000,
  'updated_at': 1770000000,
};

http.Response _savedViewsResponse(Iterable<Map<String, Object?>> views) {
  final results = views.toList();
  return _jsonResponse({
    'count': results.length,
    'next': null,
    'previous': null,
    'results': results,
  });
}

http.Response _jsonResponse(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _searchResponse({required String title}) => http.Response(
  jsonEncode({
    'count': 1,
    'next': null,
    'previous': null,
    'results': [
      {
        'id': 17,
        'title': title,
        'snippet': '',
        'rank': 1.0,
        'created_at': 1770000000,
        'mime_type': 'application/pdf',
        'sensitivity': 'restricted',
      },
    ],
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
