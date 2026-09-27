import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../auth/account_identity.dart';
import '../auth/server_origin.dart';

import 'intake_limits.dart';
import 'scan_database.dart';
import 'storage_protection.dart';

enum ScanSource { camera, share }

const terminalShareRejectionCodes = <String>{
  'bad_filename',
  'bad_metadata',
  'bad_source_file',
  'empty_payload',
  'mime_mismatch',
  'payload_changed',
  'payload_too_large',
  'unsupported_mime',
};

bool queueUploadBelongsToIdentity(
  ScanUpload upload,
  AccountIdentity identity,
) => identity.matchesStored(
  origin: upload.identityOrigin,
  userId: upload.identityUserId,
  systemId: upload.identitySystemId,
);

List<ScanUpload> visibleQueueUploads(
  Iterable<ScanUpload> uploads,
  AccountIdentity? identity,
) => List.unmodifiable(
  uploads.where(
    (upload) =>
        upload.state == 'unassigned' ||
        identity != null && queueUploadBelongsToIdentity(upload, identity),
  ),
);

final class DeviceOcrInput {
  const DeviceOcrInput({
    required this.content,
    required this.confidence,
    required this.language,
  });

  final String content;
  final double confidence;
  final String language;
}

final class StageDocumentInput {
  const StageDocumentInput({
    required this.sourceFile,
    required this.mimeType,
    required this.filename,
    required this.source,
    required this.pageCount,
    this.sourceMtime,
    this.ocr,
    this.identity,
    this.expectedSize,
    this.expectedSha256,
  });

  final File sourceFile;
  final String mimeType;
  final String filename;
  final ScanSource source;
  final int pageCount;
  final int? sourceMtime;
  final DeviceOcrInput? ocr;
  final AccountIdentity? identity;
  final int? expectedSize;
  final String? expectedSha256;
}

final class ShareReceiptInput {
  const ShareReceiptInput({required this.batchId, required this.itemIndex});

  final String batchId;
  final int itemIndex;
}

final class QueueStageException implements Exception {
  const QueueStageException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class ReconciliationReport {
  const ReconciliationReport({
    required this.recovered,
    required this.demoted,
    required this.failed,
    required this.removedArtifacts,
  });

  final int recovered;
  final int demoted;
  final int failed;
  final int removedArtifacts;
}

final class ScanQueueStore {
  ScanQueueStore._({
    required this.database,
    required this.root,
    required this._storageCapacity,
    required this._ownsDatabase,
  });

  static const _manifestVersion = 1;
  static const _copyBufferSize = 64 * 1024;
  static const _maximumOcrBytes = 1024 * 1024;
  static const _supportedMimes = <String>{
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif',
  };
  static final _uuid = Uuid();
  static const _shareClaimPrefix = 'share_picker_claim:';
  static Future<void> _reconcileTail = Future<void>.value();

  final ScanDatabase database;
  final Directory root;
  final StorageCapacity _storageCapacity;
  final bool _ownsDatabase;
  bool _closed = false;

  static Future<ScanQueueStore> open({
    ScanDatabase? database,
    Directory? root,
    StorageProtection storageProtection = const NativeStorageProtection(),
    StorageCapacity storageCapacity = const NativeStorageCapacity(),
  }) async {
    if (database == null && root == null) {
      await ScanDatabase.rejectLegacyLocation(
        await getApplicationDocumentsDirectory(),
      );
    }
    final support =
        root ??
        Directory(
          path.join(
            (await getApplicationSupportDirectory()).path,
            'suchi-scan-queue',
          ),
        );
    await support.create(recursive: true);
    await storageProtection.protectDirectory(support.absolute.path);
    final ownsDatabase = database == null;
    final resolvedDatabase = database ?? ScanDatabase.open(support);
    final store = ScanQueueStore._(
      database: resolvedDatabase,
      root: support.absolute,
      storageCapacity: storageCapacity,
      ownsDatabase: ownsDatabase,
    );
    try {
      await store._runSerializedReconciliation();
      return store;
    } catch (_) {
      if (ownsDatabase) await resolvedDatabase.close();
      rethrow;
    }
  }

  Stream<List<ScanUpload>> watchUploads() => database.watchUploads();

  Future<List<ScanUpload>> allUploads() => database.allUploads();

  Future<void> ensureWritableCapacity(int byteCount) async {
    _ensureOpen();
    try {
      await ensureWritableStorage(
        capacity: _storageCapacity,
        path: root.path,
        byteCount: byteCount,
      );
    } on StorageCapacityException {
      throw const QueueStageException(
        'storage_full',
        StorageCapacityException.message,
      );
    }
  }

  Future<bool> hasShareReceipt(String batchId, int itemIndex) async =>
      await database.shareReceipt(batchId, itemIndex) != null;

  Future<bool> hasCaptureReceipt(String captureId) async =>
      await database.captureReceipt(captureId) != null;

