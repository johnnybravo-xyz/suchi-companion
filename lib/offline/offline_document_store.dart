import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../auth/account_identity.dart';
import '../auth/server_origin.dart';
import '../detail/document_files.dart';
import '../scan/storage_protection.dart';

const offlineDocumentByteLimit = 64 * 1024 * 1024;

final class OfflineDocumentException implements Exception {
  const OfflineDocumentException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class OfflineDocument {
  const OfflineDocument({
    required this.identity,
    required this.document,
    required this.payload,
    required this.directory,
    required this.byteSize,
    required this.savedAt,
  });

  final AccountIdentity identity;
  final DocumentDetail document;
  final File payload;
  final Directory directory;
  final int byteSize;
  final DateTime savedAt;

  DocumentSummary get summary => DocumentSummary(
    id: document.id,
    title: document.title,
    mimeType: document.mimeType,
    originalSize: byteSize,
    jdCategoryId: document.jdCategoryId,
    jdCategoryCode: document.jdCategoryCode,
    jdCategoryName: document.jdCategoryName,
    jdAreaName: document.jdAreaName,
    sensitivity: document.sensitivity,
    thumbnailSha: null,
    splitOriginId: null,
    splitIndex: null,
    createdAt: document.createdAt,
    updatedAt: document.updatedAt,
    trashedAt: document.trashedAt,
    tags: document.tags,
    correspondents: document.correspondents
        .map((correspondent) => correspondent.name)
        .toList(growable: false),
  );
}

final class OfflineDocumentStore extends ChangeNotifier {
  OfflineDocumentStore._({
    required this.root,
    required this._files,
    required this._now,
    required this._newUuid,
  });

