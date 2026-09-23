import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
import 'package:suchi_mobile/auth/account_identity.dart';
import 'package:suchi_mobile/api/api_error.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/scan/network_monitor.dart';
import 'package:suchi_mobile/scan/scan_database.dart';
import 'package:suchi_mobile/scan/scan_queue_store.dart';
import 'package:suchi_mobile/scan/storage_protection.dart';
import 'package:suchi_mobile/scan/upload_coordinator.dart';

const _id = '11111111-1111-4111-8111-111111111111';
const _pdf = <int>[0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34, 0x0a];
final _origin = Uri.parse('https://suchi.example.com');
const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late Directory temporary;
  late ScanDatabase database;
  late ScanQueueStore store;
  late _FakeNetwork network;
  late DateTime now;
  late SuchiClient client;
  late UploadCoordinator coordinator;
  late AccountIdentity identity;
  late List<ApiException> unauthorized;
  late bool deviceOcrEnabled;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('suchi-uploader-');
    database = ScanDatabase(NativeDatabase.memory());
    store = await ScanQueueStore.open(
      database: database,
      root: Directory(path.join(temporary.path, 'queue')),
      storageProtection: _NoopProtection(),
    );
    network = _FakeNetwork();
    now = DateTime.utc(2026, 6, 1, 12);
    identity = AccountIdentity(origin: _origin, userId: 7, systemId: 1);
    unauthorized = [];
    deviceOcrEnabled = true;
  });

  tearDown(() async {
    await coordinator.pause();
    coordinator.dispose();
    client.close();
    await store.close();
    await database.close();
    await network.close();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  Future<void> configure(http.Client transport) async {
    client = SuchiClient(origin: _origin, token: _token, httpClient: transport);
    coordinator = UploadCoordinator(
      store: store,
      network: network,
      currentClient: () => client,
      currentIdentity: () => identity,
      deviceOcrEnabled: () => deviceOcrEnabled,
      onUnauthorized: (error) async {
        unauthorized.add(error);
        await coordinator.pause();
      },
      now: () => now,
      pollInterval: const Duration(seconds: 2),
    );
  }

  test('accepts a fresh upload, deletes payload, and starts polling', () async {
    final staged = await _stage(store, temporary, identity: identity);
    late http.Request observed;
    await configure(
      MockClient((request) async {
        observed = request;
        return _uploadResponse(
          status: 201,
          digest: staged.sha256,
          size: staged.byteSize,
        );
      }),
    );

    await coordinator.resume();

    final updated = await database.uploadById(staged.id);
    expect(updated?.state, 'processingServer');
    expect(updated?.serverDocumentId, 93);
    expect(updated?.attemptCount, 1);
    expect(
      updated?.nextAttemptAtMs,
      now.add(const Duration(seconds: 2)).millisecondsSinceEpoch,
    );
    expect(observed.headers['Idempotency-Key'], staged.id);
    expect(await store.payloadFile(staged).exists(), isFalse);
  });

  test('marks server deduplication terminal without polling', () async {
    final staged = await _stage(store, temporary, identity: identity);
    await configure(
      MockClient(
        (request) async => _uploadResponse(
          status: 200,
          digest: staged.sha256,
          size: staged.byteSize,
          extra: {'deduplicated': true},
        ),
      ),
    );

    await coordinator.resume();

    final updated = await database.uploadById(staged.id);
    expect(updated?.state, 'duplicate');
    expect(updated?.deduplicated, isTrue);
    expect(updated?.completedAtMs, now.millisecondsSinceEpoch);
    expect(await store.payloadFile(staged).exists(), isFalse);
  });

  test('backs off a retryable failure and retains the payload', () async {
    final staged = await _stage(store, temporary, identity: identity);
    await configure(
      MockClient(
        (request) async => http.Response(
          '{"code":"busy","message":"Try later"}',
          503,
          headers: {
            'content-type': 'application/json',
            'x-request-id': 'busy-1',
          },
        ),
      ),
    );

    await coordinator.resume();

    final updated = await database.uploadById(staged.id);
    expect(updated?.state, 'queued');
    expect(updated?.attemptCount, 1);
    expect(
      updated?.nextAttemptAtMs,
      now.add(const Duration(seconds: 5)).millisecondsSinceEpoch,
    );
    expect(updated?.requestId, 'busy-1');
    expect(await store.payloadFile(staged).exists(), isTrue);
  });

  test('omits queued device OCR when server-only OCR is enabled', () async {
    const recognizedText = 'private offline recognition';
    final staged = await _stage(
      store,
      temporary,
      identity: identity,
      ocr: const DeviceOcrInput(
        content: recognizedText,
        confidence: 0.9,
        language: 'en-US',
      ),
    );
    deviceOcrEnabled = false;
    late String requestBody;
    await configure(
      MockClient((request) async {
        requestBody = request.body;
        return _uploadResponse(
          status: 201,
          digest: staged.sha256,
          size: staged.byteSize,
        );
      }),
    );

    await coordinator.resume();

    expect(requestBody, isNot(contains(recognizedText)));
    expect(requestBody, isNot(contains('content_source')));
  });

  test(
    'recovers an unexpected upload exception without stranding the row',
    () async {
      final staged = await _stage(store, temporary, identity: identity);
      await configure(
        MockClient((request) async {
          throw StateError('transport adapter failed');
        }),
      );

      await coordinator.resume();

      final updated = await database.uploadById(staged.id);
      expect(updated?.state, 'queued');
      expect(updated?.attemptCount, 1);
      expect(updated?.lastErrorCode, 'unexpected_upload_failure');
      expect(
        updated?.nextAttemptAtMs,
        now.add(const Duration(seconds: 5)).millisecondsSinceEpoch,
      );
      expect(await store.payloadFile(staged).exists(), isTrue);
      expect(coordinator.isRunning, isFalse);
    },
  );

  test('uses the complete capped retry schedule', () async {
    await _stage(store, temporary, identity: identity);
    var requests = 0;
    await configure(
      MockClient((request) async {
        requests++;
        return http.Response(
          '{"code":"busy","message":"Try later"}',
          503,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    const expected = [
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(minutes: 1),
      Duration(minutes: 5),
      Duration(minutes: 15),
      Duration(hours: 1),
    ];

    await coordinator.resume();
    for (var index = 0; index < expected.length; index++) {
      final upload = (await database.allUploads()).single;
      expect(
        upload.nextAttemptAtMs! - now.millisecondsSinceEpoch,
        expected[index].inMilliseconds,
      );
      if (index < expected.length - 1) {
        now = DateTime.fromMillisecondsSinceEpoch(
          upload.nextAttemptAtMs! + 1,
          isUtc: true,
        );
        await coordinator.processNow();
      }
    }
    expect(requests, expected.length);
  });

  test('honors bounded Retry-After over the local backoff', () async {
    final staged = await _stage(store, temporary, identity: identity);
    await configure(
      MockClient(
        (request) async => http.Response(
          '{"code":"rate_limited","message":"Try later"}',
          429,
          headers: {'content-type': 'application/json', 'retry-after': '30'},
        ),
      ),
    );

    await coordinator.resume();

    final updated = await database.uploadById(staged.id);
    expect(
      updated?.nextAttemptAtMs,
      now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
    );
  });

  test('expires on 401 without deleting the queued payload', () async {
    final staged = await _stage(store, temporary, identity: identity);
    await configure(
      MockClient(
        (request) async => http.Response(
          '{"code":"unauthorized","message":"Unauthorized"}',
          401,
          headers: {
            'content-type': 'application/json',
            'x-request-id': 'auth-1',
          },
        ),
      ),
    );

    await coordinator.resume();
    await Future<void>.delayed(Duration.zero);

    final updated = await database.uploadById(staged.id);
    expect(unauthorized, hasLength(1));
    expect(coordinator.isActive, isFalse);
    expect(updated?.state, 'queued');
    expect(updated?.requestId, 'auth-1');
    expect(await store.payloadFile(staged).exists(), isTrue);
  });

  test(
    'makes idempotency conflict terminal and can re-stage a new key',
    () async {
      final staged = await _stage(store, temporary, identity: identity);
      await configure(
        MockClient(
          (request) async => http.Response(
            '{"code":"idempotency_conflict","message":"Conflict"}',
            409,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      await coordinator.resume();
      await coordinator.pause();
      final failed = await database.uploadById(staged.id);
      final replacement = await coordinator.restageConflict(staged.id);

      expect(failed?.state, 'uploadFailed');
      expect(failed?.lastErrorCode, 'idempotency_conflict');
      expect(replacement.id, isNot(staged.id));
      expect(replacement.state, 'queued');
      expect(await database.uploadById(staged.id), isNull);
      expect(await store.payloadFile(replacement).exists(), isTrue);
    },
  );

  test('polls a completed normal document to filed', () async {
    final staged = await _stage(store, temporary, identity: identity);
    await configure(
      MockClient((request) async {
        if (request.method == 'POST') {
          return _uploadResponse(
            status: 201,
            digest: staged.sha256,
            size: staged.byteSize,
          );
        }
        if (request.url.path == '/api/tasks/') return _emptyTasks();
        if (request.url.path == '/api/documents/') return _emptyPage();
        if (request.url.path == '/api/documents/93') {
          final detail = jsonDecode(
            _fixture('document-detail.json'),
          ) as Map<String, dynamic>;
          detail['id'] = 93;
          return _jsonResponse(detail);
        }
        return http.Response('{}', 404);
      }),
    );
    await coordinator.resume();
    now = now.add(const Duration(seconds: 3));

    await coordinator.processNow();

    final updated = await database.uploadById(staged.id);
    expect(updated?.state, 'filed');
    expect(updated?.split, isFalse);
    expect(updated?.completedAtMs, now.millisecondsSinceEpoch);
  });

  test('retries an unexpected processing exception in place', () async {
    final staged = await _stage(store, temporary, identity: identity);
    await configure(
      MockClient((request) async {
        if (request.method == 'POST') {
          return _uploadResponse(
            status: 201,
            digest: staged.sha256,
            size: staged.byteSize,
          );
        }
        throw StateError('poll adapter failed');
      }),
    );
    await coordinator.resume();
    now = now.add(const Duration(seconds: 3));

    await coordinator.processNow();

    final updated = await database.uploadById(staged.id);
    expect(updated?.state, 'processingServer');
    expect(updated?.lastErrorCode, 'unexpected_processing_failure');
    expect(
      updated?.nextAttemptAtMs,
      now.add(const Duration(seconds: 5)).millisecondsSinceEpoch,
    );
    expect(updated?.serverDocumentId, 93);
  });

  test('waits for all split pages then stores every child ID', () async {
    final staged = await _stage(store, temporary, identity: identity);
    final pages = <int>[];
    await configure(
      MockClient((request) async {
        if (request.method == 'POST') {
          return _uploadResponse(
            status: 201,
            digest: staged.sha256,
            size: staged.byteSize,
          );
        }
        if (request.url.path == '/api/tasks/') return _emptyTasks();
        if (request.url.path == '/api/documents/') {
          final page = int.parse(request.url.queryParameters['page']!);
          pages.add(page);
          return _jsonResponse({
            'count': 2,
            'next': null,
            'previous': null,
            'results': [
              if (page == 1)
                _summary(101, splitOriginId: 93, splitIndex: 0)
              else
                _summary(102, splitOriginId: 93, splitIndex: 1),
            ],
          });
        }
        return http.Response('{}', 404);
      }),
    );
    await coordinator.resume();
    now = now.add(const Duration(seconds: 3));

    await coordinator.processNow();

    final updated = await database.uploadById(staged.id);
    expect(updated?.state, 'filed');
    expect(updated?.split, isTrue);
    expect(jsonDecode(updated!.splitDocumentIds!) as List, [101, 102]);
    expect(pages, [1, 2]);
  });

  test('surfaces a dead post-ingest task as processing failure', () async {
    final staged = await _stage(store, temporary, identity: identity);
    await configure(
      MockClient((request) async {
        if (request.method == 'POST') {
          return _uploadResponse(
            status: 201,
            digest: staged.sha256,
            size: staged.byteSize,
          );
        }
        return _jsonResponse({
          'counts': {'pending': 0, 'running': 0, 'done': 0, 'dead': 1},
          'results': [
            {
              'id': 44,
              'kind': 'post-ingest',
              'state': 'dead',
              'attempts': 5,
              'doc_id': 93,
              'last_error': 'OCR failed',
              'created_at': 1,
              'updated_at': 2,
            },
          ],
        });
      }),
    );
    await coordinator.resume();
    now = now.add(const Duration(seconds: 3));

    await coordinator.processNow();

    final updated = await database.uploadById(staged.id);
    expect(updated?.state, 'processingFailed');
    expect(updated?.serverTaskId, 44);
    expect(updated?.lastErrorMessage, 'OCR failed');
  });

  test('never uploads a row assigned to another filing system', () async {
    final other = AccountIdentity(origin: _origin, userId: 7, systemId: 2);
    final staged = await _stage(store, temporary, identity: other);
    var requests = 0;
    await configure(
      MockClient((request) async {
        requests++;
        return http.Response('{}', 500);
      }),
    );

    await coordinator.resume();

    expect(requests, 0);
    expect((await database.uploadById(staged.id))?.state, 'queued');
  });

  test('allows only one upload in flight', () async {
    await _stage(store, temporary, identity: identity);
    final entered = Completer<void>();
    final release = Completer<void>();
    var requests = 0;
    await configure(
      MockClient((request) async {
        requests++;
        entered.complete();
        await release.future;
        return http.Response(
          '{"code":"busy","message":"Try later"}',
          503,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final first = coordinator.resume();
    await entered.future;
    await coordinator.processNow();
    expect(requests, 1);
    release.complete();
    await first;
  });
}

Future<ScanUpload> _stage(
  ScanQueueStore store,
  Directory temporary, {
  required AccountIdentity identity,
  DeviceOcrInput? ocr,
}) async {
  final source = File(
    path.join(
      temporary.path,
      'source-${DateTime.now().microsecondsSinceEpoch}.pdf',
    ),
  );
  await source.writeAsBytes(_pdf, flush: true);
  return store.stage(
    StageDocumentInput(
      sourceFile: source,
      mimeType: 'application/pdf',
      filename: 'Camera scan.pdf',
      source: ScanSource.camera,
      pageCount: 1,
      ocr: ocr,
      identity: identity,
    ),
    id: _id,
  );
}

http.Response _uploadResponse({
  required int status,
  required String digest,
  required int size,
  Map<String, Object?> extra = const {},
}) => _jsonResponse(
  {
    'id': 93,
    'sha256': digest,
    'size': size,
    'mime_type': 'application/pdf',
    'title': 'Camera scan',
    ...extra,
  },
  status: status,
  headers: {'location': '/api/documents/93'},
);

http.Response _emptyTasks() => _jsonResponse({
  'counts': {'pending': 0, 'running': 0, 'done': 1, 'dead': 0},
  'results': <Object>[],
});

http.Response _emptyPage() => _jsonResponse({
  'count': 0,
  'next': null,
  'previous': null,
  'results': <Object>[],
});

Map<String, Object?> _summary(
  int id, {
  required int splitOriginId,
  required int splitIndex,
}) => {
  'id': id,
  'title': 'Split $splitIndex',
  'mime_type': 'application/pdf',
  'split_origin_id': splitOriginId,
  'split_index': splitIndex,
  'created_at': 1,
  'updated_at': 1,
  'tags': <String>[],
  'correspondents': <String>[],
};

http.Response _jsonResponse(
  Object body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json', ...headers},
);

String _fixture(String name) =>
    File('test/fixtures/api/v1/$name').readAsStringSync();

final class _FakeNetwork implements NetworkMonitor {
  bool online = true;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  Future<bool> isOnline() async => online;

  Future<void> close() => _changes.close();
}

final class _NoopProtection implements StorageProtection {
  @override
  Future<void> protectDirectory(String absolutePath) async {}
}
