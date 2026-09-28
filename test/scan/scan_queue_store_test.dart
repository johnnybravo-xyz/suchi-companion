import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:suchi_mobile/auth/account_identity.dart';
import 'package:suchi_mobile/scan/intake_limits.dart';
import 'package:suchi_mobile/scan/scan_database.dart';
import 'package:suchi_mobile/scan/scan_queue_store.dart';
import 'package:suchi_mobile/scan/storage_protection.dart';

const _firstId = '11111111-1111-4111-8111-111111111111';
const _secondId = '22222222-2222-4222-8222-222222222222';
const _thirdId = '33333333-3333-4333-8333-333333333333';
const _fourthId = '44444444-4444-4444-8444-444444444444';
final _origin = Uri.parse('https://suchi.example.com');
const _pdf = <int>[0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34, 0x0a];

void main() {
  late Directory temporary;
  late ScanDatabase database;
  late ScanQueueStore store;
  late _RecordingProtection protection;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('suchi-queue-test-');
    database = ScanDatabase(NativeDatabase.memory());
    protection = _RecordingProtection();
    store = await ScanQueueStore.open(
      database: database,
      root: temporary,
      storageProtection: protection,
      storageCapacity: protection,
    );
  });

  tearDown(() async {
    await store.close();
    await database.close();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('stages payload and OCR atomically with frozen metadata', () async {
    final source = await _sourceFile(temporary, 'source.pdf', _pdf);
    final staged = await store.stage(
      StageDocumentInput(
        sourceFile: source,
        mimeType: 'application/pdf',
        filename: 'Camera scan.pdf',
        source: ScanSource.camera,
        pageCount: 2,
        sourceMtime: 1770000000,
        ocr: const DeviceOcrInput(
          content: 'Recognized text',
          confidence: 0.91,
          language: 'en-US',
        ),
        identity: AccountIdentity(origin: _origin, userId: 7, systemId: 1),
      ),
      id: _firstId,
    );

    expect(protection.path, temporary.absolute.path);
    expect(staged.state, 'queued');
    expect(staged.sha256, sha256.convert(_pdf).toString());
    expect(staged.byteSize, _pdf.length);
    expect(staged.identityUserId, 7);
    expect(staged.identityOrigin, _origin.toString());
    expect(staged.identitySystemId, 1);
    expect(await store.payloadFile(staged).readAsBytes(), _pdf);
    expect(await store.readOcr(staged), 'Recognized text');
    expect(await store.storageUsage(), (
      itemCount: 1,
      byteSize: _pdf.length + utf8.encode('Recognized text').length,
    ));
    expect(
      await temporary
          .list()
          .map((entity) => path.basename(entity.path))
          .where((name) => name.endsWith('.part') || name.endsWith('.json'))
          .toList(),
      isEmpty,
    );
  });

  test('keeps a camera receipt after its queued payload is removed', () async {
    const receipt =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final source = await _sourceFile(temporary, 'camera.pdf', _pdf);

    final staged = await store.stage(
      StageDocumentInput(
        sourceFile: source,
        mimeType: 'application/pdf',
        filename: 'Camera scan.pdf',
        source: ScanSource.camera,
        pageCount: 1,
      ),
      id: _firstId,
      captureReceiptId: receipt,
    );

    expect(await store.hasCaptureReceipt(receipt), isTrue);
    await store.removeUpload(staged.id);

    await expectLater(
      store.stage(
        StageDocumentInput(
          sourceFile: source,
          mimeType: 'application/pdf',
          filename: 'Camera scan.pdf',
          source: ScanSource.camera,
          pageCount: 1,
        ),
        id: _secondId,
        captureReceiptId: receipt,
      ),
      throwsA(
        isA<QueueStageException>().having(
          (error) => error.code,
          'code',
          'capture_already_staged',
        ),
      ),
    );
  });

  test(
    'keeps signed-out intake unassigned until identity confirmation',
    () async {
      final source = await _sourceFile(temporary, 'source.pdf', _pdf);
      final staged = await store.stage(
        StageDocumentInput(
          sourceFile: source,
          mimeType: 'application/pdf',
          filename: 'Shared.pdf',
          source: ScanSource.share,
          pageCount: 1,
        ),
        id: _firstId,
      );

      expect(staged.state, 'unassigned');
      await store.assign(
        staged.id,
        identity: AccountIdentity(origin: _origin, userId: 7, systemId: 1),
      );

      final assigned = await database.uploadById(staged.id);
      expect(assigned?.state, 'queued');
      expect(assigned?.identityUserId, 7);
      expect(assigned?.identitySystemId, 1);
    },
  );

  test('shows only unassigned and current-account queue items', () async {
    final source = await _sourceFile(temporary, 'visible.pdf', _pdf);
    final current = AccountIdentity(origin: _origin, userId: 7, systemId: 1);
    final other = AccountIdentity(origin: _origin, userId: 8, systemId: 1);
    final otherSystem = AccountIdentity(
      origin: _origin,
      userId: 7,
      systemId: 2,
    );
    final unassigned = await store.stage(
      StageDocumentInput(
        sourceFile: source,
        mimeType: 'application/pdf',
        filename: 'Unassigned.pdf',
        source: ScanSource.share,
        pageCount: 1,
      ),
      id: _firstId,
    );
    final owned = await store.stage(
      StageDocumentInput(
        sourceFile: source,
        mimeType: 'application/pdf',
        filename: 'Owned.pdf',
        source: ScanSource.camera,
        pageCount: 1,
        identity: current,
      ),
      id: _secondId,
    );
    final hidden = await store.stage(
      StageDocumentInput(
        sourceFile: source,
        mimeType: 'application/pdf',
        filename: 'Hidden.pdf',
        source: ScanSource.camera,
        pageCount: 1,
        identity: other,
      ),
      id: _thirdId,
    );
    final hiddenSystem = await store.stage(
      StageDocumentInput(
        sourceFile: source,
        mimeType: 'application/pdf',
        filename: 'Other system.pdf',
        source: ScanSource.camera,
        pageCount: 1,
        identity: otherSystem,
      ),
      id: _fourthId,
    );

    final visible = visibleQueueUploads(await store.allUploads(), current);

    expect(visible.map((upload) => upload.id), [unassigned.id, owned.id]);
    expect(visible, isNot(contains(hidden)));
    expect(visible, isNot(contains(hiddenSystem)));
    expect(visibleQueueUploads(await store.allUploads(), null), [unassigned]);
  });

  test('rejects MIME confusion and removes partial artifacts', () async {
    final source = await _sourceFile(temporary, 'source.png', _pdf);

    await expectLater(
      store.stage(
        StageDocumentInput(
          sourceFile: source,
          mimeType: 'image/png',
          filename: 'misleading.png',
          source: ScanSource.share,
          pageCount: 1,
        ),
        id: _firstId,
      ),
      throwsA(
        isA<QueueStageException>().having(
          (error) => error.code,
          'code',
          'mime_mismatch',
        ),
      ),
    );

    expect(await database.allUploads(), isEmpty);
    expect(
      await temporary
          .list()
          .map((entity) => path.basename(entity.path))
          .where((name) => name.startsWith(_firstId))
          .toList(),
      isEmpty,
    );
  });

  test('rejects a native receipt checksum mismatch', () async {
    final source = await _sourceFile(temporary, 'source.pdf', _pdf);

    await expectLater(
      store.stage(
        StageDocumentInput(
          sourceFile: source,
          mimeType: 'application/pdf',
          filename: 'Shared.pdf',
          source: ScanSource.share,
          pageCount: 1,
          expectedSize: _pdf.length,
          expectedSha256: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        ),
        id: _firstId,
      ),
      throwsA(
        isA<QueueStageException>().having(
          (error) => error.code,
          'code',
          'payload_changed',
        ),
      ),
    );
  });

  test('low storage leaves the unresolved source untouched', () async {
    final source = await _sourceFile(temporary, 'pending.pdf', _pdf);
    protection.available = minimumFreeStorageReserveBytes;

    await expectLater(
      store.stage(
        StageDocumentInput(
          sourceFile: source,
          mimeType: 'application/pdf',
          filename: 'Pending.pdf',
          source: ScanSource.share,
          pageCount: 1,
        ),
        id: _firstId,
      ),
      throwsA(
        isA<QueueStageException>().having(
          (error) => error.code,
          'code',
          'storage_full',
        ),
      ),
    );

    expect(await source.readAsBytes(), _pdf);
    expect(await database.allUploads(), isEmpty);
    expect(
      await temporary
          .list()
          .map((entity) => path.basename(entity.path))
          .where((name) => name.startsWith(_firstId))
          .toList(),
      isEmpty,
    );
  });

  test('rejects an oversized file before copying a queue payload', () async {
    final source = await _sourceFile(temporary, 'oversized.pdf', _pdf);
    final handle = await source.open(mode: FileMode.append);
    await handle.truncate(maximumDocumentBytes + 1);
    await handle.close();

    await expectLater(
      store.stage(
        StageDocumentInput(
          sourceFile: source,
          mimeType: 'application/pdf',
          filename: 'oversized.pdf',
          source: ScanSource.camera,
          pageCount: 1,
        ),
        id: _firstId,
      ),
      throwsA(
        isA<QueueStageException>().having(
          (error) => error.code,
          'code',
          'payload_too_large',
        ),
      ),
    );

    expect(await database.allUploads(), isEmpty);
    expect(
      await temporary
          .list()
          .map((entity) => path.basename(entity.path))
          .where((name) => name.startsWith(_firstId))
          .toList(),
      isEmpty,
    );
  });

  test('rejects a symbolic-link source', () async {
    final source = await _sourceFile(temporary, 'source.pdf', _pdf);
    final link = Link(path.join(temporary.path, 'source-link.pdf'));
    await link.create(source.path);

    await expectLater(
      store.stage(
        StageDocumentInput(
          sourceFile: File(link.path),
          mimeType: 'application/pdf',
          filename: 'Shared.pdf',
          source: ScanSource.share,
          pageCount: 1,
        ),
        id: _firstId,
      ),
      throwsA(
        isA<QueueStageException>().having(
          (error) => error.code,
          'code',
          'bad_source_file',
        ),
      ),
    );
  });

  test('recovers a flushed manifest and payload missing its DB row', () async {
    final source = await _sourceFile(temporary, 'source.pdf', _pdf);
    final staged = await store.stage(
      StageDocumentInput(
        sourceFile: source,
        mimeType: 'application/pdf',
        filename: 'Recovered.pdf',
        source: ScanSource.camera,
        pageCount: 1,
        identity: AccountIdentity(origin: _origin, userId: 7, systemId: 1),
      ),
      id: _firstId,
    );
    await database.deleteUpload(staged.id);
    final manifest = {
      'version': 1,
      'id': staged.id,
      'payload_path': staged.payloadPath,
      'ocr_content_path': null,
      'ocr_sha256': null,
      'sha256': staged.sha256,
      'byte_size': staged.byteSize,
      'mime_type': staged.mimeType,
      'filename': staged.filename,
      'source_mtime': null,
      'ocr_confidence': null,
      'ocr_language': null,
      'source': staged.source,
      'page_count': staged.pageCount,
      'state': staged.state,
      'identity_user_id': staged.identityUserId,
      'identity_origin': staged.identityOrigin,
      'identity_system_id': staged.identitySystemId,
      'created_at_ms': staged.createdAtMs,
    };
    await File(path.join(temporary.path, '${staged.id}.json'))
        .writeAsString(jsonEncode(manifest), flush: true);

    final report = await store.reconcile();

    expect(report.recovered, 1);
    expect((await database.uploadById(staged.id))?.filename, 'Recovered.pdf');
    expect(
      await File(path.join(temporary.path, '${staged.id}.json')).exists(),
      isFalse,
    );
  });

  test(
    'refuses an incompatible manifest without deleting queued files',
    () async {
      final manifest = File(path.join(temporary.path, '$_firstId.json'));
      final payload = File(path.join(temporary.path, '$_firstId.payload'));
      await manifest.writeAsString(jsonEncode({'version': 2}), flush: true);
      await payload.writeAsBytes(_pdf, flush: true);

      await expectLater(
        store.reconcile(),
        throwsA(isA<UnsupportedLocalStorageException>()),
      );

      expect(await manifest.exists(), isTrue);
      expect(await payload.exists(), isTrue);
    },
  );

  test('demotes interrupted upload and fails a changed payload', () async {
    final source = await _sourceFile(temporary, 'source.pdf', _pdf);
    final staged = await store.stage(
      StageDocumentInput(
        sourceFile: source,
        mimeType: 'application/pdf',
        filename: 'Changed.pdf',
        source: ScanSource.camera,
        pageCount: 1,
        identity: AccountIdentity(origin: _origin, userId: 7, systemId: 1),
      ),
      id: _secondId,
    );
    await (database.update(database.scanUploads)
          ..where((row) => row.id.equals(staged.id)))
        .write(const ScanUploadsCompanion(state: Value('uploading')));
    await store
        .payloadFile(staged)
        .writeAsBytes([..._pdf, 0], mode: FileMode.append, flush: true);

    final report = await store.reconcile();
    final reconciled = await database.uploadById(staged.id);

    expect(report.demoted, 1);
    expect(report.failed, 1);
    expect(reconciled?.state, 'uploadFailed');
    expect(reconciled?.lastErrorCode, 'payload_missing_or_changed');
  });

  test(
    'prunes completed queue history and receipts by age and count',
    () async {
      final now = DateTime.utc(2026, 6, 10);
      for (var index = 0; index < 23; index++) {
        final suffix = index.toString().padLeft(12, '0');
        final id = '00000000-0000-4000-8000-$suffix';
        final completedAt = index == 22
            ? now.subtract(const Duration(days: 31))
            : now.subtract(Duration(minutes: index));
        await database.insertUpload(
          ScanUploadsCompanion.insert(
            id: id,
            payloadPath: '$id.payload',
            sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            byteSize: 1,
            mimeType: 'application/pdf',
            filename: '$index.pdf',
            source: 'camera',
            pageCount: 1,
            state: 'filed',
            createdAtMs: completedAt.millisecondsSinceEpoch,
            updatedAtMs: completedAt.millisecondsSinceEpoch,
            completedAtMs: Value(completedAt.millisecondsSinceEpoch),
          ),
        );
        await database.insertShareReceipt(
          ShareReceiptsCompanion.insert(
            batchId: id,
            itemIndex: 0,
            sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            byteSize: 1,
            mimeType: 'application/pdf',
            queueId: Value(id),
            status: 'staged',
            createdAtMs: completedAt.millisecondsSinceEpoch,
            updatedAtMs: completedAt.millisecondsSinceEpoch,
          ),
        );
        await database.insertCaptureReceipt(
          CaptureReceiptsCompanion.insert(
            captureId: id,
            queueId: id,
            createdAtMs: completedAt.millisecondsSinceEpoch,
          ),
        );
      }
      const failures = {
        '44444444-4444-4444-8444-444444444444': 'uploadFailed',
        '55555555-5555-4555-8555-555555555555': 'processingFailed',
      };
      for (final MapEntry(key: id, value: state) in failures.entries) {
        final failedAt = now.subtract(const Duration(days: 31));
        await database.insertUpload(
          ScanUploadsCompanion.insert(
            id: id,
            payloadPath: '$id.payload',
            sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            byteSize: 1,
            mimeType: 'application/pdf',
            filename: '$state.pdf',
            source: 'camera',
            pageCount: 1,
            state: state,
            createdAtMs: failedAt.millisecondsSinceEpoch,
            updatedAtMs: failedAt.millisecondsSinceEpoch,
            completedAtMs: Value(failedAt.millisecondsSinceEpoch),
          ),
        );
        await File(path.join(temporary.path, '$id.payload'))
            .writeAsBytes(_pdf, flush: true);
      }

      final removed = await store.cleanupCompleted(now: now);
      final remaining = await database.allUploads();
      final successes = remaining
          .where(
            (upload) => upload.state == 'filed' || upload.state == 'duplicate',
          )
          .toList(growable: false);
      final shareReceipts = await database.select(database.shareReceipts).get();
      final captureReceipts = await database
          .select(database.captureReceipts)
          .get();
      final cutoff = now
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;

      expect(removed, 3);
      expect(successes, hasLength(20));
      expect(
        successes.every((upload) => upload.completedAtMs! >= cutoff),
        isTrue,
      );
      expect(shareReceipts, hasLength(20));
      expect(
        shareReceipts.every((receipt) => receipt.updatedAtMs >= cutoff),
        isTrue,
      );
      expect(captureReceipts, hasLength(20));
      expect(
        captureReceipts.every((receipt) => receipt.createdAtMs >= cutoff),
        isTrue,
      );
      expect(
        remaining
            .where((upload) => failures.containsKey(upload.id))
            .map((upload) => upload.state),
        unorderedEquals(failures.values),
      );
      for (final id in failures.keys) {
        expect(
          await File(path.join(temporary.path, '$id.payload')).exists(),
          isTrue,
        );
      }
    },
  );

  test('reconciliation prunes expired transient receipts', () async {
    final expired = DateTime.utc(2020).millisecondsSinceEpoch;
    await database.insertShareReceipt(
      ShareReceiptsCompanion.insert(
        batchId: _firstId,
        itemIndex: 0,
        sha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        byteSize: 1,
        mimeType: 'application/pdf',
        status: 'rejected',
        createdAtMs: expired,
        updatedAtMs: expired,
      ),
    );
    await database.insertCaptureReceipt(
      CaptureReceiptsCompanion.insert(
        captureId: _secondId,
        queueId: _thirdId,
        createdAtMs: expired,
      ),
    );

    await store.reconcile();

    expect(await database.shareReceipt(_firstId, 0), equals(null));
    expect(await database.captureReceipt(_secondId), equals(null));
  });

  test('removes orphaned part files', () async {
    final orphan = File(path.join(temporary.path, 'orphan.payload.part'));
    await orphan.writeAsBytes(_pdf, flush: true);

    final report = await store.reconcile();

    expect(report.removedArtifacts, 1);
    expect(await orphan.exists(), isFalse);
  });
  test('reconciles only abandoned picker claims after one day', () async {
    final owner = AccountIdentity(origin: _origin, userId: 7, systemId: 1);
    final now = DateTime.utc(2026, 3, 12, 12);
    String claim(DateTime createdAt) => jsonEncode({
      'origin': owner.origin.toString(),
      'user_id': owner.userId,
      'system_id': owner.systemId,
      'created_at_ms': createdAt.millisecondsSinceEpoch,
    });

    await database.setSetting(
      'share_picker_claim:$_firstId',
      claim(now.subtract(const Duration(hours: 25))),
    );
    await database.setSetting(
      'share_picker_claim:$_secondId',
      claim(now.subtract(const Duration(hours: 23))),
    );
    await database.setSetting(
      'share_picker_claim:$_thirdId',
      claim(now.subtract(const Duration(days: 2))),
    );

    expect(await store.reconcileShareBatchClaims({_thirdId}, now: now), 1);
    expect(await store.shareBatchClaim(_firstId), equals(null));
    expect(await store.shareBatchClaim(_secondId), owner);
    expect(await store.shareBatchClaim(_thirdId), owner);
  });

  test(
    'claim is durable, account-bound, and corrupt owner fails closed',
    () async {
      await store.close();
      await database.close();

      final owner = AccountIdentity(origin: _origin, userId: 7, systemId: 1);
      final disk = File(path.join(temporary.path, 'claims.sqlite'));
      final first = ScanDatabase(NativeDatabase(disk));
      final firstStore = await ScanQueueStore.open(
        database: first,
        root: Directory(path.join(temporary.path, 'durable-queue')),
        storageProtection: protection,
        storageCapacity: protection,
      );
      final beforeClaim = DateTime.now().toUtc().millisecondsSinceEpoch;
      await firstStore.claimShareBatch(_firstId, owner);
      final encodedClaim = jsonDecode(
        (await first.setting('share_picker_claim:$_firstId'))!,
      ) as Map<String, dynamic>;
      expect(
        encodedClaim.keys,
        unorderedEquals(['origin', 'user_id', 'system_id', 'created_at_ms']),
      );
      expect(encodedClaim['created_at_ms'], greaterThanOrEqualTo(beforeClaim));
      await firstStore.close();
      await first.close();

      final second = ScanDatabase(NativeDatabase(disk));
      final secondStore = await ScanQueueStore.open(
        database: second,
        root: Directory(path.join(temporary.path, 'durable-queue')),
        storageProtection: protection,
        storageCapacity: protection,
      );
      try {
        expect(await secondStore.shareBatchClaim(_firstId), owner);
        await expectLater(
          secondStore.claimShareBatch(_firstId, owner),
          throwsFormatException,
        );
        await second.setSetting(
          'share_picker_claim:$_firstId',
          '{"origin":"https://suchi.example.com","user_id":"7","system_id":1}',
        );
        await expectLater(
          secondStore.shareBatchClaim(_firstId),
          throwsFormatException,
        );
        await secondStore.removeShareBatchClaim(_firstId);
        expect(await secondStore.shareBatchClaim(_firstId), equals(null));
      } finally {
        await secondStore.close();
        await second.close();
      }
    },
  );
}

Future<File> _sourceFile(
  Directory directory,
  String name,
  List<int> bytes,
) async {
  final file = File(path.join(directory.path, name));
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

final class _RecordingProtection implements StorageProtection, StorageCapacity {
  String? path;
  int available = 1 << 60;

  @override
  Future<int> availableBytes(String absolutePath) async => available;

  @override
  Future<void> protectDirectory(String absolutePath) async {
    path = absolutePath;
  }
}