  static const _manifestVersion = 1;
  static const _maximumManifestBytes = 256 * 1024;
  static final _committedName = RegExp(
    r'^offline-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  final Directory root;
  final DocumentFiles _files;
  final DateTime Function() _now;
  final String Function() _newUuid;
  List<OfflineDocument> _entries = const [];
  Completer<void>? _abort;
  Completer<void>? _idle;
  int _generation = 0;
  int? _activeDocumentId;
  String? _errorMessage;
  bool _closed = false;

  static Future<OfflineDocumentStore> open({
    required DocumentFiles files,
    Directory? root,
    StorageProtection storageProtection = const NativeStorageProtection(),
    DateTime Function()? now,
    String Function()? newUuid,
  }) async {
    final support =
        root ??
        Directory(
          path.join(
            (await getApplicationSupportDirectory()).path,
            'suchi-offline-documents',
          ),
        );
    await support.create(recursive: true);
    if (await FileSystemEntity.type(support.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw FileSystemException(
        'Offline document storage must be a private directory.',
        support.path,
      );
    }
    await storageProtection.protectDirectory(support.absolute.path);
    final store = OfflineDocumentStore._(
      root: support.absolute,
      files: files,
      now: now ?? (() => DateTime.now().toUtc()),
      newUuid: newUuid ?? const Uuid().v4,
    );
    await store._reconcile();
    return store;
  }

  List<OfflineDocument> entriesFor(AccountIdentity? identity) {
    if (identity == null) return const [];
    return List.unmodifiable(
      _entries.where((entry) => entry.identity == identity),
    );
  }

  OfflineDocument? find(AccountIdentity? identity, int documentId) {
    if (identity == null) return null;
    for (final entry in _entries) {
      if (entry.identity == identity && entry.document.id == documentId) {
        return entry;
      }
    }
    return null;
  }

  int totalBytesFor(AccountIdentity? identity) {
    if (identity == null) return 0;
    var total = 0;
    for (final entry in _entries) {
      if (entry.identity == identity) total += entry.byteSize;
    }
    return total;
  }

  int? get activeDocumentId => _activeDocumentId;
  bool get busy => _idle != null;
  String? get errorMessage => _errorMessage;

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<OfflineDocument> save({
    required AccountIdentity identity,
    required DocumentDetail document,
    required SuchiClient client,
    bool reveal = false,
  }) async {
    _ensureOpen();
    _validateIdentity(identity);
    if (_idle != null) {
      throw const OfflineDocumentException(
        'offline_busy',
        'Another offline document operation is still running.',
      );
    }
    if (document.originalSize <= 0 ||
        document.originalSize > offlineDocumentByteLimit) {
      throw const OfflineDocumentException(
        'offline_size',
        'Documents larger than 64 MiB cannot be kept offline.',
      );
    }
    final generation = _generation;
    final abort = Completer<void>();
    final idle = Completer<void>();
    _abort = abort;
    _idle = idle;
    _activeDocumentId = document.id;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _save(
        identity: identity,
        document: document,
        client: client,
        reveal: reveal,
        generation: generation,
        abort: abort.future,
      );
    } on ApiException catch (error) {
      _errorMessage = error.message;
      rethrow;
    } on OfflineDocumentException catch (error) {
      _errorMessage = error.message;
      rethrow;
    } on FileSystemException {
      _errorMessage = 'The offline copy could not be saved. Check available device storage and try again.';
      rethrow;
    } finally {
      _abort = null;
      _idle = null;
      _activeDocumentId = null;
      if (!idle.isCompleted) idle.complete();
      notifyListeners();
    }
  }

  Future<OfflineDocument> _save({
    required AccountIdentity identity,
    required DocumentDetail document,
    required SuchiClient client,
    required bool reveal,
    required int generation,
    required Future<void> abort,
  }) async {
    final uuid = _newUuid();
    if (!_isCanonicalUuidV4(uuid)) {
      throw const OfflineDocumentException(
        'offline_id',
        'The offline copy identifier is invalid.',
      );
    }
    final staging = Directory(path.join(root.path, 'offline-$uuid.part'));
    final committed = Directory(path.join(root.path, 'offline-$uuid'));
    await staging.create();
    var published = false;
    try {
      final partialPayload = File(path.join(staging.path, 'payload.part'));
      final downloadedMime = await client.downloadDocument(
        document.id,
        destination: partialPayload,
        preview: false,
        reveal: reveal,
        abortTrigger: abort,
      );
      _checkGeneration(generation);
      final normalizedMime = _normalizedMime(document.mimeType);
      if (downloadedMime != normalizedMime) {
        throw const ApiException(
          kind: ApiFailureKind.malformedResponse,
          message: 'Suchi returned a different document type than expected.',
        );
      }
      final stat = await partialPayload.stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size != document.originalSize ||
          stat.size <= 0 ||
          stat.size > offlineDocumentByteLimit) {
        throw const ApiException(
          kind: ApiFailureKind.malformedResponse,
          message: 'Suchi returned an incomplete document download.',
        );
      }
      final payloadName =
          'document-${document.id}${DocumentFiles.extensionForMimeType(normalizedMime)}';
      await partialPayload.rename(path.join(staging.path, payloadName));
      _checkGeneration(generation);
      final savedAt = _now().toUtc();
      if (savedAt.millisecondsSinceEpoch <= 0) {
        throw const OfflineDocumentException(
          'offline_time',
          'The device time is invalid.',
        );
      }
      final manifest = _manifest(
        identity: identity,
        document: document,
        payloadName: payloadName,
        byteSize: stat.size,
        savedAt: savedAt,
      );
      final encoded = utf8.encode(jsonEncode(manifest));
      if (encoded.length > _maximumManifestBytes) {
        throw const OfflineDocumentException(
          'offline_metadata',
          'The document metadata is too large to keep offline.',
        );
      }
      final manifestPartial = File(
        path.join(staging.path, 'manifest.json.part'),
      );
      final writer = await manifestPartial.open(mode: FileMode.writeOnly);
      try {
        await writer.writeFrom(encoded);
        await writer.flush();
      } finally {
        await writer.close();
      }
      await manifestPartial.rename(path.join(staging.path, 'manifest.json'));
      _checkGeneration(generation);
      await staging.rename(committed.path);
      _checkGeneration(generation);
      final entry = await _readCommitted(committed);
      if (entry == null) {
        throw const OfflineDocumentException(
          'offline_commit',
          'The offline copy could not be verified after saving.',
        );
      }
      final previous = find(identity, document.id);
      _entries = List.unmodifiable([
        entry,
        for (final item in _entries)
          if (!identical(item, previous)) item,
      ]);
      published = true;
      notifyListeners();
      if (previous != null) {
        try {
          await previous.directory.delete(recursive: true);
        } on FileSystemException {
          // Reconciliation removes the older valid duplicate before the next
          // removal, account clear, or startup completes.
        }
      }
      return entry;
    } finally {
      if (!published) {
        if (await staging.exists()) await staging.delete(recursive: true);
        if (await committed.exists()) await committed.delete(recursive: true);
      }
    }
  }

