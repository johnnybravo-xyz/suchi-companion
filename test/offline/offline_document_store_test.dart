import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/api_error.dart';
import 'package:suchi_mobile/api/api_models.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/auth/account_identity.dart';
import 'package:suchi_mobile/detail/document_files.dart';
import 'package:suchi_mobile/offline/offline_document_store.dart';
import 'package:suchi_mobile/scan/storage_protection.dart';

void main() {
  late Directory temporary;
  late Directory root;
  late DocumentFiles files;
  late _RecordingProtection protection;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('suchi-offline-test-');
    root = Directory('${temporary.path}/offline');
    files = DocumentFiles(
      root: await Directory('${temporary.path}/exports').create(),
    );
    protection = _RecordingProtection();
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('commits a full download last and discovers it after restart', () async {
    final requests = <http.Request>[];
    final bytes = utf8.encode('%PDF-offline');
    final store = await _openStore(
      root,
      files,
      protection,
      uuids: [_uuid(1)],
      now: DateTime.utc(2026, 9, 12, 10),
    );
    final entry = await store.save(
      identity: _identity,
      document: _document(size: bytes.length),
      client: _client((request) async {
        requests.add(request);
        return _download(bytes);
      }),
    );

    expect(protection.paths, [root.absolute.path]);
    expect(requests.single.url.path, '/api/documents/91/download');
    expect(requests.single.url.queryParameters, isEmpty);
    expect(requests.single.headers['Authorization'], 'Token ${'a' * 64}');
    expect(await entry.payload.readAsBytes(), bytes);
    expect(
      entry.directory
          .listSync()
          .map((item) => item.uri.pathSegments.last)
          .toSet(),
      {'document-91.pdf', 'manifest.json'},
    );
    final manifest = jsonDecode(
      await File('${entry.directory.path}/manifest.json').readAsString(),
    ) as Map<String, dynamic>;
    expect(manifest['identity_origin'], _identity.origin.toString());
    expect(manifest['identity_user_id'], _identity.userId);
    expect(manifest['identity_system_id'], _identity.systemId);
    expect(manifest['payload_filename'], 'document-91.pdf');
    expect(manifest['byte_size'], bytes.length);
    expect((manifest['document'] as Map)['original_blob'], 'b' * 64);
    expect((manifest['document'] as Map)['content'], '');

    await store.close();
    final restored = await OfflineDocumentStore.open(
      files: files,
      root: root,
      storageProtection: protection,
    );
    addTearDown(restored.close);
    final recovered = restored.find(_identity, 91);
    expect(recovered, isNotNull);
    expect(recovered!.document.title, 'Quarterly report');
    expect(await recovered.payload.readAsBytes(), bytes);
  });

  test(
    'saving progress follows staged bytes, not the committed copy',
    () async {
      final chunks = StreamController<List<int>>();
      final halfWritten = Completer<void>();
      var finalizingBeforeCommit = false;
      final store = await _openStore(
        root,
        files,
        protection,
        uuids: [_uuid(1)],
      );
      addTearDown(store.close);
      store.addListener(() {
        if (store.savingProgress == 0.5 && !halfWritten.isCompleted) {
          halfWritten.complete();
        }
        if (store.savingFinishing && store.find(_identity, 91) == null) {
          finalizingBeforeCommit = true;
        }
      });
      final save = store.save(
        identity: _identity,
        document: _document(size: 6),
        client: SuchiClient(
          origin: _identity.origin,
          token: 'a' * 64,
          httpClient: MockClient.streaming(
            (_, _) async => http.StreamedResponse(
              chunks.stream,
              200,
              contentLength: 6,
              headers: {'content-type': 'application/pdf'},
            ),
          ),
        ),
      );

      chunks.add([1, 2, 3]);
      await halfWritten.future;
      expect(store.savingIdentity, _identity);
      expect(store.savingProgress, 0.5);
      expect(store.find(_identity, 91), isNull);
      chunks.add([4, 5, 6]);
      await chunks.close();
      final saved = await save;
      expect(finalizingBeforeCommit, isTrue);
      expect(await saved.payload.readAsBytes(), [1, 2, 3, 4, 5, 6]);
      expect(store.savingIdentity, isNull);
      expect(store.savingProgress, isNull);
    },
  );

  test(
    'saved payload reaches the native viewer directly and survives refusal',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('test.suchi/offline-handoff');
      final calls = <MethodCall>[];
      var refuse = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (refuse) throw PlatformException(code: 'viewer_unavailable');
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final protectedFiles = DocumentFiles(
        root: await Directory('${temporary.path}/exports').create(),
        channel: channel,
      );
      final store = await _openStore(
        root,
        protectedFiles,
        protection,
        uuids: [_uuid(1)],
      );
      addTearDown(store.close);
      final bytes = utf8.encode('%PDF-offline');
      final entry = await store.save(
        identity: _identity,
        document: _document(size: bytes.length),
        client: _client((_) async => _download(bytes)),
      );

      await store.handoff(identity: _identity, entry: entry, share: false);
      expect(calls.single.method, 'open');
      expect((calls.single.arguments as Map)['path'], entry.payload.path);
      expect((calls.single.arguments as Map)['mime_type'], 'application/pdf');
      expect(
        entry.payload.path,
        endsWith('/offline-${_uuid(1)}/document-91.pdf'),
      );
      expect(await entry.payload.readAsBytes(), bytes);

      refuse = true;
      await expectLater(
        store.handoff(identity: _identity, entry: entry, share: false),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'viewer_unavailable',
          ),
        ),
      );
      expect(await entry.payload.readAsBytes(), bytes);
      expect(
        () =>
            store.handoff(identity: _otherIdentity, entry: entry, share: false),
        throwsA(
          isA<OfflineDocumentException>().having(
            (error) => error.code,
            'code',
            'offline_account',
          ),
        ),
      );
      expect(calls, hasLength(2));
    },
  );

  test('refuses a linked offline storage root', () async {
    final outside = await Directory('${temporary.path}/outside').create();
    await Link(root.path).create(outside.path);

    await expectLater(
      OfflineDocumentStore.open(
        files: files,
        root: root,
        storageProtection: protection,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await outside.exists(), isTrue);
  });

  test(
    'keeps account scopes separate and clears only the selected account',
    () async {
      final bytes = utf8.encode('%PDF-a');
      final store = await _openStore(
        root,
        files,
        protection,
        uuids: [_uuid(1), _uuid(2)],
      );
      addTearDown(store.close);
      final first = await store.save(
        identity: _identity,
        document: _document(size: bytes.length),
        client: _client((_) async => _download(bytes)),
      );
      final second = await store.save(
        identity: _otherIdentity,
        document: _document(id: 92, size: bytes.length),
        client: _client((_) async => _download(bytes)),
      );
      await _copyDirectory(
        first.directory,
        Directory('${root.path}/offline-${_uuid(3)}'),
      );

      expect(store.entriesFor(_identity).map((item) => item.document.id), [91]);
      expect(store.entriesFor(_otherIdentity).map((item) => item.document.id), [
        92,
      ]);
      await store.clearAccount(_identity);
      expect(store.entriesFor(_identity), isEmpty);
      expect(store.entriesFor(_otherIdentity).map((item) => item.document.id), [
        92,
      ]);
      expect(
        await store.entriesFor(_otherIdentity).single.payload.exists(),
        isTrue,
      );
      expect(root.listSync().whereType<Directory>().map((item) => item.path), [
        second.directory.path,
      ]);
    },
  );

  test('removal also deletes an older hidden duplicate', () async {
    final bytes = utf8.encode('%PDF-duplicate');
    final store = await _openStore(root, files, protection, uuids: [_uuid(1)]);
    addTearDown(store.close);
    final entry = await store.save(
      identity: _identity,
      document: _document(size: bytes.length),
      client: _client((_) async => _download(bytes)),
    );
    await _copyDirectory(
      entry.directory,
      Directory('${root.path}/offline-${_uuid(2)}'),
    );

    await store.remove(_identity, entry.document.id);

    expect(store.entriesFor(_identity), isEmpty);
    expect(root.listSync(), isEmpty);
  });

  test('refuses to hand an entry to a different account', () async {
    final bytes = utf8.encode('%PDF-account');
    final store = await _openStore(root, files, protection, uuids: [_uuid(1)]);
    addTearDown(store.close);
    final entry = await store.save(
      identity: _identity,
      document: _document(size: bytes.length),
      client: _client((_) async => _download(bytes)),
    );

    expect(
      () => store.handoff(identity: _otherIdentity, entry: entry, share: false),
      throwsA(
        isA<OfflineDocumentException>().having(
          (error) => error.code,
          'code',
          'offline_account',
        ),
      ),
    );
  });

  test(
    'failed changed-hash update retains the previous verified copy',
    () async {
      final original = utf8.encode('%PDF-old');
      final store = await _openStore(
        root,
        files,
        protection,
        uuids: [_uuid(1), _uuid(2)],
      );
      addTearDown(store.close);
      final first = await store.save(
        identity: _identity,
        document: _document(size: original.length),
        client: _client((_) async => _download(original)),
      );

      await expectLater(
        store.save(
          identity: _identity,
          document: _document(size: original.length, blob: 'c' * 64),
          client: _client((_) async => _download(utf8.encode('short'))),
        ),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.malformedResponse,
          ),
        ),
      );

      final retained = store.find(_identity, 91);
      expect(retained, isNotNull);
      expect(retained!.document.originalBlob, 'b' * 64);
      expect(retained.directory.path, first.directory.path);
      expect(await retained.payload.readAsBytes(), original);
      expect(root.listSync().whereType<Directory>().map((item) => item.path), [
        first.directory.path,
      ]);
    },
  );

  test('account clear cancels staging and prevents a late publish', () async {
    final requested = Completer<void>();
    final response = Completer<http.Response>();
    final store = await _openStore(root, files, protection, uuids: [_uuid(1)]);
    addTearDown(store.close);
    final bytes = utf8.encode('%PDF-cancel');
    final save = store.save(
      identity: _identity,
      document: _document(size: bytes.length),
      client: _client((_) {
        requested.complete();
        return response.future;
      }),
    );
    final saveCancelled = expectLater(
      save,
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.cancelled,
        ),
      ),
    );
    await requested.future;
    final clear = store.clearAccount(_identity);
    expect(store.savingIdentity, isNull);
    expect(store.savingProgress, isNull);
    response.complete(_download(bytes));

    await saveCancelled;
    await clear;
    expect(store.entriesFor(_identity), isEmpty);
    expect(root.listSync(), isEmpty);
  });

  test('rejects the size cap before requesting bytes', () async {
    var requested = false;
    final store = await _openStore(root, files, protection, uuids: [_uuid(1)]);
    addTearDown(store.close);

    await expectLater(
      store.save(
        identity: _identity,
        document: _document(size: offlineDocumentByteLimit + 1),
        client: _client((_) async {
          requested = true;
          return _download(const [1]);
        }),
      ),
      throwsA(
        isA<OfflineDocumentException>().having(
          (error) => error.code,
          'code',
          'offline_size',
        ),
      ),
    );
    expect(requested, isFalse);
    expect(root.listSync(), isEmpty);
  });

  test(
    'startup keeps the newest duplicate and removes unsafe entries',
    () async {
      final bytes = utf8.encode('%PDF-reconcile');
      final store = await _openStore(
        root,
        files,
        protection,
        uuids: [_uuid(1)],
        now: DateTime.utc(2026, 9, 12, 10),
      );
      final first = await store.save(
        identity: _identity,
        document: _document(size: bytes.length),
        client: _client((_) async => _download(bytes)),
      );
      await store.close();

      final newer = Directory('${root.path}/offline-${_uuid(2)}');
      await _copyDirectory(first.directory, newer);
      final newerManifest = File('${newer.path}/manifest.json');
      final manifest = jsonDecode(
        await newerManifest.readAsString(),
      ) as Map<String, dynamic>;
      manifest['saved_at'] = (manifest['saved_at'] as int) + 60;
      await newerManifest.writeAsString(jsonEncode(manifest), flush: true);

      await Directory('${root.path}/offline-${_uuid(3)}.part').create();
      final malformed = await Directory('${root.path}/offline-${_uuid(4)}')
          .create();
      await File('${malformed.path}/manifest.json').writeAsString('{}');
      await File('${root.path}/unexpected.txt').writeAsString('not an entry');
      final outside = await File('${temporary.path}/outside.pdf')
          .writeAsString('private');
      await Link('${root.path}/linked').create(outside.path);

      final restored = await OfflineDocumentStore.open(
        files: files,
        root: root,
        storageProtection: protection,
      );
      addTearDown(restored.close);

      final entries = restored.entriesFor(_identity);
      expect(entries, hasLength(1));
      expect(entries.single.directory.path, newer.path);
      expect(root.listSync().map((item) => item.path), [newer.path]);
    },
  );
}