  Future<void> claimShareBatch(String batchId, AccountIdentity identity) async {
    _ensureOpen();
    _validateShareClaimId(batchId);
    if (identity.userId <= 0 ||
        identity.systemId <= 0 ||
        !_validQueueOrigin(identity.origin.toString())) {
      throw const FormatException('Share claim identity is invalid.');
    }
    final key = '$_shareClaimPrefix$batchId';
    if (await database.setting(key) != null) {
      throw const FormatException('Share batch already has an owner.');
    }
    await database.setSetting(
      key,
      jsonEncode({
        'origin': identity.origin.toString(),
        'user_id': identity.userId,
        'system_id': identity.systemId,
      }),
    );
  }

  Future<AccountIdentity?> shareBatchClaim(String batchId) async {
    _ensureOpen();
    _validateShareClaimId(batchId);
    final encoded = await database.setting('$_shareClaimPrefix$batchId');
    if (encoded == null) return null;
    try {
      final claim = jsonDecode(encoded);
      if (claim is! Map<String, dynamic> ||
          claim.length != 3 ||
          claim['origin'] is! String ||
          claim['user_id'] is! int ||
          claim['system_id'] is! int ||
          claim['user_id'] <= 0 ||
          claim['system_id'] <= 0 ||
          !_validQueueOrigin(claim['origin'] as String)) {
        throw const FormatException();
      }
      return AccountIdentity(
        origin: Uri.parse(claim['origin'] as String),
        userId: claim['user_id'] as int,
        systemId: claim['system_id'] as int,
      );
    } on FormatException {
      throw const FormatException('Share batch claim is invalid.');
    } on TypeError {
      throw const FormatException('Share batch claim is invalid.');
    }
  }

  Future<void> removeShareBatchClaim(String batchId) async {
    _ensureOpen();
    _validateShareClaimId(batchId);
    await database.deleteSetting('$_shareClaimPrefix$batchId');
  }

  static void _validateShareClaimId(String batchId) {
    if (!_isCanonicalUuidV4(batchId)) {
      throw const FormatException('Share batch id is invalid.');
    }
  }

