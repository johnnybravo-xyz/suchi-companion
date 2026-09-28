import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_companion/api/api_error.dart';
import 'package:suchi_companion/api/suchi_client.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _id = '11111111-1111-4111-8111-111111111111';
const _pdf = <int>[0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34, 0x0a];
final _origin = Uri.parse('https://suchi.example.com');

void main() {
  late Directory temporary;
  late File payload;
  late String digest;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('suchi-upload-test-');
    payload = File('${temporary.path}/scan.pdf');
    await payload.writeAsBytes(_pdf, flush: true);
    digest = sha256.convert(_pdf).toString();
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('streams frozen multipart metadata with auth and idempotency', () async {
    late http.Request observed;
    final progress = <int>[];
    final client = SuchiClient(
      origin: _origin,
      token: _token,
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'id': 93,
            'sha256': digest,
            'size': _pdf.length,
            'mime_type': 'application/pdf',
            'title': 'Camera scan',
          }),
          201,
          headers: {
            'content-type': 'application/json',
            'location': '/api/documents/93',
          },
        );
      }),
    );

    final result = await client.uploadDocument(
      file: payload,
      byteSize: _pdf.length,
      sha256Hex: digest,
      mimeType: 'application/pdf',
      filename: 'Camera scan.pdf',
      idempotencyKey: _id,
      sourceMtime: 1770000000,
      ocrContent: 'Recognized text',
      ocrConfidence: 0.91,
      ocrLanguage: 'en-US',
      onProgress: progress.add,
    );

    expect(result.id, 93);
    expect(observed.followRedirects, isFalse);
    expect(observed.headers['Authorization'], 'Token $_token');
    expect(observed.headers['Idempotency-Key'], _id);
    expect(
      observed.headers['content-type'],
      startsWith('multipart/form-data;'),
    );
    final body = latin1.decode(observed.bodyBytes);
    expect(body, contains('name="source_mtime"\r\n\r\n1770000000'));
    expect(body, contains('name="content_source"\r\n\r\ndevice_ocr'));
    expect(body, contains('name="content_confidence"\r\n\r\n0.91'));
    expect(body, contains('name="ocr_language"\r\n\r\nen-US'));
    expect(body, contains('filename="Camera scan.pdf"'));
    expect(progress.last, _pdf.length);
  });

  test('rejects an inconsistent Location before accepting success', () async {
    final client = SuchiClient(
      origin: _origin,
      token: _token,
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'id': 93,
            'sha256': digest,
            'size': _pdf.length,
            'mime_type': 'application/pdf',
            'title': 'Camera scan',
          }),
          201,
          headers: {
            'content-type': 'application/json',
            'location': 'https://attacker.example/api/documents/93',
            'x-request-id': 'upload-93',
          },
        ),
      ),
    );

    await expectLater(
      client.uploadDocument(
        file: payload,
        byteSize: _pdf.length,
        sha256Hex: digest,
        mimeType: 'application/pdf',
        filename: 'Camera scan.pdf',
        idempotencyKey: _id,
      ),
      throwsA(
        isA<ApiException>()
            .having(
              (error) => error.kind,
              'kind',
              ApiFailureKind.malformedResponse,
            )
            .having((error) => error.requestId, 'requestId', 'upload-93'),
      ),
    );
  });

  test('rejects partial OCR metadata before making a request', () async {
    var requestCount = 0;
    final client = SuchiClient(
      origin: _origin,
      token: _token,
      httpClient: MockClient((request) async {
        requestCount++;
        return http.Response('{}', 500);
      }),
    );

    await expectLater(
      client.uploadDocument(
        file: payload,
        byteSize: _pdf.length,
        sha256Hex: digest,
        mimeType: 'application/pdf',
        filename: 'Camera scan.pdf',
        idempotencyKey: _id,
        ocrContent: 'text without provenance',
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.rejected,
        ),
      ),
    );
    expect(requestCount, 0);
  });

  test(
    'maps an externally aborted multipart request to cancellation',
    () async {
      final cancel = Completer<void>();
      final transport = MockClient.streaming((request, bodyStream) async {
        if (request case http.Abortable(:final abortTrigger?)) {
          await abortTrigger;
        }
        throw http.RequestAbortedException(request.url);
      });
      final client = SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: transport,
      );

      final upload = client.uploadDocument(
        file: payload,
        byteSize: _pdf.length,
        sha256Hex: digest,
        mimeType: 'application/pdf',
        filename: 'Camera scan.pdf',
        idempotencyKey: _id,
        abortTrigger: cancel.future,
      );
      cancel.complete();

      await expectLater(
        upload,
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.cancelled,
          ),
        ),
      );
    },
  );

  test('never follows an upload redirect', () async {
    var requestCount = 0;
    final client = SuchiClient(
      origin: _origin,
      token: _token,
      httpClient: MockClient((request) async {
        requestCount++;
        return http.Response(
          '',
          307,
          headers: {'location': 'https://attacker.example/collect'},
        );
      }),
    );

    await expectLater(
      client.uploadDocument(
        file: payload,
        byteSize: _pdf.length,
        sha256Hex: digest,
        mimeType: 'application/pdf',
        filename: 'Camera scan.pdf',
        idempotencyKey: _id,
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.redirect,
        ),
      ),
    );
    expect(requestCount, 1);
  });
}
