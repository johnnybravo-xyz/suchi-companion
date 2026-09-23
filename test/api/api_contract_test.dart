import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/api_error.dart';
import 'package:suchi_mobile/api/api_models.dart';
import 'package:suchi_mobile/api/suchi_client.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _origin = Uri.parse('https://suchi.example.com');

Object? _fixture(String name) =>
    jsonDecode(File('test/fixtures/api/v1/$name').readAsStringSync());

void main() {
  group('canonical API fixtures', () {
    test('parse every pinned mobile response shape', () {
      final handshake = Handshake.fromJson(_fixture('handshake.json'));
      final user = UserSelf.fromJson(_fixture('whoami.json'));
      final documents = PageEnvelope.fromJson(
        _fixture('documents-page.json'),
        DocumentSummary.fromJson,
      );
      final detail = DocumentDetail.fromJson(_fixture('document-detail.json'));
      final search = PageEnvelope.fromJson(
        _fixture('search-page.json'),
        SearchHit.fromJson,
      );
      final categories = PageEnvelope.fromJson(
        _fixture('jd-categories.json'),
        JDCategory.fromJson,
      );
      final created = UploadResult.fromJson(
        _fixture('upload-created.json'),
        statusCode: 201,
      );
      final replayed = UploadResult.fromJson(
        _fixture('upload-replayed.json'),
        statusCode: 201,
      );
      final tasks = TasksResponse.fromJson(_fixture('tasks-processing.json'));
      final error = parseApiError(_fixture('error.json'), 409);

      expect(handshake.product, 'suchi');
      expect(user.hasMobileScopes, isTrue);
      expect(user.systemId, 1);
      expect(user.systemName, 'Archive');
      expect(user.systemCode, isEmpty);
      expect(documents.results, hasLength(2));
      expect(documents.results.last.isSensitive, isTrue);
      expect(detail.sources.single.kind, 'mailbox');
      expect(search.results.last.snippet, isEmpty);
      expect(categories.results.last.code, 49);
      expect(created.created, isTrue);
      expect(replayed.idempotentReplay, isTrue);
      expect(tasks.results.single.documentId, 93);
      expect(error.code, 'idempotency_conflict');
    });

    test('rejects incomplete token filing-system identity', () {
      final value = _fixture('whoami.json')! as Map<String, dynamic>;
      value.remove('system_id');
      expect(
        () => UserSelf.fromJson(value),
        throwsA(isA<ApiFormatException>()),
      );
    });

    test('rejects content in a metadata-only detail response', () {
      final value = _fixture('document-detail.json')! as Map<String, dynamic>;
      value['content'] = 'private OCR text';
      expect(
        () => DocumentDetail.fromJson(value),
        throwsA(isA<ApiFormatException>()),
      );
    });

    test('rejects a sensitive search snippet', () {
      expect(
        () => SearchHit.fromJson({
          'id': 1,
          'title': 'Private',
          'snippet': '<mark>secret</mark>',
          'rank': -1.0,
          'created_at': 1,
          'sensitivity': 'confidential',
        }),
        throwsA(isA<ApiFormatException>()),
      );
    });

    test('accepts the server split index origin value', () {
      final results =
          (_fixture('documents-page.json')! as Map<String, dynamic>)['results']
              as List<dynamic>;
      final document = Map<String, dynamic>.from(
        results.first as Map<String, dynamic>,
      )..addAll({'split_origin_id': 1, 'split_index': 0});

      expect(DocumentSummary.fromJson(document).splitIndex, 0);
    });
  });

  group('complete split documents', () {
    Map<String, Object?> child(int id, {int originId = 35}) => {
      'id': id,
      'title': 'Child $id',
      'mime_type': 'application/pdf',
      'split_origin_id': originId,
      'split_index': id - 101,
      'created_at': 1,
      'updated_at': 1,
      'tags': <String>[],
      'correspondents': <String>[],
    };

    SuchiClient splitClient(Object Function(int page) response) => SuchiClient(
      origin: _origin,
      token: _token,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/documents/');
        expect(request.url.queryParameters['split_origin_id'], '35');
        expect(request.url.queryParameters['page_size'], '200');
        return http.Response(
          jsonEncode(response(int.parse(request.url.queryParameters['page']!))),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    test('returns complete children rather than only the first page', () async {
      final client = splitClient(
        (page) => {
          'count': 2,
          'results': [child(page == 1 ? 101 : 102)],
        },
      );
      expect((await client.splitDocuments(35)).map((item) => item.id), [
        101,
        102,
      ]);
    });

    test('rejects an empty page before the declared result count', () async {
      final client = splitClient(
        (page) => {
          'count': 2,
          'results': [if (page == 1) child(101)],
        },
      );
      await expectLater(
        client.splitDocuments(35),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.malformedResponse,
          ),
        ),
      );
    });

    test(
      'bounds incomplete pagination instead of looping indefinitely',
      () async {
        var pages = 0;
        final client = splitClient((page) {
          pages++;
          return {
            'count': 51,
            'results': [child(100 + page)],
          };
        });
        await expectLater(
          client.splitDocuments(35),
          throwsA(
            isA<ApiException>().having(
              (error) => error.kind,
              'kind',
              ApiFailureKind.malformedResponse,
            ),
          ),
        );
        expect(pages, 50);
      },
    );

    test('rejects a later page belonging to a different upload', () async {
      final client = splitClient(
        (page) => {
          'count': 2,
          'results': [child(100 + page, originId: page == 1 ? 35 : 36)],
        },
      );
      await expectLater(
        client.splitDocuments(35),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.malformedResponse,
          ),
        ),
      );
    });
  });

  group('SuchiClient transport boundary', () {
    test('handshake never sends credentials', () async {
      late http.Request observed;
      final httpClient = MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode(_fixture('handshake.json')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: httpClient,
      );

      await client.handshake();

      expect(
        observed.url.toString(),
        'https://suchi.example.com/api/handshake',
      );
      expect(observed.headers, isNot(contains('Authorization')));
      expect(observed.followRedirects, isFalse);
    });

    test('does not follow a cross-origin redirect', () async {
      var requests = 0;
      final client = SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: MockClient((request) async {
          requests++;
          return http.Response(
            '',
            302,
            headers: {'location': 'https://attacker.example/token'},
          );
        }),
      );

      await expectLater(
        client.whoAmI(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.redirect,
          ),
        ),
      );
      expect(requests, 1);
    });

    test('rejects successful JSON with the wrong MIME type', () async {
      final client = SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode(_fixture('whoami.json')),
            200,
            headers: {'content-type': 'text/plain'},
          ),
        ),
      );

      await expectLater(
        client.whoAmI(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.malformedResponse,
          ),
        ),
      );
    });

    test('preserves request ID and Retry-After on a canonical error', () async {
      final client = SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode(_fixture('error.json')),
            409,
            headers: {
              'content-type': 'application/json',
              'x-request-id': 'request-42',
              'retry-after': '15',
            },
          ),
        ),
      );

      await expectLater(
        client.listDocuments(),
        throwsA(
          isA<ApiException>()
              .having((error) => error.kind, 'kind', ApiFailureKind.conflict)
              .having((error) => error.code, 'code', 'idempotency_conflict')
              .having((error) => error.requestId, 'requestId', 'request-42')
              .having(
                (error) => error.retryAfter,
                'retryAfter',
                const Duration(seconds: 15),
              ),
        ),
      );
    });

    test('always requests metadata-only detail with authentication', () async {
      late http.Request observed;
      final client = SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: MockClient((request) async {
          observed = request;
          return http.Response(
            jsonEncode(_fixture('document-detail.json')),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await client.document(91);

      expect(observed.url.queryParameters, {'include_content': '0'});
      expect(observed.headers['Authorization'], 'Token $_token');
      expect(observed.followRedirects, isFalse);
    });

    test('rejects an incompatible server before accepting it', () async {
      final client = SuchiClient(
        origin: _origin,
        httpClient: MockClient(
          (request) async => http.Response(
            '{"product":"other","api_version":1,'
            '"min_app_version":"0.1.0"}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      await expectLater(
        client.handshake(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.incompatibleServer,
          ),
        ),
      );
    });
  });
}