  Future<void> remove(AccountIdentity identity, int documentId) async {
    _ensureOpen();
    _validateIdentity(identity);
    if (_idle != null) {
      throw const OfflineDocumentException(
        'offline_busy',
        'Another offline document operation is still running.',
      );
    }
    final idle = Completer<void>();
    _idle = idle;
    _activeDocumentId = documentId;
    _errorMessage = null;
    notifyListeners();
    try {
      // An earlier successful update may have left an older valid directory
      // when best-effort duplicate deletion failed. Reconcile before removal
      // so no hidden copy can reappear after restart.
      await _reconcile();
      final entry = find(identity, documentId);
      if (entry == null) return;
      await entry.directory.delete(recursive: true);
      _entries = List.unmodifiable(
        _entries.where((item) => !identical(item, entry)),
      );
    } on FileSystemException {
      _errorMessage = 'The offline copy could not be removed. Try again.';
      rethrow;
    } finally {
      _idle = null;
      _activeDocumentId = null;
      if (!idle.isCompleted) idle.complete();
      notifyListeners();
    }
  }

  Future<void> clearAccount(AccountIdentity identity) async {
    _ensureOpen();
    _validateIdentity(identity);
    cancelPending();
    while (_idle != null) {
      await _waitForIdle();
      cancelPending();
    }
    final idle = Completer<void>();
    _idle = idle;
    _activeDocumentId = null;
    _errorMessage = null;
    notifyListeners();
    try {
      // Reconciliation removes malformed and duplicate directories before the
      // account deletion is allowed to succeed.
      await _reconcile();
      final owned = entriesFor(identity);
      for (final entry in owned) {
        if (await entry.directory.exists()) {
          await entry.directory.delete(recursive: true);
        }
      }
      _entries = List.unmodifiable(
        _entries.where((entry) => entry.identity != identity),
      );
      _errorMessage = null;
    } on FileSystemException {
      try {
        await _reconcile();
      } on FileSystemException {
        // Preserve the first cleanup failure for the sign-out caller.
      }
      _errorMessage =
          'Offline documents could not be removed from protected storage.';
      rethrow;
    } finally {
      _idle = null;
      if (!idle.isCompleted) idle.complete();
      notifyListeners();
    }
  }

  Future<void> handoff({
    required AccountIdentity identity,
    required OfflineDocument entry,
    required bool share,
  }) {
    _ensureOpen();
    if (entry.identity != identity ||
        !identical(find(identity, entry.document.id), entry)) {
      throw const OfflineDocumentException(
        'offline_account',
        'This offline document no longer belongs to the active account.',
      );
    }
    return _files.handoffLocal(
      file: entry.payload,
      mimeType: entry.document.mimeType,
      share: share,
    );
  }

  void cancelPending() {
    _generation++;
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    cancelPending();
    await _waitForIdle();
    _entries = const [];
    super.dispose();
  }

  Future<void> _waitForIdle() async {
    final idle = _idle;
    if (idle != null) await idle.future;
  }

