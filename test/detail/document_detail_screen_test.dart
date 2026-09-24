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
import 'package:suchi_mobile/auth/session_controller.dart';
import 'package:suchi_mobile/detail/document_detail_screen.dart';
import 'package:suchi_mobile/detail/email_preview.dart';
import 'package:suchi_mobile/detail/document_files.dart';
import 'package:suchi_mobile/documents/jd_category_store.dart';
import 'package:suchi_mobile/documents/thumbnail_cache.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/fake_webview.dart';

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

      await tester.tap(find.byKey(const ValueKey('document-preview')));
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

      await tester.tap(find.byTooltip('Share document'));
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

  testWidgets(
    'preview-first detail keeps metadata and provenance always visible',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final requests = <http.Request>[];
      final detail =
          jsonDecode(_fixture('document-detail.json')) as Map<String, dynamic>;
      detail['sensitivity'] = 'confidential';
      await _openDetail(tester, detail: detail, requests: requests);
      await tester.pumpAndSettle();

      final preview = find.byKey(const ValueKey('document-preview'));
      expect(preview, findsOneWidget);
      expect(
        tester.getTopLeft(preview).dy,
        lessThan(tester.getTopLeft(find.text('March electricity bill')).dy),
      );
      expect(find.widgetWithText(AppBar, 'Document'), findsNothing);
      expect(find.byTooltip('Share document'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('16.4 KB'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('DETAILS', skipOffstage: false),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Read text'), findsOneWidget);
      expect(find.text('File under…'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Filed: 31 · Home / Utilities'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('From: BESCOM'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Tags: utilities · electricity'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Sensitivity: Confidential'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Languages: de,en'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Source', skipOffstage: false),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      final metadata = find.byKey(const ValueKey('document-metadata'));
      expect(
        find.descendant(of: metadata, matching: find.text('Added')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: metadata,
          matching: find.text('Personal Outlook / mailbox'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: metadata, matching: find.text('Blob')),
        findsNothing,
      );
      expect(find.textContaining('reader@example.com'), findsNothing);
      expect(
        requests.where(
          (request) =>
              request.url.path.endsWith('/thumb') ||
              request.url.queryParameters['include_content'] == '1',
        ),
        isEmpty,
      );
      semantics.dispose();
    },
  );

  testWidgets('preview and AppBar hand off the full document', (tester) async {
    const channel = MethodChannel('app.suchi.page/documents');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final requests = <http.Request>[];
    await _openDetail(
      tester,
      requests: requests,
      respond: (request) async {
        if (request.url.path.endsWith('/preview') ||
            request.url.path.endsWith('/download')) {
          return http.Response.bytes(
            const [37, 80, 68, 70],
            200,
            headers: {'content-type': 'application/pdf'},
          );
        }
        return null;
      },
    );
    await tester.pumpAndSettle();

    Future<void> invokeAndWait(VoidCallback callback, int count) async {
      await tester.runAsync(() async {
        callback();
        for (var attempt = 0; attempt < 40 && calls.length < count; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump(const Duration(milliseconds: 300));
    }

    final open = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Open'),
    );
    final previewBounds = tester.getRect(
      find.byKey(const ValueKey('document-preview')),
    );
    final openBounds = tester.getRect(
      find.widgetWithText(FilledButton, 'Open'),
    );
    expect(openBounds.center.dy, greaterThan(previewBounds.center.dy));
    expect(openBounds.center.dx, greaterThan(previewBounds.center.dx));
    expect(open.onPressed, isNotNull);
    await invokeAndWait(open.onPressed!, 1);
    expect(
      requests.where((request) => request.url.path.endsWith('/preview')),
      hasLength(1),
    );
    expect(calls, hasLength(1));
    expect(calls.single.method, 'open');

    final share = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.ios_share_outlined),
    );
    expect(share.onPressed, isNotNull);
    await invokeAndWait(share.onPressed!, 2);
    expect(calls.last.method, 'share');
    expect(
      requests.where((request) => request.url.path.endsWith('/preview')),
      hasLength(1),
    );
    expect(
      requests.where((request) => request.url.path.endsWith('/download')),
      hasLength(1),
    );
  });

  testWidgets('Details sensitivity retries refusal, gates and clears preview', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final detail =
        jsonDecode(_fixture('document-detail.json')) as Map<String, dynamic>;
    detail['sensitivity'] = 'public';
    final requests = <http.Request>[];
    var rejectOnce = true;
    var changes = 0;
    await _openDetail(
      tester,
      detail: detail,
      requests: requests,
      onChanged: () => changes++,
      respond: (request) async {
        if (request.url.path.endsWith('/thumb')) {
          return http.Response.bytes(
            _png,
            200,
            headers: {'content-type': 'image/png'},
          );
        }
        if (request.method == 'PATCH' && rejectOnce) {
          rejectOnce = false;
          return http.Response(
            '{"error":{"message":"Cannot classify this document."}}',
            422,
            headers: {'content-type': 'application/json'},
          );
        }
        return null;
      },
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);

    Future<void> chooseRestricted(String current) async {
      final row = find.bySemanticsLabel('Sensitivity: $current');
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restricted'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await chooseRestricted('Public');
    expect(find.text('The sensitivity could not be changed.'), findsOneWidget);
    expect(find.bySemanticsLabel('Sensitivity: Public'), findsOneWidget);
    expect(changes, 0);
    await tester.pumpAndSettle();

    await chooseRestricted('Public');
    final patches = requests
        .where((request) => request.method == 'PATCH')
        .toList();
    expect(patches, hasLength(2));
    for (final patch in patches) {
      expect(jsonDecode(patch.body), {'sensitivity': 'restricted'});
    }
    expect(find.bySemanticsLabel('Sensitivity: Restricted'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(find.text('Restricted preview hidden'), findsOneWidget);
    expect(find.byType(Image, skipOffstage: false), findsNothing);
    expect(changes, 1);

    final restricted = find.bySemanticsLabel('Sensitivity: Restricted');
    await tester.ensureVisible(restricted);
    await tester.pumpAndSettle();
    await tester.tap(restricted);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not set'));
    await tester.pumpAndSettle();
    expect(
      jsonDecode(
        requests.lastWhere((request) => request.method == 'PATCH').body,
      ),
      {'sensitivity': ''},
    );
    expect(find.bySemanticsLabel('Sensitivity: Not set'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(changes, 2);
    semantics.dispose();
  });

  testWidgets('account transition dismisses the sensitivity choice', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final session = await _openDetail(tester, requests: requests);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sensitivity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sensitivity'));
    await tester.pumpAndSettle();
    expect(find.text('Restricted'), findsOneWidget);

    await session.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Restricted'), findsNothing);
    expect(requests.where((request) => request.method == 'PATCH'), isEmpty);
  });

  testWidgets('public and internal sensitivity remains explicit', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final sensitivity in ['', 'public', 'internal']) {
      final detail =
          jsonDecode(_fixture('document-detail.json')) as Map<String, dynamic>;
      detail['sensitivity'] = sensitivity;
      await _openDetail(tester, detail: detail);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Sensitivity'), 200);
      expect(
        find.bySemanticsLabel(
          'Sensitivity: ${switch (sensitivity) {
            'public' => 'Public',
            'internal' => 'Internal',
            _ => 'Not set',
          }}',
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
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
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

  testWidgets(
    'email preview stays in memory and clears on lifecycle concealment',
    (tester) async {
      final platform = FakeWebViewPlatform();
      WebViewPlatform.instance = platform;
      final requests = <http.Request>[];
      final detail =
          jsonDecode(_fixture('document-detail.json')) as Map<String, dynamic>
            ..['mime_type'] = 'message/rfc822'
            ..['sensitivity'] = 'public';
      await _openDetail(
        tester,
        detail: detail,
        requests: requests,
        respond: (request) async {
          if (request.url.path.endsWith('/preview')) {
            return http.Response(
              '<!doctype html><html><head></head><body>Email body</body></html>',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
          return null;
        },
      );
      await tester.pumpAndSettle();

      final previews = requests
          .where((request) => request.url.path.endsWith('/preview'))
          .toList();
      expect(previews, hasLength(1));
      expect(previews.single.url.queryParameters, isEmpty);
      expect(previews.single.headers['Accept'], 'text/html');
      expect(
        requests.where((request) => request.url.path.endsWith('/thumb')),
        isEmpty,
      );
      expect(find.byType(SandboxedEmailPreview), findsOneWidget);
      expect(
        platform.controller.loadedHtml.last,
        contains("default-src 'none'"),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byType(SandboxedEmailPreview), findsNothing);
      expect(platform.controller.loadedHtml.last, emptyWebViewPage);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        requests.where((request) => request.url.path.endsWith('/preview')),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'sensitive email fetches HTML only after Reveal and Hide purges it',
    (tester) async {
      final platform = FakeWebViewPlatform();
      WebViewPlatform.instance = platform;
      final requests = <http.Request>[];
      final detail =
          jsonDecode(_fixture('document-detail.json')) as Map<String, dynamic>
            ..['mime_type'] = 'message/rfc822'
            ..['sensitivity'] = 'restricted';
      await _openDetail(
        tester,
        detail: detail,
        requests: requests,
        respond: (request) async {
          if (request.url.path.endsWith('/preview')) {
            return http.Response(
              '<html><head></head><body>Restricted email</body></html>',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
          return null;
        },
      );
      await tester.pumpAndSettle();

      expect(
        requests.where((request) => request.url.path.endsWith('/preview')),
        isEmpty,
      );
      await tester.tap(find.text('Reveal preview'));
      await tester.pumpAndSettle();
      final previews = requests
          .where((request) => request.url.path.endsWith('/preview'))
          .toList();
      expect(previews, hasLength(1));
      expect(previews.single.url.queryParameters, {'reveal': '1'});
      expect(find.byType(SandboxedEmailPreview), findsOneWidget);

      await tester.tap(find.text('Hide'));
      await tester.pump();
      expect(find.byType(SandboxedEmailPreview), findsNothing);
      expect(find.text('Restricted preview hidden'), findsOneWidget);
      expect(platform.controller.loadedHtml.last, emptyWebViewPage);
    },
  );

  testWidgets('narrow 200% detail keeps the full hierarchy usable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _openDetail(tester, textScale: 2);
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('File under…'), 200);
    expect(find.text('Read text'), findsOneWidget);
    expect(find.text('File under…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Sensitivity'), 200);
    expect(find.text('Not set'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Personal Outlook / mailbox'),
      200,
    );
    expect(find.text('Personal Outlook / mailbox'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
  VoidCallback? onChanged,
  bool disableAnimations = false,
  double textScale = 1,
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
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: DocumentDetailScreen(
        files: DocumentFiles(root: directory),
        documentId: 91,
        client: session.client!,
        session: session,
        cache: ThumbnailMemoryCache(),
        categories: categories,
        onChanged: onChanged,
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
