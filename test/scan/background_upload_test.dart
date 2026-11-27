import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
import 'package:suchi_companion/api/api_models.dart';
import 'package:suchi_companion/api/suchi_client.dart';
import 'package:suchi_companion/auth/account_identity.dart';
import 'package:suchi_companion/auth/credential_vault.dart';
import 'package:suchi_companion/scan/background_upload.dart';
import 'package:suchi_companion/scan/scan_database.dart';
import 'package:suchi_companion/scan/scan_queue_store.dart';
import 'package:suchi_companion/scan/storage_protection.dart';

const _pdf = <int>[0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34, 0x0a];
const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _origin = Uri.parse('https://suchi.example.com');
final _identity = AccountIdentity(origin: _origin, userId: 7, systemId: 1);

void main() {
  late Directory temporary;
  late ScanDatabase database;
  late ScanQueueStore queue;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('suchi-background-');
    database = ScanDatabase(NativeDatabase.memory());
    queue = await ScanQueueStore.open(
      database: database,
      root: Directory(path.join(temporary.path, 'queue')),
      storageProtection: const _NoopProtection(),
      storageCapacity: const _NoopProtection(),
    );
  });

  tearDown(() async {
    await queue.close();
    await database.close();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('schedules account-bound work only after the app backgrounds', () async {
    await _stage(queue, temporary, _identity);
    await _stage(
      queue,
      temporary,
      AccountIdentity(origin: _origin, userId: 8, systemId: 1),
    );
    final gateway = _FakeGateway();
    final scheduler = BackgroundUploadScheduler(
      queue: queue,
      gateway: gateway,
      platform: BackgroundUploadPlatform.android,
      now: () => DateTime.utc(2026, 11, 2, 12),
    );
    addTearDown(scheduler.close);

    await scheduler.start();
    await scheduler.resume(_identity);
    await Future<void>.delayed(Duration.zero);
    expect(gateway.androidDelays, isEmpty);

    await scheduler.onBackgrounded();
    expect(gateway.androidDelays, [Duration.zero]);

    await scheduler.pause();
    expect(gateway.cancellations, 1);
  });

  test(
    'submits a concrete iOS continuation while the app is foregrounded',
    () async {
      final gateway = _FakeGateway();
      final scheduler = BackgroundUploadScheduler(
        queue: queue,
        gateway: gateway,
        platform: BackgroundUploadPlatform.ios,
        now: () => DateTime.utc(2026, 11, 2, 12),
      );
      addTearDown(scheduler.close);

      await scheduler.start();
      await scheduler.resume(_identity);
      final staged = await _stage(queue, temporary, _identity);
      await Future<void>.delayed(Duration.zero);
      await scheduler.onForegrounded();

      final taskId = backgroundUploadContinuedTaskIdentifier(staged.id);
      expect(gateway.iosContinuedTaskIds, [taskId]);
      expect(taskId, isNot(endsWith('.*')));
      expect(isBackgroundUploadTask(taskId), isTrue);

      await scheduler.pause();
      expect(gateway.cancellations, 1);
    },
  );

  test(
    'headless worker refuses a queue after account work is paused',
    () async {
      final staged = await _stage(queue, temporary, _identity);
      final gateway = _FakeGateway();
      final scheduler = BackgroundUploadScheduler(
        queue: queue,
        gateway: gateway,
        platform: BackgroundUploadPlatform.android,
      );
      await scheduler.resume(_identity);
      await scheduler.pause();
      await scheduler.close();
      var clients = 0;

      final result = await BackgroundUploadRunner(
        gateway: gateway,
        platform: BackgroundUploadPlatform.android,
        vault: _MemoryVault(
          StoredCredentials(
            origin: _origin,
            token: _token,
            userSnapshot: _user,
          ),
        ),
        openQueue: () async => queue,
        clientFactory: (origin, token) {
          clients++;
          throw StateError('A paused worker must not construct a client.');
        },
      ).run();

      expect(result, isTrue);
      expect(clients, 0);
      expect((await database.uploadById(staged.id))?.state, 'queued');
    },
  );

  test(
    'headless worker verifies origin and identity before uploading',
    () async {
      final staged = await _stage(queue, temporary, _identity);
      final gateway = _FakeGateway();
      final scheduler = BackgroundUploadScheduler(
        queue: queue,
        gateway: gateway,
        platform: BackgroundUploadPlatform.android,
      );
      await scheduler.resume(_identity);
      await scheduler.close();

      final requests = <http.Request>[];
      final transport = _uploadTransport(staged, requests);

      final result = await BackgroundUploadRunner(
        gateway: gateway,
        platform: BackgroundUploadPlatform.android,
        vault: _MemoryVault(
          StoredCredentials(
            origin: _origin,
            token: _token,
            userSnapshot: _user,
          ),
        ),
        openQueue: () async => queue,
        clientFactory: (origin, token) =>
            SuchiClient(origin: origin, token: token, httpClient: transport),
        now: () => DateTime.utc(2026, 11, 2, 12),
      ).run();

      expect(result, isTrue);
      expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        ['GET /api/handshake', 'GET /api/whoami', 'POST /api/documents/'],
      );
      expect((await database.uploadById(staged.id))?.state, 'processingServer');
      expect(gateway.androidDelays.last, const Duration(seconds: 2));
    },
  );

  test(
    'continued worker waits for the foreground lease before taking over',
    () async {
      final staged = await _stage(queue, temporary, _identity);
      final gateway = _FakeGateway();
      final scheduler = BackgroundUploadScheduler(
        queue: queue,
        gateway: gateway,
        platform: BackgroundUploadPlatform.ios,
      );
      await scheduler.resume(_identity);
      await scheduler.close();

      final now = DateTime.utc(2026, 11, 2, 12);
      expect(
        await database.tryAcquireUploadLease(
          owner: 'foreground',
          nowMs: now.millisecondsSinceEpoch,
          expiresAtMs: now
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
        ),
        isTrue,
      );

      final requests = <http.Request>[];
      final transport = _uploadTransport(staged, requests);
      final run = BackgroundUploadRunner(
        gateway: gateway,
        platform: BackgroundUploadPlatform.ios,
        vault: _MemoryVault(
          StoredCredentials(
            origin: _origin,
            token: _token,
            userSnapshot: _user,
          ),
        ),
        openQueue: () async => queue,
        clientFactory: (origin, token) =>
            SuchiClient(origin: origin, token: token, httpClient: transport),
        now: () => now,
      ).run(waitForForegroundTransfer: true);

      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(requests.where((request) => request.method == 'POST'), isEmpty);
      await database.releaseUploadLease('foreground');
      final result = await run;

      expect(result, isTrue);
      expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        ['GET /api/handshake', 'GET /api/whoami', 'POST /api/documents/'],
      );
      expect((await database.uploadById(staged.id))?.state, 'processingServer');
    },
  );
}

