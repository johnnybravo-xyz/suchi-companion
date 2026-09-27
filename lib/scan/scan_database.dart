import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'scan_database.g.dart';

const durableScanStates = <String>{
  'unassigned',
  'queued',
  'uploading',
  'processingServer',
  'filed',
  'duplicate',
  'uploadFailed',
  'processingFailed',
};

const terminalScanStates = <String>{
  'filed',
  'duplicate',
  'uploadFailed',
  'processingFailed',
};

final class UnsupportedLocalStorageException implements Exception {
  const UnsupportedLocalStorageException();

  static const message =
      'This pre-release installation uses an unsupported local storage format. '
      'Queue files were preserved. Reset or reinstall Suchi Companion before continuing.';

  @override
  String toString() => message;
}

bool isUnsupportedLocalStorageError(Object? error) =>
    error?.toString() == UnsupportedLocalStorageException.message;

class ScanUploads extends Table {
  TextColumn get id => text()();
  TextColumn get payloadPath => text()();
  TextColumn get ocrContentPath => text().nullable()();
  TextColumn get ocrSha256 => text().nullable()();
  TextColumn get sha256 => text()();
  IntColumn get byteSize => integer()();
  TextColumn get mimeType => text()();
  TextColumn get filename => text()();
  IntColumn get sourceMtime => integer().nullable()();
  RealColumn get ocrConfidence => real().nullable()();
  TextColumn get ocrLanguage => text().nullable()();
  TextColumn get source => text()();
  TextColumn get shareBatchId => text().nullable()();
  IntColumn get shareItemIndex => integer().nullable()();
  IntColumn get pageCount => integer()();
  TextColumn get state => text()();
  IntColumn get bytesSent => integer().withDefault(const Constant(0))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptAtMs => integer().nullable()();
  IntColumn get identityUserId => integer().nullable()();
  TextColumn get identityOrigin => text().nullable()();
  IntColumn get identitySystemId => integer().nullable()();
  IntColumn get serverDocumentId => integer().nullable()();
  IntColumn get serverTaskId => integer().nullable()();
  IntColumn get splitOriginId => integer().nullable()();
  TextColumn get splitDocumentIds => text().nullable()();
  BoolColumn get deduplicated => boolean().withDefault(const Constant(false))();
  BoolColumn get restored => boolean().withDefault(const Constant(false))();
  BoolColumn get split => boolean().withDefault(const Constant(false))();
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get lastErrorMessage => text().nullable()();
  TextColumn get requestId => text().nullable()();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();
  IntColumn get completedAtMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ShareReceipts extends Table {
  TextColumn get batchId => text()();
  IntColumn get itemIndex => integer()();
  TextColumn get sha256 => text()();
  IntColumn get byteSize => integer()();
  TextColumn get mimeType => text()();
  TextColumn get queueId => text().nullable()();
  TextColumn get status => text()();
  TextColumn get errorCode => text().nullable()();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {batchId, itemIndex};
}

class CaptureReceipts extends Table {
  TextColumn get captureId => text()();
  TextColumn get queueId => text()();
  IntColumn get createdAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {captureId};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(
  tables: [ScanUploads, ShareReceipts, CaptureReceipts, AppSettings],
)
final class ScanDatabase extends _$ScanDatabase {
  static const fileName = 'suchi_scan_queue.sqlite';

  ScanDatabase(super.executor);

  ScanDatabase.open(Directory directory)
    : super(
        driftDatabase(
          name: 'suchi_scan_queue',
          native: DriftNativeOptions(
            databaseDirectory: () async => directory.absolute,
            tempDirectoryPath: () async => directory.absolute.path,
          ),
        ),
      );

  static Future<void> rejectLegacyLocation(Directory directory) async {
    final legacy = File(
      '${directory.absolute.path}${Platform.pathSeparator}$fileName',
    );
    if (await legacy.exists()) {
      throw const UnsupportedLocalStorageException();
    }
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      throw const UnsupportedLocalStorageException();
    },
  );

  Stream<List<ScanUpload>> watchUploads() => (select(
    scanUploads,
  )..orderBy([(row) => OrderingTerm.desc(row.createdAtMs)])).watch();

  Future<List<ScanUpload>> allUploads() => (select(
    scanUploads,
  )..orderBy([(row) => OrderingTerm.asc(row.createdAtMs)])).get();

  Future<ScanUpload?> uploadById(String id) => (select(
    scanUploads,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<void> insertUpload(ScanUploadsCompanion upload) =>
      into(scanUploads).insert(upload);

  Future<void> deleteUpload(String id) =>
      (delete(scanUploads)..where((row) => row.id.equals(id))).go();

  Future<ShareReceipt?> shareReceipt(String batchId, int itemIndex) =>
      (select(shareReceipts)..where(
            (row) =>
                row.batchId.equals(batchId) & row.itemIndex.equals(itemIndex),
          ))
          .getSingleOrNull();

  Future<void> insertShareReceipt(ShareReceiptsCompanion receipt) =>
      into(shareReceipts).insert(receipt);

  Future<void> insertShareReceiptIfAbsent(ShareReceiptsCompanion receipt) =>
      into(shareReceipts).insert(receipt, mode: InsertMode.insertOrIgnore);

  Future<CaptureReceipt?> captureReceipt(String captureId) => (select(
    captureReceipts,
  )..where((row) => row.captureId.equals(captureId))).getSingleOrNull();

  Future<void> insertCaptureReceipt(CaptureReceiptsCompanion receipt) =>
      into(captureReceipts).insert(receipt);

  Future<int> pruneCompletedReceipts({
    required int beforeMs,
    required int keepNewest,
  }) {
    if (beforeMs <= 0 || keepNewest <= 0) {
      throw ArgumentError('Receipt retention bounds must be positive.');
    }
    return transaction(() async {
      final shareCount = await customUpdate(
        '''
DELETE FROM share_receipts
WHERE updated_at_ms < ?
   OR rowid NOT IN (
     SELECT rowid
     FROM share_receipts
     ORDER BY updated_at_ms DESC, batch_id DESC, item_index DESC
     LIMIT ?
   )
''',
        variables: [Variable<int>(beforeMs), Variable<int>(keepNewest)],
        updates: {shareReceipts},
      );
      final captureCount = await customUpdate(
        '''
DELETE FROM capture_receipts
WHERE created_at_ms < ?
   OR rowid NOT IN (
     SELECT rowid
     FROM capture_receipts
     ORDER BY created_at_ms DESC, capture_id DESC
     LIMIT ?
   )
''',
        variables: [Variable<int>(beforeMs), Variable<int>(keepNewest)],
        updates: {captureReceipts},
      );
      return shareCount + captureCount;
    });
  }

  Future<void> setSetting(String key, String value) => into(
    appSettings,
  ).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));

  Future<String?> setting(String key) async => (await (select(
    appSettings,
  )..where((row) => row.key.equals(key))).getSingleOrNull())?.value;

  Future<List<AppSetting>> settingsWithPrefix(String prefix) async =>
      (await select(appSettings).get())
          .where((setting) => setting.key.startsWith(prefix))
          .toList(growable: false);

  Future<void> deleteSetting(String key) =>
      (delete(appSettings)..where((row) => row.key.equals(key))).go();
}