  Future<void> recordRejectedShareItem({
    required ShareReceiptInput receipt,
    required String sha256,
    required int byteSize,
    required String mimeType,
    required String errorCode,
  }) async {
    _ensureOpen();
    if (!_isCanonicalUuidV4(receipt.batchId) ||
        receipt.itemIndex < 0 ||
        !_supportedMimes.contains(mimeType) ||
        byteSize <= 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
        !terminalShareRejectionCodes.contains(errorCode)) {
      throw const QueueStageException(
        'bad_share_receipt',
        'Share rejection metadata is invalid.',
      );
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await database.insertShareReceiptIfAbsent(
      ShareReceiptsCompanion.insert(
        batchId: receipt.batchId,
        itemIndex: receipt.itemIndex,
        sha256: sha256,
        byteSize: byteSize,
        mimeType: mimeType,
        status: 'rejected',
        errorCode: Value(errorCode),
        createdAtMs: now,
        updatedAtMs: now,
      ),
    );
  }

  Future<ScanUpload> stage(
    StageDocumentInput input, {
    String? id,
    ShareReceiptInput? shareReceipt,
    String? captureReceiptId,
  }) async {
    _ensureOpen();
    _validateInput(input, shareReceipt, captureReceiptId);
    if (shareReceipt != null &&
        await database.shareReceipt(
              shareReceipt.batchId,
              shareReceipt.itemIndex,
            ) !=
            null) {
      throw const QueueStageException(
        'share_already_staged',
        'Shared document was already staged.',
      );
    }
    if (captureReceiptId != null &&
        await database.captureReceipt(captureReceiptId) != null) {
      throw const QueueStageException(
        'capture_already_staged',
        'Camera capture was already staged.',
      );
    }
    final queueId = id ?? _uuid.v4();
    if (!_isCanonicalUuidV4(queueId)) {
      throw const QueueStageException('bad_queue_id', 'Queue id is invalid.');
    }
    if (await database.uploadById(queueId) != null) {
      throw const QueueStageException(
        'queue_id_conflict',
        'Queue id already exists.',
      );
    }
    await ensureWritableCapacity(
      maximumDocumentBytes + _maximumOcrBytes + _maximumOcrBytes,
    );

    final payloadPart = File(path.join(root.path, '$queueId.payload.part'));
    final payload = File(path.join(root.path, '$queueId.payload'));
    final ocrPart = File(path.join(root.path, '$queueId.ocr.part'));
    final ocrFile = File(path.join(root.path, '$queueId.ocr'));
    final manifestPart = File(path.join(root.path, '$queueId.json.part'));
    final manifestFile = File(path.join(root.path, '$queueId.json'));
    var manifestCommitted = false;

    try {
      final copied = await _copyAndHash(input.sourceFile, payloadPart);
      if (copied.size == 0) {
        throw const QueueStageException('empty_payload', 'Document is empty.');
      }
      if (input.expectedSize != null && copied.size != input.expectedSize) {
        throw const QueueStageException(
          'payload_changed',
          'Document size changed while it was staged.',
        );
      }
      if (input.expectedSha256 != null &&
          copied.sha256 != input.expectedSha256) {
        throw const QueueStageException(
          'payload_changed',
          'Document checksum changed while it was staged.',
        );
      }
      final detectedMime = await _detectMime(payloadPart);
      if (detectedMime != input.mimeType) {
        throw const QueueStageException(
          'mime_mismatch',
          'Document contents do not match the declared file type.',
        );
      }

      String? ocrSha256;
      if (input.ocr case final ocr?) {
        final bytes = utf8.encode(ocr.content);
        await _writeAndFlush(ocrPart, bytes);
        ocrSha256 = sha256.convert(bytes).toString();
      }
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final state = input.identity == null ? 'unassigned' : 'queued';
      final manifest = <String, Object?>{
        'version': _manifestVersion,
        'id': queueId,
        'payload_path': path.basename(payload.path),
        'ocr_content_path': input.ocr == null
            ? null
            : path.basename(ocrFile.path),
        'ocr_sha256': ocrSha256,
        'sha256': copied.sha256,
        'byte_size': copied.size,
        'mime_type': input.mimeType,
        'filename': input.filename,
        'source_mtime': input.sourceMtime,
        'ocr_confidence': input.ocr?.confidence,
        'ocr_language': input.ocr?.language,
        'source': input.source.name,
        'share_batch_id': shareReceipt?.batchId,
        'share_item_index': shareReceipt?.itemIndex,
        'capture_receipt_id': captureReceiptId,
        'page_count': input.pageCount,
        'state': state,
        'identity_user_id': input.identity?.userId,
        'identity_origin': input.identity?.origin.toString(),
        'identity_system_id': input.identity?.systemId,
        'created_at_ms': now,
      };
      await _writeAndFlush(manifestPart, utf8.encode(jsonEncode(manifest)));
      await manifestPart.rename(manifestFile.path);
      manifestCommitted = true;
      await payloadPart.rename(payload.path);
      if (input.ocr != null) await ocrPart.rename(ocrFile.path);

      await _insertManifest(_StagingManifest.parse(manifest));
      await _deleteIfExists(manifestFile);
      return (await database.uploadById(queueId))!;
    } on QueueStageException {
      if (!manifestCommitted) {
        await _deleteQueueArtifacts(queueId);
      }
      rethrow;
    } on FileSystemException catch (_) {
      if (!manifestCommitted) {
        await _deleteQueueArtifacts(queueId);
      }
      throw const QueueStageException(
        'storage_failed',
        'Document could not be stored safely on this device.',
      );
    } catch (_) {
      if (!manifestCommitted) {
        await _deleteQueueArtifacts(queueId);
      }
      rethrow;
    }
  }

  File payloadFile(ScanUpload upload) => _relativeFile(upload.payloadPath);

  File? ocrFile(ScanUpload upload) => switch (upload.ocrContentPath) {
    final value? => _relativeFile(value),
    null => null,
  };

  Future<String?> readOcr(ScanUpload upload) async {
    final file = ocrFile(upload);
    if (file == null) return null;
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException();
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty ||
          bytes.length > _maximumOcrBytes ||
          upload.ocrSha256 == null ||
          sha256.convert(bytes).toString() != upload.ocrSha256) {
        throw const FormatException();
      }
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException catch (_) {
      throw const QueueStageException(
        'ocr_changed',
        'Stored device text is missing or changed.',
      );
    } on FileSystemException catch (_) {
      throw const QueueStageException(
        'ocr_changed',
        'Stored device text is missing or changed.',
      );
    }
  }

  Future<bool> verifyPayload(ScanUpload upload) async {
    try {
      final file = payloadFile(upload);
      final inspected = await _hashFile(file);
      return inspected.size == upload.byteSize &&
          inspected.sha256 == upload.sha256 &&
          await _detectMime(file) == upload.mimeType;
    } catch (_) {
      return false;
    }
  }

  Future<void> deletePayloads(ScanUpload upload) async {
    await _deleteIfExists(payloadFile(upload));
    final text = ocrFile(upload);
    if (text != null) await _deleteIfExists(text);
  }

  Future<void> removeUpload(String id) async {
    _ensureOpen();
    await database.deleteUpload(id);
    await _deleteQueueArtifacts(id);
  }

