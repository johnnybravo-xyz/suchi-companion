import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/api_error.dart';
import 'package:suchi_mobile/api/suchi_client.dart';

void main() {
  test(
    'text read is explicit, scoped, bounded and allows unclassified text',
    () async {
      final client = _client((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/documents/91');
        expect(request.url.queryParameters, {'include_content': '1'});
        expect(request.headers['Authorization'], 'Token ${'a' * 64}');
        expect(request.followRedirects, isFalse);
        return _json({'id': 91, 'content': 'Plain <text> 📄'});
      });
      expect(await client.documentText(91), (
        text: 'Plain <text> 📄',
        sensitivity: '',
      ));
    },
  );

  for (final body in [
    {'id': 92, 'content': 'wrong document'},
    {'id': 91.0, 'content': 'invalid id type'},
    {'id': 91, 'content': null},
    {'id': 91, 'content': 'text', 'sensitivity': 'unknown'},
    {'id': 91, 'content': 'text', 'sensitivity': 1},
  ]) {
    test('refuses malformed text projection $body', () async {
      final client = _client((_) async => _json(body));
      await expectLater(
        client.documentText(91),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.malformedResponse,
          ),
        ),
      );
    });
  }

  test('text response retains the eight MiB JSON byte cap', () async {
    final client = _client(
      (_) async => _json({'id': 91, 'content': 'x' * (8 * 1024 * 1024)}),
    );
    await expectLater(
      client.documentText(91),
      throwsA(
        isA<ApiException>()
            .having(
              (error) => error.kind,
              'kind',
              ApiFailureKind.malformedResponse,
            )
            .having((error) => error.message, 'message', contains('too large')),
      ),
    );
  });
}

SuchiClient _client(Future<http.Response> Function(http.Request) respond) =>
    SuchiClient(
      origin: Uri.parse('https://suchi.example.com'),
      token: 'a' * 64,
      httpClient: MockClient(respond),
    );

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);
