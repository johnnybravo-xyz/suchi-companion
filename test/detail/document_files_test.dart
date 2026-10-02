import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_companion/api/api_error.dart';
import 'package:suchi_companion/api/suchi_client.dart';
import 'package:suchi_companion/detail/document_files.dart';
import 'package:suchi_companion/scan/storage_protection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.suchi/document-files');
  late Directory directory;
  late DocumentFiles files;
  late List<MethodCall> calls;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('suchi-exports-test-');
    files = DocumentFiles(
      root: directory,
      channel: channel,
      storageCapacity: _UnlimitedStorage(),
    );
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'open' || call.method == 'share') {
            final arguments = call.arguments as Map;
            expect(arguments.keys.toSet(), {'path', 'mime_type'});
            expect(
              await File(arguments['path'] as String).readAsString(),
              '%PDF-test',
            );
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  SuchiClient client(Future<http.Response> Function(http.Request) handler) =>
      SuchiClient(
        origin: Uri.parse('https://suchi.example.com'),
        token:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        httpClient: MockClient(handler),
      );

  http.Response pdf() => http.Response(
    '%PDF-test',
    200,
    headers: {'content-type': 'application/pdf'},
  );

  test(
    'opens a completed local preview and retains the handoff bytes',
    () async {
      await files.handoff(
        client: client((request) async {
          expect(request.url.path, '/api/documents/91/preview');
          expect(request.url.queryParameters, {'reveal': '1'});
          return pdf();
        }),
        documentId: 91,
        displayName: 'Electricity bill, March 2026',
        share: false,
        reveal: true,
      );

      expect(calls.single.method, 'open');
      final path = (calls.single.arguments as Map)['path'] as String;
      expect(path.endsWith('/Electricity bill, March 2026.pdf'), true);
      expect(await File(path).exists(), true);
      await files.clear();
      expect(calls.last.method, 'dismiss');
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test('email handoff uses the .eml extension and message MIME type', () async {
    await files.handoff(
      client: client(
        (_) async => http.Response(
          '%PDF-test',
          200,
          headers: {'content-type': 'message/rfc822'},
        ),
      ),
      documentId: 91,
      displayName: 'Account/statement.eml',
      share: false,
    );

    final arguments = calls.single.arguments as Map;
    expect(
      (arguments['path'] as String).endsWith('/Account statement.eml'),
      isTrue,
    );
    expect(arguments['mime_type'], 'message/rfc822');
  });

  test(
    'share requests the archive without granting raw-original access',
    () async {
      await files.handoff(
        client: client((request) async {
          expect(request.url.path, '/api/documents/91/download');
          expect(request.url.queryParameters, isEmpty);
          return pdf();
        }),
        documentId: 91,
        displayName: 'Current document title',
        share: true,
      );
      expect(calls.single.method, 'share');
    },
  );

  test(
    'an identity clear prevents a pending download from reaching native UI',
    () async {
      final response = Completer<http.Response>();
      final requested = Completer<void>();
      final handoff = files.handoff(
        client: client((_) {
          requested.complete();
          return response.future;
        }),
        documentId: 91,
        displayName: 'Current document title',
        share: true,
      );
      final failed = expectLater(handoff, throwsA(isA<ApiException>()));
      await requested.future;
      final cleared = files.clear();
      response.complete(pdf());
      await failed;
      await cleared;
      expect(calls.map((call) => call.method), ['dismiss']);
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test('native handoff failures remove temporary bytes', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'viewer_unavailable');
        });
    await expectLater(
      files.handoff(
        client: client((_) async => pdf()),
        documentId: 91,
        displayName: 'Current document title',
        share: false,
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(await directory.list().toList(), isEmpty);
  });

  test('local cleanup can retry after a native dismissal failure', () async {
    var dismissals = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          if (++dismissals == 1) {
            throw PlatformException(code: 'temporarily_busy');
          }
          return null;
        });
    await expectLater(files.clear(), throwsA(isA<PlatformException>()));
    await files.clear();
    expect(dismissals, 2);
  });

  test(
    'handoff retries failed cleanup before opening a new document',
    () async {
      var dismissals = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'dismiss' && ++dismissals == 1) {
              throw PlatformException(code: 'temporarily_busy');
            }
            return null;
          });
      await expectLater(files.clear(), throwsA(isA<PlatformException>()));
      await files.handoff(
        client: client((_) async => pdf()),
        documentId: 91,
        displayName: 'Current document title',
        share: false,
      );
      expect(calls.map((call) => call.method), ['dismiss', 'dismiss', 'open']);
    },
  );
}

final class _UnlimitedStorage implements StorageCapacity {
  @override
  Future<int> availableBytes(String absolutePath) async => 1 << 60;
}
