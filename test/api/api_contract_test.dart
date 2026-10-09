import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_companion/api/api_error.dart';
import 'package:suchi_companion/api/api_models.dart';
import 'package:suchi_companion/api/suchi_client.dart';

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
      final approvals = TasksResponse.fromJson(
        _fixture('tasks-approvals.json'),
      );
      final dates = PageEnvelope.fromJson(
        _fixture('intelligence-pending-dates.json'),
        PendingDateReview.fromJson,
      );
      final error = parseApiError(_fixture('error.json'), 409);

      expect(handshake.product, 'suchi');
      expect(handshake.mobileContracts, ['suchi-companion-v1']);
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
      expect(tasks.documentChangeApprovals, isEmpty);
      expect(approvals.documentChangeApprovals, hasLength(4));
      expect(
        approvals.documentChangeApprovals.map((approval) => approval.field),
        [
          DocumentChangeField.title,
          DocumentChangeField.tag,
          DocumentChangeField.category,
          DocumentChangeField.tag,
        ],
      );
      expect(
        approvals.documentChangeApprovals.first.proposedValue,
        contains('March'),
      );
      expect(dates.results.single.precision, 'month');
      expect(dates.results.single.date, DateTime.utc(2027, 3));
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

    test('filters unsupported approvals before strict document parsing', () {
      final value = _fixture('tasks-approvals.json')! as Map<String, dynamic>;
      final rows = value['approval_tasks']! as List<dynamic>;
      rows[3] = {'approval_name': 'rescan-proposal'};
      rows[4] = {
        'approval_name': 'document-change',
        'vars': {'field': 'document_type'},
      };
      rows[5] = {'approval_name': 'future-workflow'};
      (value['counts']! as Map<String, dynamic>)['approvals_open'] = 999;

      final tasks = TasksResponse.fromJson(value);

      expect(tasks.documentChangeApprovals, hasLength(3));
    });

    test('rejects malformed supported document and date rows', () {
      for (final index in [0, 1, 2]) {
        final approvals =
            _fixture('tasks-approvals.json')! as Map<String, dynamic>;
        final documentChange =
            (approvals['approval_tasks']! as List<dynamic>)[index]
                as Map<String, dynamic>;
        (documentChange['vars']! as Map<String, dynamic>)['confidence'] = 1.1;
        expect(
          () => TasksResponse.fromJson(approvals),
          throwsA(isA<ApiFormatException>()),
        );
      }

      final dates =
          _fixture('intelligence-pending-dates.json')! as Map<String, dynamic>;
      final date =
          (dates['results']! as List<dynamic>).single as Map<String, dynamic>;
      date['source_current'] = false;
      expect(
        () => PageEnvelope.fromJson(dates, PendingDateReview.fromJson),
        throwsA(isA<ApiFormatException>()),
      );
    });

    test('accepts every canonical date role and precision', () {
      const roles = {
        'issued',
        'due',
        'start',
        'end',
        'expiry',
        'renewal',
        'service',
        'other',
      };
      const values = {
        'day': '2027-03-17',
        'month': '2027-03-01',
        'year': '2027-01-01',
      };
      for (final role in roles) {
        for (final entry in values.entries) {
          final dates =
              _fixture('intelligence-pending-dates.json')!
                  as Map<String, dynamic>;
          final date =
              (dates['results']! as List<dynamic>).single
                  as Map<String, dynamic>;
          date['role'] = role;
          date['value'] = {'date': entry.value, 'precision': entry.key};
          date['sort_value'] = entry.value;
          expect(
            PageEnvelope.fromJson(
              dates,
              PendingDateReview.fromJson,
            ).results.single.role,
            role,
          );
        }
      }
    });
  });

  group('approval review contracts', () {
    test('uses bounded generic feeds and filters supported rows', () async {
      final requests = <Uri>[];
      final client = SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: MockClient((request) async {
          requests.add(request.url);
          final fixture = switch (request.url.path) {
            '/api/tasks/' => 'tasks-approvals.json',
            '/api/intelligence/' => 'intelligence-pending-dates.json',
            _ => throw StateError('unexpected path ${request.url.path}'),
          };
          return http.Response(
            jsonEncode(_fixture(fixture)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final documentChanges = await client.listDocumentChangeApprovals();
      final dates = await client.listPendingDates();

      expect(documentChanges, hasLength(4));
      expect(dates, hasLength(1));
      expect(requests[0].queryParameters, {
        'include': 'approvals',
        'limit': '200',
      });
      expect(requests[1].queryParameters, {
        'type': 'date',
        'status': 'pending',
        'page': '1',
        'page_size': '500',
      });
    });

    test('maps review decisions to canonical wire literals', () async {
      final sent = <({String path, Map<String, dynamic> body})>[];
      final client = SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sent.add((path: request.url.path, body: body));
          if (request.url.path.startsWith('/api/approvals/tasks/')) {
            return http.Response('', 204);
          }
          final id = (body['candidate_ids']! as List<dynamic>).single as int;
          return http.Response(
            jsonEncode({
              'total': 1,
              'applied': 1,
              'results': [
                {'id': id, 'ok': true},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await client.resolveDocumentChangeApproval(301, ReviewDecision.accept);
      await client.resolveDocumentChangeApproval(302, ReviewDecision.dismiss);
      await client.resolvePendingDate(401, ReviewDecision.accept);
      await client.resolvePendingDate(402, ReviewDecision.dismiss);

      expect(sent.map((request) => request.path), [
        '/api/approvals/tasks/301/resolve',
        '/api/approvals/tasks/302/resolve',
        '/api/intelligence/resolve',
        '/api/intelligence/resolve',
      ]);
      expect(sent.map((request) => request.body), [
        <String, dynamic>{'choice': 'apply'},
        <String, dynamic>{'choice': 'reject'},
        <String, dynamic>{
          'candidate_ids': [401],
          'decision': 'accepted',
        },
        <String, dynamic>{
          'candidate_ids': [402],
          'decision': 'rejected',
        },
      ]);
    });

    test('enforces distinct confirmed-success contracts', () async {
      SuchiClient clientReturning(http.Response response) => SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: MockClient((_) async => response),
      );

      await expectLater(
        clientReturning(
          http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ).resolveDocumentChangeApproval(301, ReviewDecision.accept),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        clientReturning(
          http.Response(
            '{}',
            204,
            headers: {'content-type': 'application/json'},
          ),
        ).resolveDocumentChangeApproval(301, ReviewDecision.accept),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.malformedResponse,
          ),
        ),
      );
      await expectLater(
        clientReturning(http.Response('', 204))
            .resolvePendingDate(401, ReviewDecision.accept),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        clientReturning(
          http.Response(
            jsonEncode({
              'total': 1,
              'applied': 0,
              'results': [
                {'id': 401, 'ok': false, 'code': 'stale_source'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ).resolvePendingDate(401, ReviewDecision.accept),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'stale_source',
          ),
        ),
      );
      await expectLater(
        clientReturning(
          http.Response(
            jsonEncode({
              'total': 1,
              'applied': 1,
              'results': [
                {'id': 999, 'ok': true},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ).resolvePendingDate(401, ReviewDecision.accept),
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

  group('tag catalog and document assignment', () {
    test('loads bounded typed tag pages from the fixed origin', () async {
      final requests = <Uri>[];
      final client = SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'count': 501,
              'results': [
                {
                  'id': 2,
                  'name': 'Travel',
                  'slug': 'travel',
                  'color': '#a6cee3',
                  'parent_id': null,
                  'child_count': 0,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final page = await client.listTags(page: 2);
      expect(page.results.single.slug, 'travel');
      expect(page.results.single.childCount, 0);
      expect(requests.single.origin, _origin.origin);
      expect(requests.single.path, '/api/tags/');
      expect(requests.single.queryParameters, {
        'page': '2',
        'page_size': '500',
      });
      await expectLater(client.listTags(pageSize: 501), throwsRangeError);
    });
    test('rejects a cross-origin next link without fetching it', () async {
      var calls = 0;
      final client = SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'count': 501,
              'next': 'https://attacker.example/api/tags/?page=2&page_size=500',
              'results': [
                for (var id = 1; id <= 500; id++)
                  {
                    'id': id,
                    'name': 'Tag $id',
                    'slug': 'tag-$id',
                    'color': '#a6cee3',
                    'child_count': 0,
                  },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await expectLater(
        client.listTags(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.malformedResponse,
          ),
        ),
      );
      expect(calls, 1);
    });

    test('rejects invalid tag identity and oversized pages', () async {
      for (final body in [
        {
          'count': 1,
          'results': [
            {
              'id': 1,
              'name': 'Tag',
              'slug': '',
              'color': '#a6cee3',
              'child_count': 0,
            },
          ],
        },
        {
          'count': 2,
          'results': [
            for (var id = 1; id <= 2; id++)
              {
                'id': id,
                'name': 'Tag $id',
                'slug': 'tag-$id',
                'color': '#a6cee3',
                'child_count': 0,
              },
          ],
        },
      ]) {
        final client = SuchiClient(
          origin: _origin,
          token: _token,
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode(body),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        );
        await expectLater(
          client.listTags(pageSize: 1),
          throwsA(
            isA<ApiException>().having(
              (error) => error.kind,
              'kind',
              ApiFailureKind.malformedResponse,
            ),
          ),
        );
      }
    });

    test(
      'does not accept 200 when the per-document result is refused',
      () async {
        late Map<String, dynamic> sent;
        final client = SuchiClient(
          origin: _origin,
          token: _token,
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/documents/bulk_edit');
            sent = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'method': 'remove_tag',
                'total': 1,
                'applied': 0,
                'results': [
                  {'id': 91, 'ok': false, 'code': 'forbidden'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        await expectLater(
          client.changeDocumentTag(91, tagId: 17, add: false),
          throwsA(
            isA<ApiException>().having(
              (error) => error.code,
              'code',
              'forbidden',
            ),
          ),
        );
        expect(sent, {
          'documents': [91],
          'method': 'remove_tag',
          'parameters': {'tag_id': 17},
        });
      },
    );
  });

  group('public share links', () {
    const shareToken =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    test('creates a link with the exact bounded request contract', () async {
      late http.Request observed;
      final client = SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: MockClient((request) async {
          observed = request;
          return http.Response(
            jsonEncode({
              'id': 7,
              'token': shareToken,
              'public_url': '/s/$shareToken',
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final link = await client.createShareLink(
        documentId: 91,
        label: List.filled(70, '😀').join(),
        expiresInSeconds: 604800,
        password: 'open sesame',
      );

      expect(observed.method, 'POST');
      expect(observed.url.path, '/api/share_links/');
      expect(jsonDecode(observed.body), {
        'doc_ids': [91],
        'label': List.filled(50, '😀').join(),
        'expires_in_sec': 604800,
        'password': 'open sesame',
      });
      expect(link.id, 7);
      expect(link.token, shareToken);
      expect(
        link.publicUrl.toString(),
        'https://suchi.example.com/s/$shareToken',
      );
    });

    test('accepts a matching absolute public URL and rejects mismatches', () {
      final absolute = CreatedShareLink.fromJson({
        'id': 7,
        'token': shareToken,
        'public_url': 'https://public.example/archive/s/$shareToken',
      }, origin: _origin);
      expect(
        absolute.publicUrl.toString(),
        'https://public.example/archive/s/$shareToken',
      );

      for (final url in [
        '/s/${List.filled(64, 'c').join()}',
        'https://user@public.example/s/$shareToken',
        'https://public.example/s/$shareToken?secret=1',
        'share/$shareToken',
      ]) {
        expect(
          () => CreatedShareLink.fromJson({
            'id': 7,
            'token': shareToken,
            'public_url': url,
          }, origin: _origin),
          throwsA(isA<ApiFormatException>()),
        );
      }
    });

    test('adds only the active share filter to document lists', () async {
      late http.Request observed;
      final client = SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: MockClient((request) async {
          observed = request;
          return http.Response(
            jsonEncode({'count': 0, 'results': <Object>[]}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await client.listDocuments(
        page: 2,
        pageSize: 30,
        ordering: '-created_at',
        activeShareLinks: true,
      );

      expect(observed.url.queryParameters, {
        'page': '2',
        'page_size': '30',
        'ordering': '-created_at',
        'share_link': 'active',
      });
    });
  });

  group('Saved View filters', () {
    test('preserves every supported flat and snapshot filter', () {
      final flat = SavedViewFilter.fromJsonString(
        jsonEncode({
          'q': 'quarterly tax',
          'tags__id__in': ['2', 4],
          'correspondents__id__in': '7,9',
          'document_type__id': '11',
          'jd_category_id': 22,
          'sensitivity': 'confidential',
          'ordering': '-updated_at',
        }),
      );
      final snapshot = SavedViewFilter.fromJsonString(
        '{"document_ids":[17,42],"ordering":"title"}',
      );

      expect(flat.queryParameters, {
        'q': 'quarterly tax',
        'tags__id__in': '2,4',
        'correspondents__id__in': '7,9',
        'document_type__id': '11',
        'jd_category_id': '22',
        'sensitivity': 'confidential',
        'ordering': '-updated_at',
      });
      expect(snapshot.queryParameters, {
        'ordering': 'title',
        'document_ids': '17,42',
      });
    });

    test('keeps an unsupported server row visible but unavailable', () {
      final view = SavedView.fromJson({
        'id': 7,
        'name': 'Future scope',
        'filter_json': '{"future_filter":"value"}',
        'display': 'list',
        'position': 0,
        'created_at': 1,
        'updated_at': 1,
      });

      expect(view.available, isFalse);
      expect(view.filter, isNull);
      expect(view.filterError, contains('unsupported filter'));
    });

    test('sends a Saved View scope intact to the document list', () async {
      late http.Request observed;
      final client = SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: MockClient((request) async {
          observed = request;
          return http.Response(
            jsonEncode({'count': 0, 'results': <Object>[]}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final filter = SavedViewFilter.fromJsonString(
        '{"q":"tax","tags__id__in":[2,4],"document_ids":[17,42],"ordering":"title"}',
      );

      await client.listDocuments(
        page: 2,
        pageSize: 30,
        ordering: '-created_at',
        savedViewFilter: filter,
      );

      expect(observed.url.queryParameters, {
        'page': '2',
        'page_size': '30',
        'ordering': 'title',
        'q': 'tax',
        'tags__id__in': '2,4',
        'document_ids': '17,42',
      });
    });
  });

  group('SuchiClient transport boundary', () {
    SuchiClient clientForHandshake(Object? value) => SuchiClient(
      origin: _origin,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

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

    test(
      'accepts undeclared compatibility despite higher release fields',
      () async {
        final handshake = await clientForHandshake({
          'product': 'suchi',
          'api_version': 99,
          'min_app_version': '99.0.0',
        }).handshake();

        expect(handshake.mobileContracts, isNull);
      },
    );

    test('accepts the supported profile alongside a newer one', () async {
      final handshake = await clientForHandshake({
        'product': 'suchi',
        'mobile_contracts': ['suchi-companion-v2', 'suchi-companion-v1'],
      }).handshake();

      expect(handshake.mobileContracts, [
        'suchi-companion-v2',
        'suchi-companion-v1',
      ]);
    });

    test(
      'refuses an explicit declaration without the supported profile',
      () async {
        for (final contracts in [
          <String>[],
          ['suchi-companion-v2'],
        ]) {
          await expectLater(
            clientForHandshake({
              'product': 'suchi',
              'mobile_contracts': contracts,
            }).handshake(),
            throwsA(
              isA<ApiException>().having(
                (error) => error.kind,
                'kind',
                ApiFailureKind.incompatibleServer,
              ),
            ),
          );
        }
      },
    );

    test(
      'rejects malformed contract declarations, not as incompatibility',
      () async {
        for (final contracts in [
          null,
          1,
          ['suchi-companion-v1', 1],
        ]) {
          await expectLater(
            clientForHandshake({
              'product': 'suchi',
              'mobile_contracts': contracts,
            }).handshake(),
            throwsA(
              isA<ApiException>().having(
                (error) => error.kind,
                'kind',
                ApiFailureKind.malformedResponse,
              ),
            ),
          );
        }
      },
    );

    test('refuses a handshake redirect before sending credentials', () async {
      var requests = 0;
      final client = SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: MockClient((request) async {
          requests++;
          expect(request.headers, isNot(contains('Authorization')));
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {'location': 'https://other.example.com/api/handshake'},
          );
        }),
      );

      await expectLater(
        client.handshake(),
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

    test('rejects an incompatible server before accepting it', () async {
      final client = SuchiClient(
        origin: _origin,
        httpClient: MockClient(
          (request) async => http.Response(
            '{"product":"other",'
            '"mobile_contracts":["suchi-companion-v1"]}',
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