final _identity = AccountIdentity(
  origin: Uri.parse('https://suchi.example.com'),
  userId: 7,
  systemId: 11,
);
final _otherIdentity = AccountIdentity(
  origin: Uri.parse('https://suchi.example.com'),
  userId: 8,
  systemId: 11,
);
Future<OfflineDocumentStore> _openStore(
  Directory root,
  DocumentFiles files,
  StorageProtection protection, {
  required List<String> uuids,
  DateTime? now,
}) {
  final remaining = uuids.iterator;
  return OfflineDocumentStore.open(
    files: files,
    root: root,
    storageProtection: protection,
    now: () => now ?? DateTime.utc(2026, 9, 12, 12),
    newUuid: () {
      if (!remaining.moveNext()) throw StateError('No UUID prepared for test');
      return remaining.current;
    },
  );
}

SuchiClient _client(Future<http.Response> Function(http.Request) handler) =>
    SuchiClient(
      origin: Uri.parse('https://suchi.example.com'),
      token: 'a' * 64,
      httpClient: MockClient(handler),
    );

http.Response _download(List<int> bytes) => http.Response.bytes(
  bytes,
  200,
  headers: {'content-type': 'application/pdf'},
);

DocumentDetail _document({int id = 91, required int size, String blob = ''}) =>
    DocumentDetail.fromJson({
      'id': id,
      'title': 'Quarterly report',
      'mime_type': 'application/pdf',
      'original_size': size,
      'original_blob': blob.isEmpty ? 'b' * 64 : blob,
      'jd_category_id': 31,
      'jd_category_code': 31,
      'jd_category_name': 'Utilities',
      'jd_area_name': 'Home',
      'sensitivity': '',
      'created_at': 100,
      'added_at': 110,
      'updated_at': 120,
      'source_mtime': 90,
      'trashed_at': null,
      'sources': [
        {
          'kind': 'email',
          'label': 'Email attachment',
          'detail': 'report.pdf',
          'observed_at': 95,
        },
      ],
      'tags': ['tax', 'quarterly'],
      'correspondents': [
        {'id': 3, 'name': 'Accountant', 'role': 'sender'},
      ],
      'languages': 'eng',
      'languages_locked': true,
      'content': '',
    });

String _uuid(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list()) {
    if (entity is File) {
      await entity.copy('${destination.path}/${entity.uri.pathSegments.last}');
    }
  }
}

final class _RecordingProtection implements StorageProtection {
  final paths = <String>[];

  @override
  Future<void> protectDirectory(String path) async => paths.add(path);
}