  Future<ScanUpload> restageConflict(
    String id, {
    required AccountIdentity identity,
  }) async {
    final upload = await database.uploadById(id);
    if (upload == null ||
        upload.state != 'uploadFailed' ||
        upload.lastErrorCode != 'idempotency_conflict' ||
        !queueUploadBelongsToIdentity(upload, identity)) {
      throw const QueueStageException(
        'cannot_restage',
        'This upload cannot be staged with a new request key.',
      );
    }
    final text = await readOcr(upload);
    final DeviceOcrInput? ocr;
    if (text == null) {
      ocr = null;
    } else if (upload.ocrConfidence == null || upload.ocrLanguage == null) {
      throw const QueueStageException(
        'ocr_changed',
        'Stored device text metadata is incomplete.',
      );
    } else {
      ocr = DeviceOcrInput(
        content: text,
        confidence: upload.ocrConfidence!,
        language: upload.ocrLanguage!,
      );
    }
    final replacement = await stage(
      StageDocumentInput(
        sourceFile: payloadFile(upload),
        mimeType: upload.mimeType,
        filename: upload.filename,
        source: ScanSource.values.byName(upload.source),
        pageCount: upload.pageCount,
        sourceMtime: upload.sourceMtime,
        ocr: ocr,
        identity: identity,
        expectedSize: upload.byteSize,
        expectedSha256: upload.sha256,
      ),
    );
    await removeUpload(upload.id);
    return replacement;
  }

  Future<int> cleanupCompleted({DateTime? now}) async {
    _ensureOpen();
    final cutoff = (now ?? DateTime.now().toUtc()).subtract(
      const Duration(days: 7),
    );
    final completed =
        (await database.allUploads())
            .where(
              (upload) =>
                  upload.completedAtMs != null &&
                  (upload.state == 'filed' || upload.state == 'duplicate'),
            )
            .toList()
          ..sort(
            (left, right) =>
                right.completedAtMs!.compareTo(left.completedAtMs!),
          );
    final remove = <ScanUpload>[];
    for (var index = 0; index < completed.length; index++) {
      final completedAt = DateTime.fromMillisecondsSinceEpoch(
        completed[index].completedAtMs!,
        isUtc: true,
      );
      if (index >= 20 || completedAt.isBefore(cutoff)) {
        remove.add(completed[index]);
      }
    }
    for (final upload in remove) {
      await removeUpload(upload.id);
    }
    return remove.length;
  }

  Future<void> assign(String id, {required AccountIdentity identity}) async {
    _ensureOpen();
    if (identity.userId <= 0 ||
        identity.systemId <= 0 ||
        !_validQueueOrigin(identity.origin.toString())) {
      throw const QueueStageException(
        'bad_identity',
        'Queue identity is invalid.',
      );
    }
    final upload = await database.uploadById(id);
    if (upload == null || upload.state != 'unassigned') {
      throw const QueueStageException(
        'not_unassigned',
        'Document is not awaiting an identity.',
      );
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (database.update(
      database.scanUploads,
    )..where((row) => row.id.equals(id))).write(
      ScanUploadsCompanion(
        state: const Value('queued'),
        identityUserId: Value(identity.userId),
        identityOrigin: Value(identity.origin.toString()),
        identitySystemId: Value(identity.systemId),
        updatedAtMs: Value(now),
      ),
    );
  }

  Future<ReconciliationReport> reconcile() {
    _ensureOpen();
    return _runSerializedReconciliation();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_ownsDatabase) await database.close();
  }

