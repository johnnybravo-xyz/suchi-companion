import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';
import 'package:suchi_mobile/auth/session_controller.dart';
import 'package:suchi_mobile/detail/document_detail_screen.dart';
import 'package:suchi_mobile/detail/document_files.dart';
import 'package:suchi_mobile/documents/jd_category_store.dart';
import 'package:suchi_mobile/documents/thumbnail_cache.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _origin = Uri.parse('https://suchi.example.com');
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
String _fixture(String name) =>
    File('test/fixtures/api/v1/$name').readAsStringSync();

void main() {
  testWidgets(
    'sensitive detail fetches bytes only after Reveal and supports Hide',
    (tester) async {
      final requests = <http.Request>[];
      final firstThumbnail = Completer<http.Response>();
      var thumbnailRequests = 0;
      final detail =
          jsonDecode(_fixture('document-detail.json')) as Map<String, dynamic>;
      detail['sensitivity'] = 'restricted';
      final transport = MockClient((request) async {
        requests.add(request);
        switch (request.url.path) {
          case '/api/handshake':
            return _json(_fixture('handshake.json'));
          case '/api/whoami':
            return _json(_fixture('whoami.json'));
          case '/api/jd/categories/':
            return _json(_fixture('jd-categories.json'));
          case '/api/documents/91':
            if (request.method == 'PATCH') {
              detail.addAll(jsonDecode(request.body) as Map<String, dynamic>);
              return _json('{"id":91}');
            }
            return _json(jsonEncode(detail));
          case '/api/documents/91/thumb':
            thumbnailRequests++;
            if (thumbnailRequests == 1) return firstThumbnail.future;
            return http.Response.bytes(
              _png,
              200,
              headers: {'content-type': 'image/png'},
            );
          default:
            return http.Response('', 404);
        }
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
      final categories = JdCategoryStore(
        client: session.client!,
        onUnauthorized: session.expire,
      );
      final filesDirectory = Directory.systemTemp.createTempSync(
        'suchi-detail-test-',
      );
      addTearDown(() => filesDirectory.deleteSync(recursive: true));
      await tester.pumpWidget(
        MaterialApp(
          theme: SuchiTheme.light,
          home: DocumentDetailScreen(
            files: DocumentFiles(root: filesDirectory),
            documentId: 91,
            client: session.client!,
            session: session,
            cache: ThumbnailMemoryCache(),
            categories: categories,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Restricted preview hidden'), findsOneWidget);
      expect(
        requests
            .where((request) => request.url.path == '/api/documents/91')
            .every(
              (request) =>
                  request.url.queryParameters['include_content'] == '0',
            ),
        isTrue,
      );
      await tester.ensureVisible(find.text('Read text'));
      await tester.tap(find.text('Read text'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Read sensitive text?'), findsOneWidget);
      expect(
        requests.where(
          (request) => request.url.queryParameters['include_content'] == '1',
        ),
        isEmpty,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.fling(find.byType(ListView), const Offset(0, 1200), 2000);
      await tester.pumpAndSettle();
      expect(
        requests.where((request) => request.url.path.endsWith('/thumb')),
        isEmpty,
      );

      await tester.tap(find.text('Reveal preview'));
      await tester.pump();

      final observedThumbnails = requests
          .where((request) => request.url.path.endsWith('/thumb'))
          .toList();
      expect(observedThumbnails, hasLength(1));
      expect(observedThumbnails.single.url.queryParameters, {
        'width': '512',
        'reveal': '1',
      });
      expect(find.text('Hide'), findsOneWidget);

      await tester.tap(find.text('Hide'));
      await tester.pump();
      expect(find.byType(Image, skipOffstage: false), findsNothing);
      expect(find.text('Restricted preview hidden'), findsOneWidget);
      firstThumbnail.complete(
        http.Response.bytes(_png, 200, headers: {'content-type': 'image/png'}),
      );
      await tester.pumpAndSettle();

      expect(find.text('Restricted preview hidden'), findsOneWidget);
      expect(find.byType(Image, skipOffstage: false), findsNothing);

      await tester.tap(find.text('Reveal preview'));
      await tester.pumpAndSettle();

      expect(
        requests.where((request) => request.url.path.endsWith('/thumb')),
        hasLength(2),
      );
      expect(find.text('Hide'), findsOneWidget);

      expect(find.byType(Image), findsOneWidget);
      await tester.tap(find.text('Hide'));
      await tester.pump();
      expect(find.byType(Image, skipOffstage: false), findsNothing);
      await tester.tap(find.text('Reveal preview'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('Restricted preview hidden'), findsOneWidget);
      expect(find.text('Hide'), findsNothing);
      expect(find.byType(Image, skipOffstage: false), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Restricted preview hidden'), findsOneWidget);
      expect(
        requests.where((request) => request.url.path.endsWith('/thumb')),
        hasLength(3),
      );

      await tester.tap(find.text('Reveal preview'));
      await tester.pumpAndSettle();
      expect(
        requests.where((request) => request.url.path.endsWith('/thumb')),
        hasLength(4),
      );

      await tester.ensureVisible(find.text('Share'));
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(find.text('Share this document?'), findsOneWidget);
      expect(
        requests.where((request) => request.url.path.endsWith('/download')),
        isEmpty,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        requests.where((request) => request.url.path.endsWith('/download')),
        isEmpty,
      );
      await tester.tap(find.byTooltip('Edit document'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Updated electricity bill',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Updated electricity bill'),
        -250,
      );
      await tester.pumpAndSettle();
      expect(find.text('Updated electricity bill'), findsOneWidget);
      final patches = requests.where((request) => request.method == 'PATCH');
      expect(patches, hasLength(1));
      expect(jsonDecode(patches.single.body), {
        'title': 'Updated electricity bill',
      });
      await tester.fling(find.byType(ListView), const Offset(0, 1200), 2000);
      await tester.pumpAndSettle();
      expect(find.text('Restricted preview hidden'), findsOneWidget);
      categories.dispose();
    },
  );

  testWidgets('information disclosure hides source details until expanded', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final requests = <http.Request>[];
    final detail =
        jsonDecode(_fixture('document-detail.json')) as Map<String, dynamic>;
    detail['sensitivity'] = 'confidential';
    await _openDetail(tester, detail: detail, requests: requests);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp(r'\bClassification: Confidential\b')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Document information'), 250);
    expect(find.text('Personal Outlook'), findsNothing);
    expect(find.text('reader@example.com / INBOX'), findsNothing);
    expect(find.text('BESCOM'), findsNothing);
    expect(find.text('electricity'), findsNothing);

    expect(find.text('Document information'), findsOneWidget);
    await tester.tap(find.text('Document information'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('reader@example.com / INBOX'));
    expect(find.text('reader@example.com / INBOX'), findsOneWidget);
    expect(find.text('BESCOM'), findsOneWidget);
    expect(find.text('electricity'), findsOneWidget);
    await tester.ensureVisible(find.text('Document information'));
    await tester.tap(find.text('Document information'));
    await tester.pumpAndSettle();
    expect(find.text('reader@example.com / INBOX'), findsNothing);
    expect(
      requests.where(
        (request) =>
            request.url.path.endsWith('/thumb') ||
            request.url.queryParameters['include_content'] == '1',
      ),
      isEmpty,
    );
    semantics.dispose();
  });

  testWidgets('public and internal classifications are not called sensitive', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final sensitivity in ['', 'public', 'internal']) {
      final detail =
          jsonDecode(_fixture('document-detail.json')) as Map<String, dynamic>;
      detail['sensitivity'] = sensitivity;
      await _openDetail(tester, detail: detail);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(
          RegExp(
            'Classification: ${switch (sensitivity) {
              'public' => 'Public',
              'internal' => 'Internal',
              _ => 'Not set',
            }}',
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('preview hidden'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    semantics.dispose();
  });

  testWidgets('failed reload retains identity and exposes error and retry', (
    tester,
  ) async {
    final reload = Completer<http.Response>();
    var reads = 0;
    final detail =
        jsonDecode(_fixture('document-detail.json')) as Map<String, dynamic>;
    detail['sensitivity'] = 'restricted';
    await _openDetail(
      tester,
      detail: detail,
      respond: (request) async {
        if (request.url.path == '/api/documents/91' &&
            request.method == 'GET') {
          reads++;
          if (reads == 2) return reload.future;
        }
        return null;
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit document'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Corrected electricity bill',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(find.text('March electricity bill'), -250);
    await tester.pump();
    expect(find.text('March electricity bill'), findsOneWidget);
    expect(find.text('Refreshing document information…'), findsOneWidget);

    reload.complete(_unavailable('reload-91'));
    await tester.pumpAndSettle();
    expect(find.text('March electricity bill'), findsOneWidget);
    expect(find.text('Showing last loaded information.'), findsOneWidget);
    expect(find.textContaining('reload-91'), findsOneWidget);
    expect(find.text('Refreshing document information…'), findsNothing);
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Corrected electricity bill'),
      -250,
    );
    expect(find.text('Corrected electricity bill'), findsOneWidget);
    expect(find.text('Showing last loaded information.'), findsNothing);
    expect(find.textContaining('reload-91'), findsNothing);
    expect(find.text('Restricted preview hidden'), findsOneWidget);
  });

  testWidgets('initial error recovers through metadata and preview retry', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final initial = Completer<http.Response>();
    final preview = Completer<http.Response>();
    var reads = 0;
    var previews = 0;
    await _openDetail(
      tester,
      disableAnimations: true,
      respond: (request) async {
        if (request.url.path == '/api/documents/91') {
          reads++;
          if (reads == 1) return initial.future;
        }
        if (request.url.path.endsWith('/thumb')) {
          previews++;
          if (previews == 1) return preview.future;
          return http.Response.bytes(
            _png,
            200,
            headers: {'content-type': 'image/png'},
          );
        }
        return null;
      },
    );
    expect(find.bySemanticsLabel('Loading document'), findsOneWidget);
    initial.complete(_unavailable('initial-91'));
    await tester.pumpAndSettle();
    expect(find.textContaining('initial-91'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text('March electricity bill'), findsOneWidget);
    await tester.ensureVisible(find.byType(CircularProgressIndicator));
    await tester.pump();
    expect(
      find.bySemanticsLabel(RegExp(r'\bLoading preview\b')),
      findsOneWidget,
    );
    preview.complete(http.Response('', 404));
    await tester.pumpAndSettle();
    expect(find.text('Preview is still being prepared.'), findsOneWidget);
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('No preview available'), findsNothing);
    semantics.dispose();
  });

  testWidgets('account transition conceals preview and rejects late reveal', (
    tester,
  ) async {
    for (final delayed in [false, true]) {
      final pending = Completer<http.Response>();
      final detail =
          jsonDecode(_fixture('document-detail.json')) as Map<String, dynamic>;
      detail['sensitivity'] = 'restricted';
      final session = await _openDetail(
        tester,
        detail: detail,
        respond: (request) async {
          if (request.url.path.endsWith('/thumb')) {
            if (delayed) return pending.future;
            return http.Response.bytes(
              _png,
              200,
              headers: {'content-type': 'image/png'},
            );
          }
          return null;
        },
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reveal preview'));
      if (delayed) {
        await tester.pump();
      } else {
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsOneWidget);
      }
      await session.signOut();
      await tester.pump();
      expect(find.byType(Image, skipOffstage: false), findsNothing);
      expect(find.text('March electricity bill'), findsNothing);
      if (delayed) {
        pending.complete(
          http.Response.bytes(
            _png,
            200,
            headers: {'content-type': 'image/png'},
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Image, skipOffstage: false), findsNothing);
        expect(find.text('March electricity bill'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

http.Response _json(String body) =>
    http.Response(body, 200, headers: {'content-type': 'application/json'});

http.Response _unavailable(String requestId) => http.Response(
  '{"error":{"message":"Temporarily unavailable"}}',
  503,
  headers: {'content-type': 'application/json', 'x-request-id': requestId},
);

Future<SessionController> _openDetail(
  WidgetTester tester, {
  Map<String, dynamic>? detail,
  List<http.Request>? requests,
  Future<http.Response?> Function(http.Request)? respond,
  bool disableAnimations = false,
}) async {
  final document =
      detail ??
      jsonDecode(_fixture('document-detail.json')) as Map<String, dynamic>;
  final transport = MockClient((request) async {
    requests?.add(request);
    final response = await respond?.call(request);
    if (response != null) return response;
    switch (request.url.path) {
      case '/api/handshake':
        return _json(_fixture('handshake.json'));
      case '/api/whoami':
        return _json(_fixture('whoami.json'));
      case '/api/jd/categories/':
        return _json(_fixture('jd-categories.json'));
      case '/api/documents/91':
        if (request.method == 'PATCH') {
          document.addAll(jsonDecode(request.body) as Map<String, dynamic>);
          return _json('{"id":91}');
        }
        return _json(jsonEncode(document));
      case '/api/documents/91/thumb':
        return http.Response('', 202);
      default:
        return http.Response('', 404);
    }
  });
  final session = SessionController(
    vault: _MemoryVault(),
    clientFactory: (origin, token) =>
        SuchiClient(origin: origin, token: token, httpClient: transport),
  );
  await session.pairWithToken(serverAddress: _origin.toString(), token: _token);
  final categories = JdCategoryStore(
    client: session.client!,
    onUnauthorized: session.expire,
  );
  final directory = Directory.systemTemp.createTempSync('suchi-detail-test-');
  addTearDown(() {
    categories.dispose();
    session.dispose();
    directory.deleteSync(recursive: true);
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: SuchiTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: DocumentDetailScreen(
        files: DocumentFiles(root: directory),
        documentId: 91,
        client: session.client!,
        session: session,
        cache: ThumbnailMemoryCache(),
        categories: categories,
      ),
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
