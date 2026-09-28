import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_companion/scan/scanner_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('scanner-bridge-test');
  final bridge = ScannerBridge(channel: channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('capture preserves page order and PDF metadata', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'capture');
          expect(call.arguments, {'mode': 'scanner'});
          return <String, Object?>{
            'cancelled': false,
            'pdf_path': '/capture/document.pdf',
            'page_count': 2,
            'pages': [
              {'path': '/capture/page-000.jpg'},
              {'path': '/capture/page-001.jpg'},
            ],
          };
        });

    final capture = await bridge.capture();

    expect(capture.cancelled, isFalse);
    expect(capture.pageCount, 2);
    expect(capture.pdfPath, '/capture/document.pdf');
    expect(capture.pages.map((page) => page.path), [
      '/capture/page-000.jpg',
      '/capture/page-001.jpg',
    ]);
  });

  test('capture represents cancellation explicitly', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.arguments, {'mode': 'photo'});
          return <String, Object?>{
            'cancelled': true,
            'pdf_path': null,
            'page_count': 0,
            'pages': <Object?>[],
          };
        });

    final capture = await bridge.capture(mode: CaptureMode.photo);

    expect(capture.cancelled, isTrue);
    expect(capture.pages, isEmpty);
  });

  test('OCR preserves null Android confidence and page order', () async {
    const paths = ['/capture/page-000.jpg', '/capture/page-001.jpg'];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'recognizeText');
          expect(call.arguments, {'paths': paths});
          return <Object?>[
            {
              'path': paths[0],
              'text': 'first',
              'confidence': null,
              'language': null,
            },
            {
              'path': paths[1],
              'text': '',
              'confidence': null,
              'language': null,
              'error_code': 'recognition_failed',
            },
          ];
        });

    final pages = await bridge.recognizeText(paths);

    expect(pages.map((page) => page.path), paths);
    expect(pages.first.confidence, isNull);
    expect(pages.last.errorCode, 'recognition_failed');
  });

  test('OCR rejects reordered native results', () async {
    const paths = ['/capture/page-000.jpg', '/capture/page-001.jpg'];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <Object?>[
            {'path': paths[1], 'text': 'second'},
            {'path': paths[0], 'text': 'first'},
          ];
        });

    expect(() => bridge.recognizeText(paths), throwsA(isA<FormatException>()));
  });
  test('capture exposes native settings recovery', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: 'camera_denied',
            message: 'Camera access is required.',
            details: {'retryable': false, 'open_settings': true},
          );
        });

    await expectLater(
      bridge.capture(),
      throwsA(
        isA<ScannerFailure>()
            .having((error) => error.code, 'code', 'camera_denied')
            .having((error) => error.openSettings, 'openSettings', isTrue),
      ),
    );
  });

  test('openSettings invokes the native settings action', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'openSettings');
          return null;
        });

    await bridge.openSettings();
  });
  test('discardCapture passes only native capture paths', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'discardCapture');
          expect(call.arguments, {
            'paths': ['/capture/page-000.jpg', '/capture/document.pdf'],
          });
          return null;
        });

    await bridge.discardCapture(
      const CaptureResult(
        cancelled: false,
        pageCount: 1,
        pages: [CapturedPage(path: '/capture/page-000.jpg')],
        pdfPath: '/capture/document.pdf',
      ),
    );
  });
}
