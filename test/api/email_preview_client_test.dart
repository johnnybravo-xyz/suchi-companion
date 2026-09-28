import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_companion/api/api_error.dart';
import 'package:suchi_companion/api/suchi_client.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _origin = Uri.parse('https://suchi.example.com');

void main() {
  SuchiClient client(Future<http.Response> Function(http.Request) handler) =>
      SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: MockClient(handler),
      );

  test(
    'email preview requests bounded authenticated HTML without redirects',
    () async {
      late http.Request observed;
      final api = client((request) async {
        observed = request;
        return http.Response(
          '<!doctype html><html><head></head><body>Mail</body></html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });

      expect(await api.emailPreview(91, reveal: true), contains('Mail'));
      expect(observed.url.path, '/api/documents/91/preview');
      expect(observed.url.queryParameters, {'reveal': '1'});
      expect(observed.headers['Accept'], 'text/html');
      expect(observed.headers['Authorization'], 'Token $_token');
      expect(observed.followRedirects, isFalse);
      expect(observed.maxRedirects, 0);
    },
  );

  test('email preview refuses redirects and sensitive gates', () async {
    final redirecting = client(
      (_) async => http.Response(
        '',
        302,
        headers: {'location': 'https://attacker.example/mail'},
      ),
    );
    await expectLater(
      redirecting.emailPreview(91),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.redirect,
        ),
      ),
    );

    final gated = client(
      (_) async => http.Response(
        '{"sensitivity":"restricted","gated":true}',
        202,
        headers: {'content-type': 'application/json'},
      ),
    );
    await expectLater(
      gated.emailPreview(91),
      throwsA(
        isA<ApiException>()
            .having((error) => error.kind, 'kind', ApiFailureKind.rejected)
            .having((error) => error.statusCode, 'statusCode', 202),
      ),
    );
  });

  test('email preview requires HTML declared as UTF-8', () async {
    for (final contentType in [
      'text/plain; charset=utf-8',
      'text/html',
      'text/html; charset=iso-8859-1',
      'not a media type',
    ]) {
      final api = client(
        (_) async => http.Response.bytes(
          utf8.encode('<html><head></head><body>Mail</body></html>'),
          200,
          headers: {'content-type': contentType},
        ),
      );
      await expectLater(
        api.emailPreview(91),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.malformedResponse,
          ),
        ),
        reason: contentType,
      );
    }
  });

  test(
    'email preview refuses malformed UTF-8 and responses over 8 MiB',
    () async {
      final malformed = client(
        (_) async => http.Response.bytes(
          [0xc3, 0x28],
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      );
      await expectLater(
        malformed.emailPreview(91),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.malformedResponse,
          ),
        ),
      );

      final oversized = client(
        (_) async => http.Response.bytes(
          Uint8List(8 * 1024 * 1024 + 1),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      );
      await expectLater(
        oversized.emailPreview(91),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.malformedResponse,
          ),
        ),
      );
    },
  );

  test('email preview decodes non-ASCII UTF-8 exactly', () async {
    const html = '<html><head></head><body>नमस्ते café</body></html>';
    final api = client(
      (_) async => http.Response.bytes(
        utf8.encode(html),
        200,
        headers: {'content-type': 'text/html; charset=UTF-8'},
      ),
    );

    expect(await api.emailPreview(91), html);
  });
}