  Future<void> _reconcile() async {
    final valid = <OfflineDocument>[];
    await for (final entity in root.list(followLinks: false)) {
      final name = path.basename(entity.path);
      if (entity is Directory && _committedName.hasMatch(name)) {
        final entry = await _readCommitted(entity);
        if (entry != null) {
          valid.add(entry);
          continue;
        }
      }
      await _deleteEntity(entity);
    }
    valid.sort((left, right) {
      final byDate = right.savedAt.compareTo(left.savedAt);
      return byDate != 0
          ? byDate
          : right.directory.path.compareTo(left.directory.path);
    });
    final seen = <String>{};
    final retained = <OfflineDocument>[];
    for (final entry in valid) {
      final key = [
        entry.identity.origin,
        entry.identity.userId,
        entry.identity.systemId,
        entry.document.id,
      ].join('|');
      if (seen.add(key)) {
        retained.add(entry);
      } else {
        await entry.directory.delete(recursive: true);
      }
    }
    _entries = List.unmodifiable(retained);
    notifyListeners();
  }

  Future<OfflineDocument?> _readCommitted(Directory directory) async {
    try {
      final directoryType = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (directoryType != FileSystemEntityType.directory ||
          directory.parent.absolute.path != root.absolute.path ||
          !_committedName.hasMatch(path.basename(directory.path))) {
        return null;
      }
      final entities = await directory.list(followLinks: false).toList();
      if (entities.length != 2 ||
          entities.any(
            (entity) =>
                entity is! File ||
                path.basename(entity.path) == 'manifest.json.part',
          )) {
        return null;
      }
      final manifestFile = File(path.join(directory.path, 'manifest.json'));
      if (await FileSystemEntity.type(manifestFile.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      final manifestStat = await manifestFile.stat();
      if (manifestStat.size <= 0 || manifestStat.size > _maximumManifestBytes) {
        return null;
      }
      final manifest = jsonDecode(
        utf8.decode(await manifestFile.readAsBytes(), allowMalformed: false),
      );
      if (manifest is! Map<String, dynamic> ||
          !_hasExactKeys(manifest, const {
            'version',
            'identity_origin',
            'identity_user_id',
            'identity_system_id',
            'document',
            'payload_filename',
            'byte_size',
            'saved_at',
          }) ||
          manifest['version'] != _manifestVersion) {
        return null;
      }
      final originValue = manifest['identity_origin'];
      final userId = manifest['identity_user_id'];
      final systemId = manifest['identity_system_id'];
      final payloadName = manifest['payload_filename'];
      final byteSize = manifest['byte_size'];
      final savedAtSeconds = manifest['saved_at'];
      if (originValue is! String ||
          userId is! int ||
          userId <= 0 ||
          systemId is! int ||
          systemId <= 0 ||
          payloadName is! String ||
          byteSize is! int ||
          byteSize <= 0 ||
          byteSize > offlineDocumentByteLimit ||
          savedAtSeconds is! int ||
          savedAtSeconds <= 0) {
        return null;
      }
      final origin = ServerOrigin.canonicalizeStoredIdentity(originValue);
      if (origin.toString() != originValue) return null;
      final documentValue = manifest['document'];
      if (documentValue is! Map<String, dynamic> ||
          !_validDocumentShape(documentValue)) {
        return null;
      }
      final document = DocumentDetail.fromJson(documentValue);
      final normalizedMime = _normalizedMime(document.mimeType);
      final expectedPayload =
          'document-${document.id}${DocumentFiles.extensionForMimeType(normalizedMime)}';
      if (payloadName != expectedPayload || byteSize != document.originalSize) {
        return null;
      }
      final payload = File(path.join(directory.path, payloadName));
      if (path.basename(payload.path) != payloadName ||
          await FileSystemEntity.type(payload.path, followLinks: false) !=
              FileSystemEntityType.file) {
        return null;
      }
      final payloadStat = await payload.stat();
      if (payloadStat.size != byteSize) return null;
      return OfflineDocument(
        identity: AccountIdentity(
          origin: origin,
          userId: userId,
          systemId: systemId,
        ),
        document: document,
        payload: payload,
        directory: directory,
        byteSize: byteSize,
        savedAt: DateTime.fromMillisecondsSinceEpoch(
          savedAtSeconds * 1000,
          isUtc: true,
        ),
      );
    } on ApiFormatException {
      return null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    } on ServerOriginException {
      return null;
    }
  }

  Map<String, Object?> _manifest({
    required AccountIdentity identity,
    required DocumentDetail document,
    required String payloadName,
    required int byteSize,
    required DateTime savedAt,
  }) => {
    'version': _manifestVersion,
    'identity_origin': identity.origin.toString(),
    'identity_user_id': identity.userId,
    'identity_system_id': identity.systemId,
    'document': {
      'id': document.id,
      'title': document.title,
      'mime_type': document.mimeType,
      'original_size': document.originalSize,
      'original_blob': document.originalBlob,
      'jd_category_id': document.jdCategoryId,
      'jd_category_code': document.jdCategoryCode,
      'jd_category_name': document.jdCategoryName,
      'jd_area_name': document.jdAreaName,
      'sensitivity': document.sensitivity,
      'created_at': document.createdAt,
      'added_at': document.addedAt,
      'updated_at': document.updatedAt,
      'source_mtime': document.sourceMtime,
      'trashed_at': document.trashedAt,
      'sources': [
        for (final source in document.sources)
          {
            'kind': source.kind,
            'label': source.label,
            'detail': source.detail,
            'observed_at': source.observedAt,
          },
      ],
      'tags': document.tags,
      'correspondents': [
        for (final correspondent in document.correspondents)
          {
            'id': correspondent.id,
            'name': correspondent.name,
            'role': correspondent.role,
          },
      ],
      'languages': document.languages,
      'languages_locked': document.languagesLocked,
      'content': '',
    },
    'payload_filename': payloadName,
    'byte_size': byteSize,
    'saved_at': savedAt.millisecondsSinceEpoch ~/ 1000,
  };

  static bool _validDocumentShape(Map<String, dynamic> value) {
    if (!_hasExactKeys(value, const {
      'id',
      'title',
      'mime_type',
      'original_size',
      'original_blob',
      'jd_category_id',
      'jd_category_code',
      'jd_category_name',
      'jd_area_name',
      'sensitivity',
      'created_at',
      'added_at',
      'updated_at',
      'source_mtime',
      'trashed_at',
      'sources',
      'tags',
      'correspondents',
      'languages',
      'languages_locked',
      'content',
    })) {
      return false;
    }
    final sources = value['sources'];
    final correspondents = value['correspondents'];
    if (sources is! List ||
        sources.length > 1000 ||
        sources.any(
          (source) =>
              source is! Map<String, dynamic> ||
              !_hasExactKeys(source, const {
                'kind',
                'label',
                'detail',
                'observed_at',
              }),
        ) ||
        correspondents is! List ||
        correspondents.length > 1000 ||
        correspondents.any(
          (correspondent) =>
              correspondent is! Map<String, dynamic> ||
              !_hasExactKeys(correspondent, const {'id', 'name', 'role'}),
        )) {
      return false;
    }
    final tags = value['tags'];
    return tags is List && tags.length <= 1000;
  }

  static bool _hasExactKeys(Map<String, dynamic> value, Set<String> expected) =>
      value.length == expected.length &&
      value.keys.toSet().containsAll(expected);

  static String _normalizedMime(String value) {
    final normalized = value.split(';').first.trim().toLowerCase();
    if (normalized != value ||
        !RegExp(r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$')
            .hasMatch(normalized)) {
      throw const OfflineDocumentException(
        'offline_mime',
        'The document type cannot be kept offline.',
      );
    }
    return normalized;
  }

  static bool _isCanonicalUuidV4(String value) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(value);

  static void _validateIdentity(AccountIdentity identity) {
    if (identity.userId <= 0 ||
        identity.systemId <= 0 ||
        ServerOrigin.canonicalizeStoredIdentity(identity.origin.toString())
                .toString() !=
            identity.origin.toString()) {
      throw const OfflineDocumentException(
        'offline_identity',
        'The offline document account is invalid.',
      );
    }
  }

  void _checkGeneration(int generation) {
    if (_closed || generation != _generation) {
      throw const ApiException(
        kind: ApiFailureKind.cancelled,
        message: 'The offline document download was cancelled.',
      );
    }
  }

  Future<void> _deleteEntity(FileSystemEntity entity) async {
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      await entity.delete(recursive: type == FileSystemEntityType.directory);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('OfflineDocumentStore is closed.');
    }
  }
}