  Future<ReconciliationReport> _runSerializedReconciliation() {
    final completer = Completer<ReconciliationReport>();
    final previous = _reconcileTail;
    _reconcileTail = () async {
      try {
        await previous;
      } catch (_) {
        // A failed prior store must not permanently block later reconciliation.
      }
      try {
        completer.complete(await _reconcile());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();
    return completer.future;
  }

  Future<void> _insertManifest(_StagingManifest manifest) {
    return database.transaction(() async {
      await database.insertUpload(_companionFromManifest(manifest));
      if (manifest.shareBatchId case final batchId?) {
        await database.insertShareReceipt(
          ShareReceiptsCompanion.insert(
            batchId: batchId,
            itemIndex: manifest.shareItemIndex!,
            sha256: manifest.sha256,
            byteSize: manifest.byteSize,
            mimeType: manifest.mimeType,
            queueId: Value(manifest.id),
            status: 'staged',
            createdAtMs: manifest.createdAtMs,
            updatedAtMs: manifest.createdAtMs,
          ),
        );
      }
      if (manifest.captureReceiptId case final captureId?) {
        await database.insertCaptureReceipt(
          CaptureReceiptsCompanion.insert(
            captureId: captureId,
            queueId: manifest.id,
            createdAtMs: manifest.createdAtMs,
          ),
        );
      }
    });
  }

  Future<ReconciliationReport> _reconcile() async {
    var recovered = 0;
    var demoted = 0;
    var failed = 0;
    var removedArtifacts = 0;

    final entities = await root.list(followLinks: false).toList();
    final manifestFiles = entities
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList(growable: false);
    for (final manifestFile in manifestFiles) {
      final queueId = path.basenameWithoutExtension(manifestFile.path);
      if (!_isCanonicalUuidV4(queueId)) {
        await _deleteIfExists(manifestFile);
        removedArtifacts++;
        continue;
      }
      final existing = await database.uploadById(queueId);
      if (existing != null) {
        await _deleteIfExists(manifestFile);
        await _deleteIfExists(File('${manifestFile.path}.part'));
        removedArtifacts++;
        continue;
      }
      try {
        final manifest = _StagingManifest.parse(
          jsonDecode(await manifestFile.readAsString()),
        );
        if (manifest.id != queueId) throw const FormatException();
        final payload = _relativeFile(manifest.payloadPath);
        final payloadPart = File('${payload.path}.part');
        if (!await payload.exists() && await payloadPart.exists()) {
          final inspected = await _hashFile(payloadPart);
          if (inspected.size != manifest.byteSize ||
              inspected.sha256 != manifest.sha256) {
            throw const FormatException();
          }
          await payloadPart.rename(payload.path);
        }
        final inspected = await _hashFile(payload);
        if (inspected.size != manifest.byteSize ||
            inspected.sha256 != manifest.sha256 ||
            await _detectMime(payload) != manifest.mimeType) {
          throw const FormatException();
        }
        if (manifest.ocrContentPath case final ocrPath?) {
          final ocr = _relativeFile(ocrPath);
          final ocrPart = File('${ocr.path}.part');
          if (!await ocr.exists() && await ocrPart.exists()) {
            await ocrPart.rename(ocr.path);
          }
          final bytes = await ocr.readAsBytes();
          if (bytes.length > _maximumOcrBytes ||
              sha256.convert(bytes).toString() != manifest.ocrSha256) {
            throw const FormatException();
          }
          utf8.decode(bytes, allowMalformed: false);
        }
        await _insertManifest(manifest);
        await _deleteIfExists(manifestFile);
        recovered++;
      } on UnsupportedLocalStorageException {
        rethrow;
      } catch (_) {
        await _deleteQueueArtifacts(queueId);
        removedArtifacts++;
      }
    }

    final rows = await database.allUploads();
    for (final upload in rows) {
      if (const {
        'processingServer',
        'filed',
        'duplicate',
        'processingFailed',
      }.contains(upload.state)) {
        await deletePayloads(upload);
      }
      if (upload.state == 'uploading') {
        await (database.update(
          database.scanUploads,
        )..where((row) => row.id.equals(upload.id))).write(
          ScanUploadsCompanion(
            state: const Value('queued'),
            bytesSent: const Value(0),
            updatedAtMs: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
          ),
        );
        demoted++;
      }
      if (_requiresPayload(upload.state)) {
        try {
          final payload = payloadFile(upload);
          final inspected = await _hashFile(payload);
          if (inspected.size != upload.byteSize ||
              inspected.sha256 != upload.sha256 ||
              await _detectMime(payload) != upload.mimeType) {
            throw const FormatException();
          }
          if (upload.ocrContentPath case final ocrPath?) {
            final ocr = _relativeFile(ocrPath);
            if (await FileSystemEntity.type(ocr.path, followLinks: false) !=
                FileSystemEntityType.file) {
              throw const FormatException();
            }
            final bytes = await ocr.readAsBytes();
            if (bytes.length > _maximumOcrBytes ||
                upload.ocrSha256 == null ||
                sha256.convert(bytes).toString() != upload.ocrSha256) {
              throw const FormatException();
            }
            utf8.decode(bytes, allowMalformed: false);
          }
        } catch (_) {
          await (database.update(
            database.scanUploads,
          )..where((row) => row.id.equals(upload.id))).write(
            ScanUploadsCompanion(
              state: const Value('uploadFailed'),
              lastErrorCode: const Value('payload_missing_or_changed'),
              lastErrorMessage: const Value(
                'The staged document is missing or changed.',
              ),
              completedAtMs: Value(
                DateTime.now().toUtc().millisecondsSinceEpoch,
              ),
              updatedAtMs: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
            ),
          );
          failed++;
        }
      }
    }

    final knownIds = (await database.allUploads()).map((row) => row.id).toSet();
    final remaining = await root.list(followLinks: false).toList();
    for (final entity in remaining) {
      if (entity is! File) continue;
      final name = path.basename(entity.path);
      final id = name.split('.').first;
      if (name.endsWith('.part') ||
          (_isQueueArtifact(name) && !knownIds.contains(id))) {
        await _deleteIfExists(entity);
        removedArtifacts++;
      }
    }

    return ReconciliationReport(
      recovered: recovered,
      demoted: demoted,
      failed: failed,
      removedArtifacts: removedArtifacts,
    );
  }

  void _validateInput(
    StageDocumentInput input,
    ShareReceiptInput? shareReceipt,
    String? captureReceiptId,
  ) {
    if (!_supportedMimes.contains(input.mimeType)) {
      throw const QueueStageException(
        'unsupported_mime',
        'This document type is not supported.',
      );
    }
    if (!_validFilename(input.filename)) {
      throw const QueueStageException(
        'bad_filename',
        'Document filename is invalid.',
      );
    }
    if (input.expectedSize != null &&
        input.expectedSize! > maximumDocumentBytes) {
      throw const QueueStageException(
        'payload_too_large',
        'Mobile intake is limited to 64 MiB per document.',
      );
    }
    if (input.pageCount <= 0 ||
        input.sourceMtime != null && input.sourceMtime! <= 0 ||
        input.expectedSize != null && input.expectedSize! <= 0 ||
        input.expectedSha256 != null &&
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(input.expectedSha256!)) {
      throw const QueueStageException(
        'bad_metadata',
        'Document metadata is invalid.',
      );
    }
    if (shareReceipt != null &&
        (input.source != ScanSource.share ||
            input.expectedSize == null ||
            input.expectedSha256 == null ||
            !_isCanonicalUuidV4(shareReceipt.batchId) ||
            shareReceipt.itemIndex < 0)) {
      throw const QueueStageException(
        'bad_share_receipt',
        'Share receipt metadata is invalid.',
      );
    }
    if (captureReceiptId != null &&
        (input.source != ScanSource.camera ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(captureReceiptId))) {
      throw const QueueStageException(
        'bad_capture_receipt',
        'Camera receipt metadata is invalid.',
      );
    }
    final identity = input.identity;
    if (identity != null &&
        (identity.userId <= 0 ||
            identity.systemId <= 0 ||
            !_validQueueOrigin(identity.origin.toString()))) {
      throw const QueueStageException(
        'bad_identity',
        'Queue identity is invalid.',
      );
    }
    final ocr = input.ocr;
    if (ocr != null) {
      final length = utf8.encode(ocr.content).length;
      if (ocr.content.trim().isEmpty ||
          length > _maximumOcrBytes ||
          !ocr.confidence.isFinite ||
          ocr.confidence < 0 ||
          ocr.confidence > 1 ||
          !RegExp(r'^[a-z]{2,3}(?:[-_][A-Z]{2})?$').hasMatch(ocr.language)) {
        throw const QueueStageException(
          'bad_device_content',
          'Device text metadata is invalid.',
        );
      }
    }
  }

  File _relativeFile(String relativePath) {
    if (relativePath.isEmpty ||
        path.basename(relativePath) != relativePath ||
        relativePath == '.' ||
        relativePath == '..' ||
        relativePath.contains('/') ||
        relativePath.contains('\\')) {
      throw const QueueStageException(
        'bad_storage_path',
        'Stored queue path is invalid.',
      );
    }
    return File(path.join(root.path, relativePath));
  }

  Future<({int size, String sha256})> _copyAndHash(
    File source,
    File destination,
  ) async {
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const QueueStageException(
        'bad_source_file',
        'Document source must be a regular file.',
      );
    }
    if (await source.length() > maximumDocumentBytes) {
      throw const QueueStageException(
        'payload_too_large',
        'Mobile intake is limited to 64 MiB per document.',
      );
    }
    final input = await source.open();
    final output = await destination.open(mode: FileMode.writeOnly);
    final digestSink = _DigestSink();
    final hashInput = sha256.startChunkedConversion(digestSink);
    var size = 0;
    try {
      while (true) {
        final chunk = await input.read(_copyBufferSize);
        if (chunk.isEmpty) break;
        size += chunk.length;
        if (size > maximumDocumentBytes) {
          throw const QueueStageException(
            'payload_too_large',
            'Mobile intake is limited to 64 MiB per document.',
          );
        }
        hashInput.add(chunk);
        await output.writeFrom(chunk);
      }
      hashInput.close();
      await output.flush();
      return (size: size, sha256: digestSink.value.toString());
    } finally {
      await input.close();
      await output.close();
    }
  }

  Future<({int size, String sha256})> _hashFile(File file) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FileSystemException('not a regular file');
    }
    final digest = await sha256.bind(file.openRead()).single;
    return (size: await file.length(), sha256: digest.toString());
  }

