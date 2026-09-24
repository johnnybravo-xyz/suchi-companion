import 'package:flutter/material.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

const emptyWebViewPage =
    '<!doctype html><html><head></head><body></body></html>';

final class FakeWebViewPlatform extends WebViewPlatform {
  late FakeWebViewController controller;
  late FakeNavigationDelegate delegate;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    controller = FakeWebViewController(params);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    delegate = FakeNavigationDelegate(params);
    return delegate;
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => FakeWebViewWidget(params);
}

final class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();

  JavaScriptMode? javaScriptMode;
  PlatformNavigationDelegate? navigationDelegate;
  void Function(PlatformWebViewPermissionRequest request)? permissionRequest;
  final loadedHtml = <String>[];
  final baseUrls = <String?>[];
  int cacheClears = 0;
  int storageClears = 0;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {
    this.javaScriptMode = javaScriptMode;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    navigationDelegate = handler;
  }

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) async {
    permissionRequest = onPermissionRequest;
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    loadedHtml.add(html);
    baseUrls.add(baseUrl);
  }

  @override
  Future<void> clearCache() async {
    cacheClears++;
  }

  @override
  Future<void> clearLocalStorage() async {
    storageClears++;
  }
}

final class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? navigationRequest;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    navigationRequest = onNavigationRequest;
  }
}

final class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(child: ColoredBox(color: Colors.white));
}
