import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';
import 'package:suchi_mobile/auth/session_controller.dart';
import 'package:suchi_mobile/documents/thumbnail_cache.dart';
import 'package:suchi_mobile/search/search_screen.dart';
import 'package:suchi_mobile/search/saved_searches.dart';
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

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('saved searches stay account-scoped and usable on $platform', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var systemId = 1;
      final session = await _pairedSession(systemId: () => systemId);
      addTearDown(session.dispose);
      final storage = _MemorySecureStorage();
      var searches = SavedSearchController(session: session, storage: storage);
      await searches.reload();

      Future<void> showScreen() => tester.pumpWidget(
        MaterialApp(
          theme: SuchiTheme.light.copyWith(platform: platform),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SearchScreen(
              client: session.client!,
              session: session,
              cache: ThumbnailMemoryCache(),
              savedSearches: searches,
              onOpenDocument: (_) {},
            ),
          ),
        ),
      );

      await showScreen();
      await tester.enterText(
        find.byKey(const ValueKey('archive-search')),
        'annual statements',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('saved-search-name')),
        'Yearly papers',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(searches.entries.single.query, 'annual statements');

      await tester.pumpWidget(const SizedBox.shrink());
      searches.dispose();
      searches = SavedSearchController(session: session, storage: storage);
      await searches.reload();
      await showScreen();
      await tester.pumpAndSettle();
      final entry = searches.entries.single;
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('saved-search-${entry.id}')),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('saved-search-${entry.id}')));
      await tester.pump(const Duration(milliseconds: 321));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('archive-search')))
            .controller!
            .text,
        'annual statements',
      );
      expect(find.text('Saved-query result'), findsOneWidget);
      expect(find.byKey(const ValueKey('save-search')), findsOneWidget);

      await session.signOut();
      systemId = 2;
      await session.pairWithToken(
        serverAddress: _origin.toString(),
        token: _token,
      );
      await searches.reload();
      await showScreen();
      await tester.pumpAndSettle();
      expect(searches.entries, isEmpty);
      expect(find.text('Yearly papers'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('archive-search')),
        'family statements',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('saved-search-name')),
        'Family papers',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(searches.entries.single.query, 'family statements');

      await session.signOut();
      systemId = 1;
      await session.pairWithToken(
        serverAddress: _origin.toString(),
        token: _token,
      );
      await searches.reload();
      await showScreen();
      await tester.pumpAndSettle();
      expect(searches.entries.single.name, 'Yearly papers');
      expect(find.text('Family papers'), findsNothing);

      await tester.scrollUntilVisible(
        find.byTooltip('Delete Yearly papers'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete Yearly papers'));
      await tester.pumpAndSettle();
      expect(searches.entries, isEmpty);
      await searches.reload();
      expect(searches.entries, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      searches.dispose();
    });
  }

  testWidgets('saved-search read failures stay recoverable without promotion', (
    tester,
  ) async {
    final session = await _pairedSession();
    addTearDown(session.dispose);
    final storage = _MemorySecureStorage();
    final searches = SavedSearchController(session: session, storage: storage);
    addTearDown(searches.dispose);
    await searches.reload();
    final pending = Completer<String?>();
    storage.nextRead = pending;
    final loading = searches.reload();
    await tester.pumpWidget(
      MaterialApp(
        theme: SuchiTheme.light,
        home: Scaffold(
          body: SearchScreen(
            client: session.client!,
            session: session,
            cache: ThumbnailMemoryCache(),
            savedSearches: searches,
            onOpenDocument: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.text('Kept on this device for this archive account.'),
      findsOneWidget,
    );
    pending.completeError(StateError('Protected storage unavailable'));
    await loading;
    await tester.pump();
    expect(find.text(searches.errorMessage!), findsOneWidget);
    expect(
      find.text('Run a search, then choose Save this search to use it again.'),
      findsNothing,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(searches.ready, isTrue);
    expect(
      find.text('Run a search, then choose Save this search to use it again.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('failed writes preserve searches and late reads cannot cross filing systems', () async {
    var userId = 1;
    var systemId = 1;
    final session = await _pairedSession(
      userId: () => userId,
      systemId: () => systemId,
    );
    addTearDown(session.dispose);
    final storage = _MemorySecureStorage();
    final searches = SavedSearchController(session: session, storage: storage);
    addTearDown(searches.dispose);
    await searches.reload();
    expect(
      await searches.save(name: 'Private papers', query: 'account one'),
      isTrue,
    );
    final original = storage.values.values.single;
    storage.failWrites = true;
    expect(await searches.remove(searches.entries.single.id), isFalse);
    expect(searches.entries.single.query, 'account one');
    expect(searches.errorMessage, contains('could not be updated'));
    expect(storage.values.values.single, original);
    storage.failWrites = false;

    final delayedRead = Completer<String?>();
    storage.nextRead = delayedRead;
    final reading = searches.reload();
    await Future<void>.delayed(Duration.zero);
    await session.signOut();
    expect(searches.entries, isEmpty);
    systemId = 2;
    await session.pairWithToken(
      serverAddress: _origin.toString(),
      token: _token,
    );
    await searches.reload();
    expect(searches.entries, isEmpty);
    delayedRead.complete(original);
    await reading;
    expect(searches.entries, isEmpty);
    expect(
      await searches.save(name: 'Other papers', query: 'account two'),
      isTrue,
    );
    expect(storage.values.length, 2);

    await session.signOut();
    userId = 1;
    systemId = 1;
    await session.pairWithToken(
      serverAddress: _origin.toString(),
      token: _token,
    );
    await searches.reload();
    expect(searches.entries.single.query, 'account one');
    expect(
      storage.values.keys.every((key) => !key.contains(_origin.host)),
      isTrue,
    );
  });
}

Future<SessionController> _pairedSession({
  int Function()? userId,
  int Function()? systemId,
}) async {
  final session = SessionController(
    vault: _MemoryVault(),
    clientFactory: (origin, token) => SuchiClient(
      origin: origin,
      token: token,
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/handshake') {
          return http.Response(
            _fixture('handshake.json'),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/whoami') {
          final who =
              jsonDecode(_fixture('whoami.json')) as Map<String, dynamic>;
          who['user_id'] = userId?.call() ?? 1;
          who['system_id'] = systemId?.call() ?? 1;
          who['system_name'] = who['system_id'] == 1
              ? 'Archive'
              : 'Family archive';
          who['system_code'] = who['system_id'] == 1 ? '' : 'F02';
          return http.Response(
            jsonEncode(who),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return _searchResponse(title: 'Saved-query result');
      }),
    ),
  );
  await session.pairWithToken(serverAddress: _origin.toString(), token: _token);
  return session;
}

final class _MemorySecureStorage extends FlutterSecureStorage {
  final values = <String, String>{};
  bool failWrites = false;
  Completer<String?>? nextRead;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final pending = nextRead;
    nextRead = null;
    return pending == null ? values[key] : pending.future;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failWrites) throw StateError('Protected storage unavailable');
    values[key] = value!;
  }
}

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