const _user = UserSelf(
  kind: 'token',
  userId: 7,
  email: 'person@example.com',
  displayName: 'Person',
  instanceHost: 'suchi.example.com',
  role: 'member',
  authenticatedBy: 'token',
  avatarUrl: null,
  systemId: 1,
  systemName: 'Archive',
  systemCode: 'A01',
  capabilities: [],
  scopes: ['documents:read', 'documents:write'],
);

MockClient _uploadTransport(ScanUpload staged, List<http.Request> requests) =>
    MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/api/handshake') {
        expect(request.headers['Authorization'], isNull);
        return http.Response(
          jsonEncode({
            'product': 'suchi',
            'mobile_contracts': ['suchi-companion-v1'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/whoami') {
        return http.Response(
          jsonEncode(_user.toJson()),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST' && request.url.path == '/api/documents/') {
        return http.Response(
          jsonEncode({
            'id': 93,
            'sha256': staged.sha256,
            'size': staged.byteSize,
            'mime_type': staged.mimeType,
            'title': 'Document',
            'restored': false,
            'deduplicated': false,
          }),
          201,
          headers: {
            'content-type': 'application/json',
            'location': '/api/documents/93',
          },
        );
      }
      return http.Response('{}', 404);
    });

Future<ScanUpload> _stage(
  ScanQueueStore queue,
  Directory temporary,
  AccountIdentity identity,
) async {
  final source = File(
    path.join(
      temporary.path,
      '${identity.userId}-${DateTime.now().microsecondsSinceEpoch}.pdf',
    ),
  );
  await source.writeAsBytes(_pdf, flush: true);
  return queue.stage(
    StageDocumentInput(
      sourceFile: source,
      mimeType: 'application/pdf',
      filename: 'Document.pdf',
      source: ScanSource.camera,
      pageCount: 1,
      identity: identity,
    ),
  );
}

final class _FakeGateway implements BackgroundUploadTaskGateway {
  final androidDelays = <Duration>[];
  final iosProcessingDelays = <Duration>[];
  final iosContinuedTaskIds = <String>[];
  var cancellations = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleAndroid({required Duration delay}) async {
    androidDelays.add(delay);
  }

  @override
  Future<void> scheduleIosProcessing({required Duration delay}) async {
    iosProcessingDelays.add(delay);
  }

  @override
  Future<void> scheduleIosContinued({required String taskId}) async {
    iosContinuedTaskIds.add(taskId);
  }

  @override
  Future<void> cancelUploadTasks() async {
    cancellations++;
  }
}

final class _MemoryVault implements CredentialVault {
  _MemoryVault(this.credentials);

  StoredCredentials? credentials;

  @override
  Future<StoredCredentials?> read() async => credentials;

  @override
  Future<void> save(StoredCredentials credentials) async {
    this.credentials = credentials;
  }

  @override
  Future<void> clear() async {
    credentials = null;
  }
}

final class _NoopProtection implements StorageProtection, StorageCapacity {
  const _NoopProtection();

  @override
  Future<void> protectDirectory(String absolutePath) async {}

  @override
  Future<int> availableBytes(String absolutePath) async => 1 << 40;
}