  Future<String> _detectMime(File file) async {
    final handle = await file.open();
    try {
      final bytes = await handle.read(4096);
      if (bytes.length >= 5 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46 &&
          bytes[4] == 0x2d) {
        return 'application/pdf';
      }
      if (bytes.length >= 3 &&
          bytes[0] == 0xff &&
          bytes[1] == 0xd8 &&
          bytes[2] == 0xff) {
        return 'image/jpeg';
      }
      const png = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
      if (bytes.length >= png.length && _bytesEqual(bytes, png, png.length)) {
        return 'image/png';
      }
      if (bytes.length >= 16 &&
          bytes[4] == 0x66 &&
          bytes[5] == 0x74 &&
          bytes[6] == 0x79 &&
          bytes[7] == 0x70) {
        final boxSize =
            bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3];
        if (boxSize >= 16 &&
            boxSize <= bytes.length &&
            boxSize <= 4096 &&
            (boxSize - 16) % 4 == 0) {
          final brands = <String>[];
          for (var offset = 8; offset < boxSize; offset += 4) {
            if (offset == 12) continue;
            brands.add(
              ascii.decode(bytes.sublist(offset, offset + 4)).toLowerCase(),
            );
          }
          if (brands.any(const {'avif', 'avis'}.contains)) return '';
          if (brands.any(const {'heic', 'heix', 'hevc', 'hevx'}.contains)) {
            return 'image/heic';
          }
          if (brands.any(const {'mif1', 'msf1'}.contains)) return 'image/heif';
        }
      }
      return '';
    } on FormatException {
      return '';
    } finally {
      await handle.close();
    }
  }

  Future<void> _writeAndFlush(File file, List<int> bytes) async {
    final handle = await file.open(mode: FileMode.writeOnly);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  Future<void> _deleteQueueArtifacts(String id) async {
    for (final suffix in const [
      '.payload.part',
      '.payload',
      '.ocr.part',
      '.ocr',
      '.json.part',
      '.json',
    ]) {
      await _deleteIfExists(File(path.join(root.path, '$id$suffix')));
    }
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Startup reconciliation will retry cleanup without hiding valid rows.
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('ScanQueueStore is closed.');
  }

  static bool _requiresPayload(String state) =>
      state == 'unassigned' ||
      state == 'queued' ||
      state == 'uploading' ||
      state == 'uploadFailed';

  static bool _isQueueArtifact(String name) =>
      name.endsWith('.payload') ||
      name.endsWith('.ocr') ||
      name.endsWith('.json');

  static bool _validFilename(String value) =>
      value.isNotEmpty &&
      value != '.' &&
      value != '..' &&
      utf8.encode(value).length <= 255 &&
      path.basename(value) == value &&
      !value.contains('/') &&
      !value.contains('\\') &&
      !value.runes.any((rune) => rune < 0x20 || rune == 0x7f);

  static bool _isCanonicalUuidV4(String value) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(value);

  static bool _bytesEqual(List<int> left, List<int> right, int length) {
    for (var index = 0; index < length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static ScanUploadsCompanion _companionFromManifest(
    _StagingManifest manifest,
  ) => ScanUploadsCompanion.insert(
    id: manifest.id,
    payloadPath: manifest.payloadPath,
    ocrContentPath: Value(manifest.ocrContentPath),
    ocrSha256: Value(manifest.ocrSha256),
    sha256: manifest.sha256,
    byteSize: manifest.byteSize,
    mimeType: manifest.mimeType,
    filename: manifest.filename,
    sourceMtime: Value(manifest.sourceMtime),
    ocrConfidence: Value(manifest.ocrConfidence),
    ocrLanguage: Value(manifest.ocrLanguage),
    source: manifest.source,
    shareBatchId: Value(manifest.shareBatchId),
    shareItemIndex: Value(manifest.shareItemIndex),
    pageCount: manifest.pageCount,
    state: manifest.state,
    identityUserId: Value(manifest.identityUserId),
    identityOrigin: Value(manifest.identityOrigin),
    identitySystemId: Value(manifest.identitySystemId),
    createdAtMs: manifest.createdAtMs,
    updatedAtMs: manifest.createdAtMs,
  );
}

final class _StagingManifest {
  const _StagingManifest({
    required this.id,
    required this.payloadPath,
    required this.ocrContentPath,
    required this.ocrSha256,
    required this.sha256,
    required this.byteSize,
    required this.mimeType,
    required this.filename,
    required this.sourceMtime,
    required this.ocrConfidence,
    required this.ocrLanguage,
    required this.source,
    required this.shareBatchId,
    required this.shareItemIndex,
    required this.captureReceiptId,
    required this.pageCount,
    required this.state,
    required this.identityUserId,
    required this.identityOrigin,
    required this.identitySystemId,
    required this.createdAtMs,
  });

  factory _StagingManifest.parse(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException();
    }
    final version = value['version'];
    if (version is! int) throw const FormatException();
    if (version != ScanQueueStore._manifestVersion) {
      throw const UnsupportedLocalStorageException();
    }
    final id = value['id'];
    final payloadPath = value['payload_path'];
    final ocrContentPath = value['ocr_content_path'];
    final ocrSha256 = value['ocr_sha256'];
    final digest = value['sha256'];
    final byteSize = value['byte_size'];
    final mimeType = value['mime_type'];
    final filename = value['filename'];
    final sourceMtime = value['source_mtime'];
    final ocrConfidence = value['ocr_confidence'];
    final ocrLanguage = value['ocr_language'];
    final source = value['source'];
    final shareBatchId = value['share_batch_id'];
    final shareItemIndex = value['share_item_index'];
    final captureReceiptId = value['capture_receipt_id'];
    final pageCount = value['page_count'];
    final state = value['state'];
    final identityUserId = value['identity_user_id'];
    final identityOrigin = value['identity_origin'];
    final identitySystemId = value['identity_system_id'];
    final createdAtMs = value['created_at_ms'];
    final hasOcr = ocrContentPath != null;
    final hasIdentity = identityUserId != null;
    final hasShareReceipt = shareBatchId != null;
    if (id is! String ||
        !ScanQueueStore._isCanonicalUuidV4(id) ||
        payloadPath is! String ||
        path.basename(payloadPath) != payloadPath ||
        payloadPath != '$id.payload' ||
        digest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        byteSize is! int ||
        byteSize <= 0 ||
        mimeType is! String ||
        !ScanQueueStore._supportedMimes.contains(mimeType) ||
        filename is! String ||
        !ScanQueueStore._validFilename(filename) ||
        sourceMtime != null && (sourceMtime is! int || sourceMtime <= 0) ||
        source is! String ||
        !const {'camera', 'share'}.contains(source) ||
        pageCount is! int ||
        pageCount <= 0 ||
        state is! String ||
        !const {'unassigned', 'queued'}.contains(state) ||
        createdAtMs is! int ||
        createdAtMs <= 0 ||
        hasOcr != (ocrSha256 != null) ||
        hasOcr != (ocrConfidence != null) ||
        hasOcr != (ocrLanguage != null) ||
        hasIdentity != (identityOrigin != null) ||
        hasIdentity != (identitySystemId != null) ||
        hasIdentity != (state == 'queued') ||
        hasShareReceipt != (shareItemIndex != null)) {
      throw const FormatException();
    }
    if (hasOcr &&
        (ocrContentPath is! String ||
            ocrContentPath != '$id.ocr' ||
            ocrSha256 is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(ocrSha256) ||
            ocrConfidence is! num ||
            !ocrConfidence.isFinite ||
            ocrConfidence < 0 ||
            ocrConfidence > 1 ||
            ocrLanguage is! String ||
            !RegExp(r'^[a-z]{2,3}(?:[-_][A-Z]{2})?$').hasMatch(ocrLanguage))) {
      throw const FormatException();
    }
    if (hasIdentity &&
        (identityUserId is! int ||
            identityUserId <= 0 ||
            identityOrigin is! String ||
            !_validIdentityOrigin(identityOrigin) ||
            identitySystemId is! int ||
            identitySystemId <= 0)) {
      throw const FormatException();
    }
    if (hasShareReceipt &&
        (source != 'share' ||
            shareBatchId is! String ||
            !ScanQueueStore._isCanonicalUuidV4(shareBatchId) ||
            shareItemIndex is! int ||
            shareItemIndex < 0)) {
      throw const FormatException();
    }
    if (captureReceiptId != null &&
        (source != 'camera' ||
            captureReceiptId is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(captureReceiptId))) {
      throw const FormatException();
    }
    return _StagingManifest(
      id: id,
      payloadPath: payloadPath,
      ocrContentPath: ocrContentPath as String?,
      ocrSha256: ocrSha256 as String?,
      sha256: digest,
      byteSize: byteSize,
      mimeType: mimeType,
      filename: filename,
      sourceMtime: sourceMtime as int?,
      ocrConfidence: (ocrConfidence as num?)?.toDouble(),
      ocrLanguage: ocrLanguage as String?,
      source: source,
      shareBatchId: shareBatchId as String?,
      shareItemIndex: shareItemIndex as int?,
      captureReceiptId: captureReceiptId as String?,
      pageCount: pageCount,
      state: state,
      identityUserId: identityUserId as int?,
      identityOrigin: identityOrigin as String?,
      identitySystemId: identitySystemId as int?,
      createdAtMs: createdAtMs,
    );
  }

  final String id;
  final String payloadPath;
  final String? ocrContentPath;
  final String? ocrSha256;
  final String sha256;
  final int byteSize;
  final String mimeType;
  final String filename;
  final int? sourceMtime;
  final double? ocrConfidence;
  final String? ocrLanguage;
  final String source;
  final String? shareBatchId;
  final int? shareItemIndex;
  final String? captureReceiptId;
  final int pageCount;
  final String state;
  final int? identityUserId;
  final String? identityOrigin;
  final int? identitySystemId;
  final int createdAtMs;

  static bool _validIdentityOrigin(String value) => _validQueueOrigin(value);
}

bool _validQueueOrigin(String value) {
  try {
    return ServerOrigin.canonicalizeStoredIdentity(value).toString() == value;
  } on ServerOriginException {
    return false;
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value => _value ?? (throw StateError('Digest is not complete.'));

  @override
  void add(Digest data) {
    if (_value != null) throw StateError('Digest was emitted more than once.');
    _value = data;
  }

  @override
  void close() {}
}
