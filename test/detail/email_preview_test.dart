import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_companion/detail/email_preview.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/fake_webview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWebViewPlatform platform;
  setUp(() {
    platform = FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
  });

  test('hardening inserts the restrictive policy first in a complete head', () {
    const source =
        '<!doctype html><html><head data-mail="yes"><title>Mail</title></head>'
        '<body><img src="https://tracker.example/pixel"><form></form></body></html>';

    final hardened = hardenEmailPreviewHtml(source);

    expect(
      hardened,
      startsWith(
        '<!doctype html><html><head data-mail="yes"><meta '
        'http-equiv="Content-Security-Policy"',
      ),
    );
    expect(hardened, contains("default-src 'none'"));
    expect(hardened, contains("img-src data:"));
    expect(hardened, contains("script-src 'none'"));
    expect(hardened, contains("connect-src 'none'"));
    expect(hardened, contains("frame-src 'none'"));
    expect(hardened, contains("form-action 'none'"));
    expect(hardened, contains("base-uri 'none'"));
  });

  test('hardening rejects HTML without a usable head', () {
    expect(
      () => hardenEmailPreviewHtml('<html><body>Mail</body></html>'),
      throwsFormatException,
    );
    expect(
      () => hardenEmailPreviewHtml('<html><head><body>Mail</body></html>'),
      throwsFormatException,
    );
    expect(
      () => hardenEmailPreviewHtml(
        '<html><body><head></head><img src="https://tracker.example"></body></html>',
      ),
      throwsFormatException,
    );
    expect(
      () => hardenEmailPreviewHtml(
        '<html><img src="https://tracker.example"><head></head></html>',
      ),
      throwsFormatException,
    );
  });

  testWidgets(
    'renderer disables JavaScript, blocks navigation, opens through its callback and purges data',
    (tester) async {
      var opened = false;
      final html = hardenEmailPreviewHtml(
        '<html><head></head><body><a href="https://attacker.example">Mail</a></body></html>',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SandboxedEmailPreview(
              html: html,
              onOpen: () => opened = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final controller = platform.controller;
      expect(controller.javaScriptMode, JavaScriptMode.disabled);
      expect(controller.loadedHtml, [emptyWebViewPage, html]);
      expect(controller.baseUrls, [null, null]);
      expect(controller.cacheClears, 1);
      expect(controller.storageClears, 1);
      expect(controller.permissionRequest, isNotNull);
      expect(platform.delegate.navigationRequest, isNotNull);
      expect(
        await platform.delegate.navigationRequest!(
          const NavigationRequest(
            url: 'https://attacker.example/steal',
            isMainFrame: true,
          ),
        ),
        NavigationDecision.prevent,
      );
      expect(
        await platform.delegate.navigationRequest!(
          const NavigationRequest(url: 'about:blank', isMainFrame: true),
        ),
        NavigationDecision.prevent,
      );

      await tester.tap(find.bySemanticsLabel('Open email document'));
      expect(opened, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(controller.loadedHtml.last, emptyWebViewPage);
      expect(controller.cacheClears, 2);
      expect(controller.storageClears, 2);
    },
  );
}
