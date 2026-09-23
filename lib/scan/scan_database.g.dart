// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scan_database.dart';

// ignore_for_file: type=lint
class $ScanUploadsTable extends ScanUploads
    with TableInfo<$ScanUploadsTable, ScanUpload> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScanUploadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadPathMeta = const VerificationMeta(
    'payloadPath',
  );
  @override
  late final GeneratedColumn<String> payloadPath = GeneratedColumn<String>(
    'payload_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ocrContentPathMeta = const VerificationMeta(
    'ocrContentPath',
  );
  @override
  late final GeneratedColumn<String> ocrContentPath = GeneratedColumn<String>(
    'ocr_content_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ocrSha256Meta = const VerificationMeta(
    'ocrSha256',
  );
  @override
  late final GeneratedColumn<String> ocrSha256 = GeneratedColumn<String>(
    'ocr_sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  @override
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filenameMeta = const VerificationMeta(
    'filename',
  );
  @override
  late final GeneratedColumn<String> filename = GeneratedColumn<String>(
    'filename',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMtimeMeta = const VerificationMeta(
    'sourceMtime',
  );
  @override
  late final GeneratedColumn<int> sourceMtime = GeneratedColumn<int>(
    'source_mtime',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ocrConfidenceMeta = const VerificationMeta(
    'ocrConfidence',
  );
  @override
  late final GeneratedColumn<double> ocrConfidence = GeneratedColumn<double>(
    'ocr_confidence',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ocrLanguageMeta = const VerificationMeta(
    'ocrLanguage',
  );
  @override
  late final GeneratedColumn<String> ocrLanguage = GeneratedColumn<String>(
    'ocr_language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shareBatchIdMeta = const VerificationMeta(
    'shareBatchId',
  );
  @override
  late final GeneratedColumn<String> shareBatchId = GeneratedColumn<String>(
    'share_batch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shareItemIndexMeta = const VerificationMeta(
    'shareItemIndex',
  );
  @override
  late final GeneratedColumn<int> shareItemIndex = GeneratedColumn<int>(
    'share_item_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageCountMeta = const VerificationMeta(
    'pageCount',
  );
  @override
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesSentMeta = const VerificationMeta(
    'bytesSent',
  );
  @override
  late final GeneratedColumn<int> bytesSent = GeneratedColumn<int>(
    'bytes_sent',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMsMeta = const VerificationMeta(
    'nextAttemptAtMs',
  );
  @override
  late final GeneratedColumn<int> nextAttemptAtMs = GeneratedColumn<int>(
    'next_attempt_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _identityUserIdMeta = const VerificationMeta(
    'identityUserId',
  );
  @override
  late final GeneratedColumn<int> identityUserId = GeneratedColumn<int>(
    'identity_user_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _identityOriginMeta = const VerificationMeta(
    'identityOrigin',
  );
  @override
  late final GeneratedColumn<String> identityOrigin = GeneratedColumn<String>(
    'identity_origin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _identitySystemIdMeta = const VerificationMeta(
    'identitySystemId',
  );
  @override
  late final GeneratedColumn<int> identitySystemId = GeneratedColumn<int>(
    'identity_system_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverDocumentIdMeta = const VerificationMeta(
    'serverDocumentId',
  );
  @override
  late final GeneratedColumn<int> serverDocumentId = GeneratedColumn<int>(
    'server_document_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverTaskIdMeta = const VerificationMeta(
    'serverTaskId',
  );
  @override
  late final GeneratedColumn<int> serverTaskId = GeneratedColumn<int>(
    'server_task_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _splitOriginIdMeta = const VerificationMeta(
    'splitOriginId',
  );
  @override
  late final GeneratedColumn<int> splitOriginId = GeneratedColumn<int>(
    'split_origin_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _splitDocumentIdsMeta = const VerificationMeta(
    'splitDocumentIds',
  );
  @override
  late final GeneratedColumn<String> splitDocumentIds = GeneratedColumn<String>(
    'split_document_ids',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deduplicatedMeta = const VerificationMeta(
    'deduplicated',
  );
  @override
  late final GeneratedColumn<bool> deduplicated = GeneratedColumn<bool>(
    'deduplicated',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deduplicated" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _restoredMeta = const VerificationMeta(
    'restored',
  );
  @override
  late final GeneratedColumn<bool> restored = GeneratedColumn<bool>(
    'restored',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("restored" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _splitMeta = const VerificationMeta('split');
  @override
  late final GeneratedColumn<bool> split = GeneratedColumn<bool>(
    'split',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("split" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMessageMeta = const VerificationMeta(
    'lastErrorMessage',
  );
  @override
  late final GeneratedColumn<String> lastErrorMessage = GeneratedColumn<String>(
    'last_error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<String> requestId = GeneratedColumn<String>(
    'request_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtMsMeta = const VerificationMeta(
    'completedAtMs',
  );
  @override
  late final GeneratedColumn<int> completedAtMs = GeneratedColumn<int>(
    'completed_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    payloadPath,
    ocrContentPath,
    ocrSha256,
    sha256,
    byteSize,
    mimeType,
    filename,
    sourceMtime,
    ocrConfidence,
    ocrLanguage,
    source,
    shareBatchId,
    shareItemIndex,
    pageCount,
    state,
    bytesSent,
    attemptCount,
    nextAttemptAtMs,
    identityUserId,
    identityOrigin,
    identitySystemId,
    serverDocumentId,
    serverTaskId,
    splitOriginId,
    splitDocumentIds,
    deduplicated,
    restored,
    split,
    lastErrorCode,
    lastErrorMessage,
    requestId,
    createdAtMs,
    updatedAtMs,
    completedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scan_uploads';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScanUpload> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('payload_path')) {
      context.handle(
        _payloadPathMeta,
        payloadPath.isAcceptableOrUnknown(
          data['payload_path']!,
          _payloadPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadPathMeta);
    }
    if (data.containsKey('ocr_content_path')) {
      context.handle(
        _ocrContentPathMeta,
        ocrContentPath.isAcceptableOrUnknown(
          data['ocr_content_path']!,
          _ocrContentPathMeta,
        ),
      );
    }
    if (data.containsKey('ocr_sha256')) {
      context.handle(
        _ocrSha256Meta,
        ocrSha256.isAcceptableOrUnknown(data['ocr_sha256']!, _ocrSha256Meta),
      );
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_byteSizeMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('filename')) {
      context.handle(
        _filenameMeta,
        filename.isAcceptableOrUnknown(data['filename']!, _filenameMeta),
      );
    } else if (isInserting) {
      context.missing(_filenameMeta);
    }
    if (data.containsKey('source_mtime')) {
      context.handle(
        _sourceMtimeMeta,
        sourceMtime.isAcceptableOrUnknown(
          data['source_mtime']!,
          _sourceMtimeMeta,
        ),
      );
    }
    if (data.containsKey('ocr_confidence')) {
      context.handle(
        _ocrConfidenceMeta,
        ocrConfidence.isAcceptableOrUnknown(
          data['ocr_confidence']!,
          _ocrConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('ocr_language')) {
      context.handle(
        _ocrLanguageMeta,
        ocrLanguage.isAcceptableOrUnknown(
          data['ocr_language']!,
          _ocrLanguageMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('share_batch_id')) {
      context.handle(
        _shareBatchIdMeta,
        shareBatchId.isAcceptableOrUnknown(
          data['share_batch_id']!,
          _shareBatchIdMeta,
        ),
      );
    }
    if (data.containsKey('share_item_index')) {
      context.handle(
        _shareItemIndexMeta,
        shareItemIndex.isAcceptableOrUnknown(
          data['share_item_index']!,
          _shareItemIndexMeta,
        ),
      );
    }
    if (data.containsKey('page_count')) {
      context.handle(
        _pageCountMeta,
        pageCount.isAcceptableOrUnknown(data['page_count']!, _pageCountMeta),
      );
    } else if (isInserting) {
      context.missing(_pageCountMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('bytes_sent')) {
      context.handle(
        _bytesSentMeta,
        bytesSent.isAcceptableOrUnknown(data['bytes_sent']!, _bytesSentMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at_ms')) {
      context.handle(
        _nextAttemptAtMsMeta,
        nextAttemptAtMs.isAcceptableOrUnknown(
          data['next_attempt_at_ms']!,
          _nextAttemptAtMsMeta,
        ),
      );
    }
    if (data.containsKey('identity_user_id')) {
      context.handle(
        _identityUserIdMeta,
        identityUserId.isAcceptableOrUnknown(
          data['identity_user_id']!,
          _identityUserIdMeta,
        ),
      );
    }
    if (data.containsKey('identity_origin')) {
      context.handle(
        _identityOriginMeta,
        identityOrigin.isAcceptableOrUnknown(
          data['identity_origin']!,
          _identityOriginMeta,
        ),
      );
    }
    if (data.containsKey('identity_system_id')) {
      context.handle(
        _identitySystemIdMeta,
        identitySystemId.isAcceptableOrUnknown(
          data['identity_system_id']!,
          _identitySystemIdMeta,
        ),
      );
    }
    if (data.containsKey('server_document_id')) {
      context.handle(
        _serverDocumentIdMeta,
        serverDocumentId.isAcceptableOrUnknown(
          data['server_document_id']!,
          _serverDocumentIdMeta,
        ),
      );
    }
    if (data.containsKey('server_task_id')) {
      context.handle(
        _serverTaskIdMeta,
        serverTaskId.isAcceptableOrUnknown(
          data['server_task_id']!,
          _serverTaskIdMeta,
        ),
      );
    }
    if (data.containsKey('split_origin_id')) {
      context.handle(
        _splitOriginIdMeta,
        splitOriginId.isAcceptableOrUnknown(
          data['split_origin_id']!,
          _splitOriginIdMeta,
        ),
      );
    }
    if (data.containsKey('split_document_ids')) {
      context.handle(
        _splitDocumentIdsMeta,
        splitDocumentIds.isAcceptableOrUnknown(
          data['split_document_ids']!,
          _splitDocumentIdsMeta,
        ),
      );
    }
    if (data.containsKey('deduplicated')) {
      context.handle(
        _deduplicatedMeta,
        deduplicated.isAcceptableOrUnknown(
          data['deduplicated']!,
          _deduplicatedMeta,
        ),
      );
    }
    if (data.containsKey('restored')) {
      context.handle(
        _restoredMeta,
        restored.isAcceptableOrUnknown(data['restored']!, _restoredMeta),
      );
    }
    if (data.containsKey('split')) {
      context.handle(
        _splitMeta,
        split.isAcceptableOrUnknown(data['split']!, _splitMeta),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('last_error_message')) {
      context.handle(
        _lastErrorMessageMeta,
        lastErrorMessage.isAcceptableOrUnknown(
          data['last_error_message']!,
          _lastErrorMessageMeta,
        ),
      );
    }
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    if (data.containsKey('completed_at_ms')) {
      context.handle(
        _completedAtMsMeta,
        completedAtMs.isAcceptableOrUnknown(
          data['completed_at_ms']!,
          _completedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScanUpload map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScanUpload(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      payloadPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_path'],
      )!,
      ocrContentPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ocr_content_path'],
      ),
      ocrSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ocr_sha256'],
      ),
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      filename: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filename'],
      )!,
      sourceMtime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_mtime'],
      ),
      ocrConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ocr_confidence'],
      ),
      ocrLanguage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ocr_language'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      shareBatchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}share_batch_id'],
      ),
      shareItemIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}share_item_index'],
      ),
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      bytesSent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes_sent'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_at_ms'],
      ),
      identityUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}identity_user_id'],
      ),
      identityOrigin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_origin'],
      ),
      identitySystemId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}identity_system_id'],
      ),
      serverDocumentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_document_id'],
      ),
      serverTaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_task_id'],
      ),
      splitOriginId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}split_origin_id'],
      ),
      splitDocumentIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}split_document_ids'],
      ),
      deduplicated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deduplicated'],
      )!,
      restored: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}restored'],
      )!,
      split: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}split'],
      )!,
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
      lastErrorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_message'],
      ),
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_id'],
      ),
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      completedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_at_ms'],
      ),
    );
  }

  @override
  $ScanUploadsTable createAlias(String alias) {
    return $ScanUploadsTable(attachedDatabase, alias);
  }
}

class ScanUpload extends DataClass implements Insertable<ScanUpload> {
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
  final int pageCount;
  final String state;
  final int bytesSent;
  final int attemptCount;
  final int? nextAttemptAtMs;
  final int? identityUserId;
  final String? identityOrigin;
  final int? identitySystemId;
  final int? serverDocumentId;
  final int? serverTaskId;
  final int? splitOriginId;
  final String? splitDocumentIds;
  final bool deduplicated;
  final bool restored;
  final bool split;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final String? requestId;
  final int createdAtMs;
  final int updatedAtMs;
  final int? completedAtMs;
  const ScanUpload({
    required this.id,
    required this.payloadPath,
    this.ocrContentPath,
    this.ocrSha256,
    required this.sha256,
    required this.byteSize,
    required this.mimeType,
    required this.filename,
    this.sourceMtime,
    this.ocrConfidence,
    this.ocrLanguage,
    required this.source,
    this.shareBatchId,
    this.shareItemIndex,
    required this.pageCount,
    required this.state,
    required this.bytesSent,
    required this.attemptCount,
    this.nextAttemptAtMs,
    this.identityUserId,
    this.identityOrigin,
    this.identitySystemId,
    this.serverDocumentId,
    this.serverTaskId,
    this.splitOriginId,
    this.splitDocumentIds,
    required this.deduplicated,
    required this.restored,
    required this.split,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.requestId,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.completedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['payload_path'] = Variable<String>(payloadPath);
    if (!nullToAbsent || ocrContentPath != null) {
      map['ocr_content_path'] = Variable<String>(ocrContentPath);
    }
    if (!nullToAbsent || ocrSha256 != null) {
      map['ocr_sha256'] = Variable<String>(ocrSha256);
    }
    map['sha256'] = Variable<String>(sha256);
    map['byte_size'] = Variable<int>(byteSize);
    map['mime_type'] = Variable<String>(mimeType);
    map['filename'] = Variable<String>(filename);
    if (!nullToAbsent || sourceMtime != null) {
      map['source_mtime'] = Variable<int>(sourceMtime);
    }
    if (!nullToAbsent || ocrConfidence != null) {
      map['ocr_confidence'] = Variable<double>(ocrConfidence);
    }
    if (!nullToAbsent || ocrLanguage != null) {
      map['ocr_language'] = Variable<String>(ocrLanguage);
    }
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || shareBatchId != null) {
      map['share_batch_id'] = Variable<String>(shareBatchId);
    }
    if (!nullToAbsent || shareItemIndex != null) {
      map['share_item_index'] = Variable<int>(shareItemIndex);
    }
    map['page_count'] = Variable<int>(pageCount);
    map['state'] = Variable<String>(state);
    map['bytes_sent'] = Variable<int>(bytesSent);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAtMs != null) {
      map['next_attempt_at_ms'] = Variable<int>(nextAttemptAtMs);
    }
    if (!nullToAbsent || identityUserId != null) {
      map['identity_user_id'] = Variable<int>(identityUserId);
    }
    if (!nullToAbsent || identityOrigin != null) {
      map['identity_origin'] = Variable<String>(identityOrigin);
    }
    if (!nullToAbsent || identitySystemId != null) {
      map['identity_system_id'] = Variable<int>(identitySystemId);
    }
    if (!nullToAbsent || serverDocumentId != null) {
      map['server_document_id'] = Variable<int>(serverDocumentId);
    }
    if (!nullToAbsent || serverTaskId != null) {
      map['server_task_id'] = Variable<int>(serverTaskId);
    }
    if (!nullToAbsent || splitOriginId != null) {
      map['split_origin_id'] = Variable<int>(splitOriginId);
    }
    if (!nullToAbsent || splitDocumentIds != null) {
      map['split_document_ids'] = Variable<String>(splitDocumentIds);
    }
    map['deduplicated'] = Variable<bool>(deduplicated);
    map['restored'] = Variable<bool>(restored);
    map['split'] = Variable<bool>(split);
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    if (!nullToAbsent || lastErrorMessage != null) {
      map['last_error_message'] = Variable<String>(lastErrorMessage);
    }
    if (!nullToAbsent || requestId != null) {
      map['request_id'] = Variable<String>(requestId);
    }
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    if (!nullToAbsent || completedAtMs != null) {
      map['completed_at_ms'] = Variable<int>(completedAtMs);
    }
    return map;
  }

  ScanUploadsCompanion toCompanion(bool nullToAbsent) {
    return ScanUploadsCompanion(
      id: Value(id),
      payloadPath: Value(payloadPath),
      ocrContentPath: ocrContentPath == null && nullToAbsent
          ? const Value.absent()
          : Value(ocrContentPath),
      ocrSha256: ocrSha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(ocrSha256),
      sha256: Value(sha256),
      byteSize: Value(byteSize),
      mimeType: Value(mimeType),
      filename: Value(filename),
      sourceMtime: sourceMtime == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceMtime),
      ocrConfidence: ocrConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(ocrConfidence),
      ocrLanguage: ocrLanguage == null && nullToAbsent
          ? const Value.absent()
          : Value(ocrLanguage),
      source: Value(source),
      shareBatchId: shareBatchId == null && nullToAbsent
          ? const Value.absent()
          : Value(shareBatchId),
      shareItemIndex: shareItemIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(shareItemIndex),
      pageCount: Value(pageCount),
      state: Value(state),
      bytesSent: Value(bytesSent),
      attemptCount: Value(attemptCount),
      nextAttemptAtMs: nextAttemptAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAtMs),
      identityUserId: identityUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(identityUserId),
      identityOrigin: identityOrigin == null && nullToAbsent
          ? const Value.absent()
          : Value(identityOrigin),
      identitySystemId: identitySystemId == null && nullToAbsent
          ? const Value.absent()
          : Value(identitySystemId),
      serverDocumentId: serverDocumentId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverDocumentId),
      serverTaskId: serverTaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverTaskId),
      splitOriginId: splitOriginId == null && nullToAbsent
          ? const Value.absent()
          : Value(splitOriginId),
      splitDocumentIds: splitDocumentIds == null && nullToAbsent
          ? const Value.absent()
          : Value(splitDocumentIds),
      deduplicated: Value(deduplicated),
      restored: Value(restored),
      split: Value(split),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
      lastErrorMessage: lastErrorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorMessage),
      requestId: requestId == null && nullToAbsent
          ? const Value.absent()
          : Value(requestId),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
      completedAtMs: completedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAtMs),
    );
  }

  factory ScanUpload.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScanUpload(
      id: serializer.fromJson<String>(json['id']),
      payloadPath: serializer.fromJson<String>(json['payloadPath']),
      ocrContentPath: serializer.fromJson<String?>(json['ocrContentPath']),
      ocrSha256: serializer.fromJson<String?>(json['ocrSha256']),
      sha256: serializer.fromJson<String>(json['sha256']),
      byteSize: serializer.fromJson<int>(json['byteSize']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      filename: serializer.fromJson<String>(json['filename']),
      sourceMtime: serializer.fromJson<int?>(json['sourceMtime']),
      ocrConfidence: serializer.fromJson<double?>(json['ocrConfidence']),
      ocrLanguage: serializer.fromJson<String?>(json['ocrLanguage']),
      source: serializer.fromJson<String>(json['source']),
      shareBatchId: serializer.fromJson<String?>(json['shareBatchId']),
      shareItemIndex: serializer.fromJson<int?>(json['shareItemIndex']),
      pageCount: serializer.fromJson<int>(json['pageCount']),
      state: serializer.fromJson<String>(json['state']),
      bytesSent: serializer.fromJson<int>(json['bytesSent']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAtMs: serializer.fromJson<int?>(json['nextAttemptAtMs']),
      identityUserId: serializer.fromJson<int?>(json['identityUserId']),
      identityOrigin: serializer.fromJson<String?>(json['identityOrigin']),
      identitySystemId: serializer.fromJson<int?>(json['identitySystemId']),
      serverDocumentId: serializer.fromJson<int?>(json['serverDocumentId']),
      serverTaskId: serializer.fromJson<int?>(json['serverTaskId']),
      splitOriginId: serializer.fromJson<int?>(json['splitOriginId']),
      splitDocumentIds: serializer.fromJson<String?>(json['splitDocumentIds']),
      deduplicated: serializer.fromJson<bool>(json['deduplicated']),
      restored: serializer.fromJson<bool>(json['restored']),
      split: serializer.fromJson<bool>(json['split']),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      lastErrorMessage: serializer.fromJson<String?>(json['lastErrorMessage']),
      requestId: serializer.fromJson<String?>(json['requestId']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      completedAtMs: serializer.fromJson<int?>(json['completedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'payloadPath': serializer.toJson<String>(payloadPath),
      'ocrContentPath': serializer.toJson<String?>(ocrContentPath),
      'ocrSha256': serializer.toJson<String?>(ocrSha256),
      'sha256': serializer.toJson<String>(sha256),
      'byteSize': serializer.toJson<int>(byteSize),
      'mimeType': serializer.toJson<String>(mimeType),
      'filename': serializer.toJson<String>(filename),
      'sourceMtime': serializer.toJson<int?>(sourceMtime),
      'ocrConfidence': serializer.toJson<double?>(ocrConfidence),
      'ocrLanguage': serializer.toJson<String?>(ocrLanguage),
      'source': serializer.toJson<String>(source),
      'shareBatchId': serializer.toJson<String?>(shareBatchId),
      'shareItemIndex': serializer.toJson<int?>(shareItemIndex),
      'pageCount': serializer.toJson<int>(pageCount),
      'state': serializer.toJson<String>(state),
      'bytesSent': serializer.toJson<int>(bytesSent),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAtMs': serializer.toJson<int?>(nextAttemptAtMs),
      'identityUserId': serializer.toJson<int?>(identityUserId),
      'identityOrigin': serializer.toJson<String?>(identityOrigin),
      'identitySystemId': serializer.toJson<int?>(identitySystemId),
      'serverDocumentId': serializer.toJson<int?>(serverDocumentId),
      'serverTaskId': serializer.toJson<int?>(serverTaskId),
      'splitOriginId': serializer.toJson<int?>(splitOriginId),
      'splitDocumentIds': serializer.toJson<String?>(splitDocumentIds),
      'deduplicated': serializer.toJson<bool>(deduplicated),
      'restored': serializer.toJson<bool>(restored),
      'split': serializer.toJson<bool>(split),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'lastErrorMessage': serializer.toJson<String?>(lastErrorMessage),
      'requestId': serializer.toJson<String?>(requestId),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'completedAtMs': serializer.toJson<int?>(completedAtMs),
    };
  }

  ScanUpload copyWith({
    String? id,
    String? payloadPath,
    Value<String?> ocrContentPath = const Value.absent(),
    Value<String?> ocrSha256 = const Value.absent(),
    String? sha256,
    int? byteSize,
    String? mimeType,
    String? filename,
    Value<int?> sourceMtime = const Value.absent(),
    Value<double?> ocrConfidence = const Value.absent(),
    Value<String?> ocrLanguage = const Value.absent(),
    String? source,
    Value<String?> shareBatchId = const Value.absent(),
    Value<int?> shareItemIndex = const Value.absent(),
    int? pageCount,
    String? state,
    int? bytesSent,
    int? attemptCount,
    Value<int?> nextAttemptAtMs = const Value.absent(),
    Value<int?> identityUserId = const Value.absent(),
    Value<String?> identityOrigin = const Value.absent(),
    Value<int?> identitySystemId = const Value.absent(),
    Value<int?> serverDocumentId = const Value.absent(),
    Value<int?> serverTaskId = const Value.absent(),
    Value<int?> splitOriginId = const Value.absent(),
    Value<String?> splitDocumentIds = const Value.absent(),
    bool? deduplicated,
    bool? restored,
    bool? split,
    Value<String?> lastErrorCode = const Value.absent(),
    Value<String?> lastErrorMessage = const Value.absent(),
    Value<String?> requestId = const Value.absent(),
    int? createdAtMs,
    int? updatedAtMs,
    Value<int?> completedAtMs = const Value.absent(),
  }) => ScanUpload(
    id: id ?? this.id,
    payloadPath: payloadPath ?? this.payloadPath,
    ocrContentPath: ocrContentPath.present
        ? ocrContentPath.value
        : this.ocrContentPath,
    ocrSha256: ocrSha256.present ? ocrSha256.value : this.ocrSha256,
    sha256: sha256 ?? this.sha256,
    byteSize: byteSize ?? this.byteSize,
    mimeType: mimeType ?? this.mimeType,
    filename: filename ?? this.filename,
    sourceMtime: sourceMtime.present ? sourceMtime.value : this.sourceMtime,
    ocrConfidence: ocrConfidence.present
        ? ocrConfidence.value
        : this.ocrConfidence,
    ocrLanguage: ocrLanguage.present ? ocrLanguage.value : this.ocrLanguage,
    source: source ?? this.source,
    shareBatchId: shareBatchId.present ? shareBatchId.value : this.shareBatchId,
    shareItemIndex: shareItemIndex.present
        ? shareItemIndex.value
        : this.shareItemIndex,
    pageCount: pageCount ?? this.pageCount,
    state: state ?? this.state,
    bytesSent: bytesSent ?? this.bytesSent,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAtMs: nextAttemptAtMs.present
        ? nextAttemptAtMs.value
        : this.nextAttemptAtMs,
    identityUserId: identityUserId.present
        ? identityUserId.value
        : this.identityUserId,
    identityOrigin: identityOrigin.present
        ? identityOrigin.value
        : this.identityOrigin,
    identitySystemId: identitySystemId.present
        ? identitySystemId.value
        : this.identitySystemId,
    serverDocumentId: serverDocumentId.present
        ? serverDocumentId.value
        : this.serverDocumentId,
    serverTaskId: serverTaskId.present ? serverTaskId.value : this.serverTaskId,
    splitOriginId: splitOriginId.present
        ? splitOriginId.value
        : this.splitOriginId,
    splitDocumentIds: splitDocumentIds.present
        ? splitDocumentIds.value
        : this.splitDocumentIds,
    deduplicated: deduplicated ?? this.deduplicated,
    restored: restored ?? this.restored,
    split: split ?? this.split,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
    lastErrorMessage: lastErrorMessage.present
        ? lastErrorMessage.value
        : this.lastErrorMessage,
    requestId: requestId.present ? requestId.value : this.requestId,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    completedAtMs: completedAtMs.present
        ? completedAtMs.value
        : this.completedAtMs,
  );
  ScanUpload copyWithCompanion(ScanUploadsCompanion data) {
    return ScanUpload(
      id: data.id.present ? data.id.value : this.id,
      payloadPath: data.payloadPath.present
          ? data.payloadPath.value
          : this.payloadPath,
      ocrContentPath: data.ocrContentPath.present
          ? data.ocrContentPath.value
          : this.ocrContentPath,
      ocrSha256: data.ocrSha256.present ? data.ocrSha256.value : this.ocrSha256,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      filename: data.filename.present ? data.filename.value : this.filename,
      sourceMtime: data.sourceMtime.present
          ? data.sourceMtime.value
          : this.sourceMtime,
      ocrConfidence: data.ocrConfidence.present
          ? data.ocrConfidence.value
          : this.ocrConfidence,
      ocrLanguage: data.ocrLanguage.present
          ? data.ocrLanguage.value
          : this.ocrLanguage,
      source: data.source.present ? data.source.value : this.source,
      shareBatchId: data.shareBatchId.present
          ? data.shareBatchId.value
          : this.shareBatchId,
      shareItemIndex: data.shareItemIndex.present
          ? data.shareItemIndex.value
          : this.shareItemIndex,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      state: data.state.present ? data.state.value : this.state,
      bytesSent: data.bytesSent.present ? data.bytesSent.value : this.bytesSent,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAtMs: data.nextAttemptAtMs.present
          ? data.nextAttemptAtMs.value
          : this.nextAttemptAtMs,
      identityUserId: data.identityUserId.present
          ? data.identityUserId.value
          : this.identityUserId,
      identityOrigin: data.identityOrigin.present
          ? data.identityOrigin.value
          : this.identityOrigin,
      identitySystemId: data.identitySystemId.present
          ? data.identitySystemId.value
          : this.identitySystemId,
      serverDocumentId: data.serverDocumentId.present
          ? data.serverDocumentId.value
          : this.serverDocumentId,
      serverTaskId: data.serverTaskId.present
          ? data.serverTaskId.value
          : this.serverTaskId,
      splitOriginId: data.splitOriginId.present
          ? data.splitOriginId.value
          : this.splitOriginId,
      splitDocumentIds: data.splitDocumentIds.present
          ? data.splitDocumentIds.value
          : this.splitDocumentIds,
      deduplicated: data.deduplicated.present
          ? data.deduplicated.value
          : this.deduplicated,
      restored: data.restored.present ? data.restored.value : this.restored,
      split: data.split.present ? data.split.value : this.split,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
      lastErrorMessage: data.lastErrorMessage.present
          ? data.lastErrorMessage.value
          : this.lastErrorMessage,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      completedAtMs: data.completedAtMs.present
          ? data.completedAtMs.value
          : this.completedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScanUpload(')
          ..write('id: $id, ')
          ..write('payloadPath: $payloadPath, ')
          ..write('ocrContentPath: $ocrContentPath, ')
          ..write('ocrSha256: $ocrSha256, ')
          ..write('sha256: $sha256, ')
          ..write('byteSize: $byteSize, ')
          ..write('mimeType: $mimeType, ')
          ..write('filename: $filename, ')
          ..write('sourceMtime: $sourceMtime, ')
          ..write('ocrConfidence: $ocrConfidence, ')
          ..write('ocrLanguage: $ocrLanguage, ')
          ..write('source: $source, ')
          ..write('shareBatchId: $shareBatchId, ')
          ..write('shareItemIndex: $shareItemIndex, ')
          ..write('pageCount: $pageCount, ')
          ..write('state: $state, ')
          ..write('bytesSent: $bytesSent, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAtMs: $nextAttemptAtMs, ')
          ..write('identityUserId: $identityUserId, ')
          ..write('identityOrigin: $identityOrigin, ')
          ..write('identitySystemId: $identitySystemId, ')
          ..write('serverDocumentId: $serverDocumentId, ')
          ..write('serverTaskId: $serverTaskId, ')
          ..write('splitOriginId: $splitOriginId, ')
          ..write('splitDocumentIds: $splitDocumentIds, ')
          ..write('deduplicated: $deduplicated, ')
          ..write('restored: $restored, ')
          ..write('split: $split, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorMessage: $lastErrorMessage, ')
          ..write('requestId: $requestId, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('completedAtMs: $completedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    payloadPath,
    ocrContentPath,
    ocrSha256,
    sha256,
    byteSize,
    mimeType,
    filename,
    sourceMtime,
    ocrConfidence,
    ocrLanguage,
    source,
    shareBatchId,
    shareItemIndex,
    pageCount,
    state,
    bytesSent,
    attemptCount,
    nextAttemptAtMs,
    identityUserId,
    identityOrigin,
    identitySystemId,
    serverDocumentId,
    serverTaskId,
    splitOriginId,
    splitDocumentIds,
    deduplicated,
    restored,
    split,
    lastErrorCode,
    lastErrorMessage,
    requestId,
    createdAtMs,
    updatedAtMs,
    completedAtMs,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScanUpload &&
          other.id == this.id &&
          other.payloadPath == this.payloadPath &&
          other.ocrContentPath == this.ocrContentPath &&
          other.ocrSha256 == this.ocrSha256 &&
          other.sha256 == this.sha256 &&
          other.byteSize == this.byteSize &&
          other.mimeType == this.mimeType &&
          other.filename == this.filename &&
          other.sourceMtime == this.sourceMtime &&
          other.ocrConfidence == this.ocrConfidence &&
          other.ocrLanguage == this.ocrLanguage &&
          other.source == this.source &&
          other.shareBatchId == this.shareBatchId &&
          other.shareItemIndex == this.shareItemIndex &&
          other.pageCount == this.pageCount &&
          other.state == this.state &&
          other.bytesSent == this.bytesSent &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAtMs == this.nextAttemptAtMs &&
          other.identityUserId == this.identityUserId &&
          other.identityOrigin == this.identityOrigin &&
          other.identitySystemId == this.identitySystemId &&
          other.serverDocumentId == this.serverDocumentId &&
          other.serverTaskId == this.serverTaskId &&
          other.splitOriginId == this.splitOriginId &&
          other.splitDocumentIds == this.splitDocumentIds &&
          other.deduplicated == this.deduplicated &&
          other.restored == this.restored &&
          other.split == this.split &&
          other.lastErrorCode == this.lastErrorCode &&
          other.lastErrorMessage == this.lastErrorMessage &&
          other.requestId == this.requestId &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs &&
          other.completedAtMs == this.completedAtMs);
}

class ScanUploadsCompanion extends UpdateCompanion<ScanUpload> {
  final Value<String> id;
  final Value<String> payloadPath;
  final Value<String?> ocrContentPath;
  final Value<String?> ocrSha256;
  final Value<String> sha256;
  final Value<int> byteSize;
  final Value<String> mimeType;
  final Value<String> filename;
  final Value<int?> sourceMtime;
  final Value<double?> ocrConfidence;
  final Value<String?> ocrLanguage;
  final Value<String> source;
  final Value<String?> shareBatchId;
  final Value<int?> shareItemIndex;
  final Value<int> pageCount;
  final Value<String> state;
  final Value<int> bytesSent;
  final Value<int> attemptCount;
  final Value<int?> nextAttemptAtMs;
  final Value<int?> identityUserId;
  final Value<String?> identityOrigin;
  final Value<int?> identitySystemId;
  final Value<int?> serverDocumentId;
  final Value<int?> serverTaskId;
  final Value<int?> splitOriginId;
  final Value<String?> splitDocumentIds;
  final Value<bool> deduplicated;
  final Value<bool> restored;
  final Value<bool> split;
  final Value<String?> lastErrorCode;
  final Value<String?> lastErrorMessage;
  final Value<String?> requestId;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<int?> completedAtMs;
  final Value<int> rowid;
  const ScanUploadsCompanion({
    this.id = const Value.absent(),
    this.payloadPath = const Value.absent(),
    this.ocrContentPath = const Value.absent(),
    this.ocrSha256 = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.filename = const Value.absent(),
    this.sourceMtime = const Value.absent(),
    this.ocrConfidence = const Value.absent(),
    this.ocrLanguage = const Value.absent(),
    this.source = const Value.absent(),
    this.shareBatchId = const Value.absent(),
    this.shareItemIndex = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.state = const Value.absent(),
    this.bytesSent = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAtMs = const Value.absent(),
    this.identityUserId = const Value.absent(),
    this.identityOrigin = const Value.absent(),
    this.identitySystemId = const Value.absent(),
    this.serverDocumentId = const Value.absent(),
    this.serverTaskId = const Value.absent(),
    this.splitOriginId = const Value.absent(),
    this.splitDocumentIds = const Value.absent(),
    this.deduplicated = const Value.absent(),
    this.restored = const Value.absent(),
    this.split = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorMessage = const Value.absent(),
    this.requestId = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.completedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScanUploadsCompanion.insert({
    required String id,
    required String payloadPath,
    this.ocrContentPath = const Value.absent(),
    this.ocrSha256 = const Value.absent(),
    required String sha256,
    required int byteSize,
    required String mimeType,
    required String filename,
    this.sourceMtime = const Value.absent(),
    this.ocrConfidence = const Value.absent(),
    this.ocrLanguage = const Value.absent(),
    required String source,
    this.shareBatchId = const Value.absent(),
    this.shareItemIndex = const Value.absent(),
    required int pageCount,
    required String state,
    this.bytesSent = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAtMs = const Value.absent(),
    this.identityUserId = const Value.absent(),
    this.identityOrigin = const Value.absent(),
    this.identitySystemId = const Value.absent(),
    this.serverDocumentId = const Value.absent(),
    this.serverTaskId = const Value.absent(),
    this.splitOriginId = const Value.absent(),
    this.splitDocumentIds = const Value.absent(),
    this.deduplicated = const Value.absent(),
    this.restored = const Value.absent(),
    this.split = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorMessage = const Value.absent(),
    this.requestId = const Value.absent(),
    required int createdAtMs,
    required int updatedAtMs,
    this.completedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       payloadPath = Value(payloadPath),
       sha256 = Value(sha256),
       byteSize = Value(byteSize),
       mimeType = Value(mimeType),
       filename = Value(filename),
       source = Value(source),
       pageCount = Value(pageCount),
       state = Value(state),
       createdAtMs = Value(createdAtMs),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<ScanUpload> custom({
    Expression<String>? id,
    Expression<String>? payloadPath,
    Expression<String>? ocrContentPath,
    Expression<String>? ocrSha256,
    Expression<String>? sha256,
    Expression<int>? byteSize,
    Expression<String>? mimeType,
    Expression<String>? filename,
    Expression<int>? sourceMtime,
    Expression<double>? ocrConfidence,
    Expression<String>? ocrLanguage,
    Expression<String>? source,
    Expression<String>? shareBatchId,
    Expression<int>? shareItemIndex,
    Expression<int>? pageCount,
    Expression<String>? state,
    Expression<int>? bytesSent,
    Expression<int>? attemptCount,
    Expression<int>? nextAttemptAtMs,
    Expression<int>? identityUserId,
    Expression<String>? identityOrigin,
    Expression<int>? identitySystemId,
    Expression<int>? serverDocumentId,
    Expression<int>? serverTaskId,
    Expression<int>? splitOriginId,
    Expression<String>? splitDocumentIds,
    Expression<bool>? deduplicated,
    Expression<bool>? restored,
    Expression<bool>? split,
    Expression<String>? lastErrorCode,
    Expression<String>? lastErrorMessage,
    Expression<String>? requestId,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<int>? completedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payloadPath != null) 'payload_path': payloadPath,
      if (ocrContentPath != null) 'ocr_content_path': ocrContentPath,
      if (ocrSha256 != null) 'ocr_sha256': ocrSha256,
      if (sha256 != null) 'sha256': sha256,
      if (byteSize != null) 'byte_size': byteSize,
      if (mimeType != null) 'mime_type': mimeType,
      if (filename != null) 'filename': filename,
      if (sourceMtime != null) 'source_mtime': sourceMtime,
      if (ocrConfidence != null) 'ocr_confidence': ocrConfidence,
      if (ocrLanguage != null) 'ocr_language': ocrLanguage,
      if (source != null) 'source': source,
      if (shareBatchId != null) 'share_batch_id': shareBatchId,
      if (shareItemIndex != null) 'share_item_index': shareItemIndex,
      if (pageCount != null) 'page_count': pageCount,
      if (state != null) 'state': state,
      if (bytesSent != null) 'bytes_sent': bytesSent,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAtMs != null) 'next_attempt_at_ms': nextAttemptAtMs,
      if (identityUserId != null) 'identity_user_id': identityUserId,
      if (identityOrigin != null) 'identity_origin': identityOrigin,
      if (identitySystemId != null) 'identity_system_id': identitySystemId,
      if (serverDocumentId != null) 'server_document_id': serverDocumentId,
      if (serverTaskId != null) 'server_task_id': serverTaskId,
      if (splitOriginId != null) 'split_origin_id': splitOriginId,
      if (splitDocumentIds != null) 'split_document_ids': splitDocumentIds,
      if (deduplicated != null) 'deduplicated': deduplicated,
      if (restored != null) 'restored': restored,
      if (split != null) 'split': split,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (lastErrorMessage != null) 'last_error_message': lastErrorMessage,
      if (requestId != null) 'request_id': requestId,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (completedAtMs != null) 'completed_at_ms': completedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScanUploadsCompanion copyWith({
    Value<String>? id,
    Value<String>? payloadPath,
    Value<String?>? ocrContentPath,
    Value<String?>? ocrSha256,
    Value<String>? sha256,
    Value<int>? byteSize,
    Value<String>? mimeType,
    Value<String>? filename,
    Value<int?>? sourceMtime,
    Value<double?>? ocrConfidence,
    Value<String?>? ocrLanguage,
    Value<String>? source,
    Value<String?>? shareBatchId,
    Value<int?>? shareItemIndex,
    Value<int>? pageCount,
    Value<String>? state,
    Value<int>? bytesSent,
    Value<int>? attemptCount,
    Value<int?>? nextAttemptAtMs,
    Value<int?>? identityUserId,
    Value<String?>? identityOrigin,
    Value<int?>? identitySystemId,
    Value<int?>? serverDocumentId,
    Value<int?>? serverTaskId,
    Value<int?>? splitOriginId,
    Value<String?>? splitDocumentIds,
    Value<bool>? deduplicated,
    Value<bool>? restored,
    Value<bool>? split,
    Value<String?>? lastErrorCode,
    Value<String?>? lastErrorMessage,
    Value<String?>? requestId,
    Value<int>? createdAtMs,
    Value<int>? updatedAtMs,
    Value<int?>? completedAtMs,
    Value<int>? rowid,
  }) {
    return ScanUploadsCompanion(
      id: id ?? this.id,
      payloadPath: payloadPath ?? this.payloadPath,
      ocrContentPath: ocrContentPath ?? this.ocrContentPath,
      ocrSha256: ocrSha256 ?? this.ocrSha256,
      sha256: sha256 ?? this.sha256,
      byteSize: byteSize ?? this.byteSize,
      mimeType: mimeType ?? this.mimeType,
      filename: filename ?? this.filename,
      sourceMtime: sourceMtime ?? this.sourceMtime,
      ocrConfidence: ocrConfidence ?? this.ocrConfidence,
      ocrLanguage: ocrLanguage ?? this.ocrLanguage,
      source: source ?? this.source,
      shareBatchId: shareBatchId ?? this.shareBatchId,
      shareItemIndex: shareItemIndex ?? this.shareItemIndex,
      pageCount: pageCount ?? this.pageCount,
      state: state ?? this.state,
      bytesSent: bytesSent ?? this.bytesSent,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAtMs: nextAttemptAtMs ?? this.nextAttemptAtMs,
      identityUserId: identityUserId ?? this.identityUserId,
      identityOrigin: identityOrigin ?? this.identityOrigin,
      identitySystemId: identitySystemId ?? this.identitySystemId,
      serverDocumentId: serverDocumentId ?? this.serverDocumentId,
      serverTaskId: serverTaskId ?? this.serverTaskId,
      splitOriginId: splitOriginId ?? this.splitOriginId,
      splitDocumentIds: splitDocumentIds ?? this.splitDocumentIds,
      deduplicated: deduplicated ?? this.deduplicated,
      restored: restored ?? this.restored,
      split: split ?? this.split,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      lastErrorMessage: lastErrorMessage ?? this.lastErrorMessage,
      requestId: requestId ?? this.requestId,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      completedAtMs: completedAtMs ?? this.completedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (payloadPath.present) {
      map['payload_path'] = Variable<String>(payloadPath.value);
    }
    if (ocrContentPath.present) {
      map['ocr_content_path'] = Variable<String>(ocrContentPath.value);
    }
    if (ocrSha256.present) {
      map['ocr_sha256'] = Variable<String>(ocrSha256.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (filename.present) {
      map['filename'] = Variable<String>(filename.value);
    }
    if (sourceMtime.present) {
      map['source_mtime'] = Variable<int>(sourceMtime.value);
    }
    if (ocrConfidence.present) {
      map['ocr_confidence'] = Variable<double>(ocrConfidence.value);
    }
    if (ocrLanguage.present) {
      map['ocr_language'] = Variable<String>(ocrLanguage.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (shareBatchId.present) {
      map['share_batch_id'] = Variable<String>(shareBatchId.value);
    }
    if (shareItemIndex.present) {
      map['share_item_index'] = Variable<int>(shareItemIndex.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (bytesSent.present) {
      map['bytes_sent'] = Variable<int>(bytesSent.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAtMs.present) {
      map['next_attempt_at_ms'] = Variable<int>(nextAttemptAtMs.value);
    }
    if (identityUserId.present) {
      map['identity_user_id'] = Variable<int>(identityUserId.value);
    }
    if (identityOrigin.present) {
      map['identity_origin'] = Variable<String>(identityOrigin.value);
    }
    if (identitySystemId.present) {
      map['identity_system_id'] = Variable<int>(identitySystemId.value);
    }
    if (serverDocumentId.present) {
      map['server_document_id'] = Variable<int>(serverDocumentId.value);
    }
    if (serverTaskId.present) {
      map['server_task_id'] = Variable<int>(serverTaskId.value);
    }
    if (splitOriginId.present) {
      map['split_origin_id'] = Variable<int>(splitOriginId.value);
    }
    if (splitDocumentIds.present) {
      map['split_document_ids'] = Variable<String>(splitDocumentIds.value);
    }
    if (deduplicated.present) {
      map['deduplicated'] = Variable<bool>(deduplicated.value);
    }
    if (restored.present) {
      map['restored'] = Variable<bool>(restored.value);
    }
    if (split.present) {
      map['split'] = Variable<bool>(split.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (lastErrorMessage.present) {
      map['last_error_message'] = Variable<String>(lastErrorMessage.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<String>(requestId.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (completedAtMs.present) {
      map['completed_at_ms'] = Variable<int>(completedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScanUploadsCompanion(')
          ..write('id: $id, ')
          ..write('payloadPath: $payloadPath, ')
          ..write('ocrContentPath: $ocrContentPath, ')
          ..write('ocrSha256: $ocrSha256, ')
          ..write('sha256: $sha256, ')
          ..write('byteSize: $byteSize, ')
          ..write('mimeType: $mimeType, ')
          ..write('filename: $filename, ')
          ..write('sourceMtime: $sourceMtime, ')
          ..write('ocrConfidence: $ocrConfidence, ')
          ..write('ocrLanguage: $ocrLanguage, ')
          ..write('source: $source, ')
          ..write('shareBatchId: $shareBatchId, ')
          ..write('shareItemIndex: $shareItemIndex, ')
          ..write('pageCount: $pageCount, ')
          ..write('state: $state, ')
          ..write('bytesSent: $bytesSent, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAtMs: $nextAttemptAtMs, ')
          ..write('identityUserId: $identityUserId, ')
          ..write('identityOrigin: $identityOrigin, ')
          ..write('identitySystemId: $identitySystemId, ')
          ..write('serverDocumentId: $serverDocumentId, ')
          ..write('serverTaskId: $serverTaskId, ')
          ..write('splitOriginId: $splitOriginId, ')
          ..write('splitDocumentIds: $splitDocumentIds, ')
          ..write('deduplicated: $deduplicated, ')
          ..write('restored: $restored, ')
          ..write('split: $split, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorMessage: $lastErrorMessage, ')
          ..write('requestId: $requestId, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('completedAtMs: $completedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ShareReceiptsTable extends ShareReceipts
    with TableInfo<$ShareReceiptsTable, ShareReceipt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShareReceiptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemIndexMeta = const VerificationMeta(
    'itemIndex',
  );
  @override
  late final GeneratedColumn<int> itemIndex = GeneratedColumn<int>(
    'item_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  @override
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _queueIdMeta = const VerificationMeta(
    'queueId',
  );
  @override
  late final GeneratedColumn<String> queueId = GeneratedColumn<String>(
    'queue_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    batchId,
    itemIndex,
    sha256,
    byteSize,
    mimeType,
    queueId,
    status,
    errorCode,
    createdAtMs,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'share_receipts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShareReceipt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    if (data.containsKey('item_index')) {
      context.handle(
        _itemIndexMeta,
        itemIndex.isAcceptableOrUnknown(data['item_index']!, _itemIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIndexMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_byteSizeMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('queue_id')) {
      context.handle(
        _queueIdMeta,
        queueId.isAcceptableOrUnknown(data['queue_id']!, _queueIdMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {batchId, itemIndex};
  @override
  ShareReceipt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShareReceipt(
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      )!,
      itemIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}item_index'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      queueId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}queue_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $ShareReceiptsTable createAlias(String alias) {
    return $ShareReceiptsTable(attachedDatabase, alias);
  }
}

class ShareReceipt extends DataClass implements Insertable<ShareReceipt> {
  final String batchId;
  final int itemIndex;
  final String sha256;
  final int byteSize;
  final String mimeType;
  final String? queueId;
  final String status;
  final String? errorCode;
  final int createdAtMs;
  final int updatedAtMs;
  const ShareReceipt({
    required this.batchId,
    required this.itemIndex,
    required this.sha256,
    required this.byteSize,
    required this.mimeType,
    this.queueId,
    required this.status,
    this.errorCode,
    required this.createdAtMs,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['batch_id'] = Variable<String>(batchId);
    map['item_index'] = Variable<int>(itemIndex);
    map['sha256'] = Variable<String>(sha256);
    map['byte_size'] = Variable<int>(byteSize);
    map['mime_type'] = Variable<String>(mimeType);
    if (!nullToAbsent || queueId != null) {
      map['queue_id'] = Variable<String>(queueId);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  ShareReceiptsCompanion toCompanion(bool nullToAbsent) {
    return ShareReceiptsCompanion(
      batchId: Value(batchId),
      itemIndex: Value(itemIndex),
      sha256: Value(sha256),
      byteSize: Value(byteSize),
      mimeType: Value(mimeType),
      queueId: queueId == null && nullToAbsent
          ? const Value.absent()
          : Value(queueId),
      status: Value(status),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory ShareReceipt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShareReceipt(
      batchId: serializer.fromJson<String>(json['batchId']),
      itemIndex: serializer.fromJson<int>(json['itemIndex']),
      sha256: serializer.fromJson<String>(json['sha256']),
      byteSize: serializer.fromJson<int>(json['byteSize']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      queueId: serializer.fromJson<String?>(json['queueId']),
      status: serializer.fromJson<String>(json['status']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'batchId': serializer.toJson<String>(batchId),
      'itemIndex': serializer.toJson<int>(itemIndex),
      'sha256': serializer.toJson<String>(sha256),
      'byteSize': serializer.toJson<int>(byteSize),
      'mimeType': serializer.toJson<String>(mimeType),
      'queueId': serializer.toJson<String?>(queueId),
      'status': serializer.toJson<String>(status),
      'errorCode': serializer.toJson<String?>(errorCode),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  ShareReceipt copyWith({
    String? batchId,
    int? itemIndex,
    String? sha256,
    int? byteSize,
    String? mimeType,
    Value<String?> queueId = const Value.absent(),
    String? status,
    Value<String?> errorCode = const Value.absent(),
    int? createdAtMs,
    int? updatedAtMs,
  }) => ShareReceipt(
    batchId: batchId ?? this.batchId,
    itemIndex: itemIndex ?? this.itemIndex,
    sha256: sha256 ?? this.sha256,
    byteSize: byteSize ?? this.byteSize,
    mimeType: mimeType ?? this.mimeType,
    queueId: queueId.present ? queueId.value : this.queueId,
    status: status ?? this.status,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  ShareReceipt copyWithCompanion(ShareReceiptsCompanion data) {
    return ShareReceipt(
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      itemIndex: data.itemIndex.present ? data.itemIndex.value : this.itemIndex,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      queueId: data.queueId.present ? data.queueId.value : this.queueId,
      status: data.status.present ? data.status.value : this.status,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShareReceipt(')
          ..write('batchId: $batchId, ')
          ..write('itemIndex: $itemIndex, ')
          ..write('sha256: $sha256, ')
          ..write('byteSize: $byteSize, ')
          ..write('mimeType: $mimeType, ')
          ..write('queueId: $queueId, ')
          ..write('status: $status, ')
          ..write('errorCode: $errorCode, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    batchId,
    itemIndex,
    sha256,
    byteSize,
    mimeType,
    queueId,
    status,
    errorCode,
    createdAtMs,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShareReceipt &&
          other.batchId == this.batchId &&
          other.itemIndex == this.itemIndex &&
          other.sha256 == this.sha256 &&
          other.byteSize == this.byteSize &&
          other.mimeType == this.mimeType &&
          other.queueId == this.queueId &&
          other.status == this.status &&
          other.errorCode == this.errorCode &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs);
}

class ShareReceiptsCompanion extends UpdateCompanion<ShareReceipt> {
  final Value<String> batchId;
  final Value<int> itemIndex;
  final Value<String> sha256;
  final Value<int> byteSize;
  final Value<String> mimeType;
  final Value<String?> queueId;
  final Value<String> status;
  final Value<String?> errorCode;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const ShareReceiptsCompanion({
    this.batchId = const Value.absent(),
    this.itemIndex = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.queueId = const Value.absent(),
    this.status = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShareReceiptsCompanion.insert({
    required String batchId,
    required int itemIndex,
    required String sha256,
    required int byteSize,
    required String mimeType,
    this.queueId = const Value.absent(),
    required String status,
    this.errorCode = const Value.absent(),
    required int createdAtMs,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : batchId = Value(batchId),
       itemIndex = Value(itemIndex),
       sha256 = Value(sha256),
       byteSize = Value(byteSize),
       mimeType = Value(mimeType),
       status = Value(status),
       createdAtMs = Value(createdAtMs),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<ShareReceipt> custom({
    Expression<String>? batchId,
    Expression<int>? itemIndex,
    Expression<String>? sha256,
    Expression<int>? byteSize,
    Expression<String>? mimeType,
    Expression<String>? queueId,
    Expression<String>? status,
    Expression<String>? errorCode,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (batchId != null) 'batch_id': batchId,
      if (itemIndex != null) 'item_index': itemIndex,
      if (sha256 != null) 'sha256': sha256,
      if (byteSize != null) 'byte_size': byteSize,
      if (mimeType != null) 'mime_type': mimeType,
      if (queueId != null) 'queue_id': queueId,
      if (status != null) 'status': status,
      if (errorCode != null) 'error_code': errorCode,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShareReceiptsCompanion copyWith({
    Value<String>? batchId,
    Value<int>? itemIndex,
    Value<String>? sha256,
    Value<int>? byteSize,
    Value<String>? mimeType,
    Value<String?>? queueId,
    Value<String>? status,
    Value<String?>? errorCode,
    Value<int>? createdAtMs,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return ShareReceiptsCompanion(
      batchId: batchId ?? this.batchId,
      itemIndex: itemIndex ?? this.itemIndex,
      sha256: sha256 ?? this.sha256,
      byteSize: byteSize ?? this.byteSize,
      mimeType: mimeType ?? this.mimeType,
      queueId: queueId ?? this.queueId,
      status: status ?? this.status,
      errorCode: errorCode ?? this.errorCode,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (itemIndex.present) {
      map['item_index'] = Variable<int>(itemIndex.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (queueId.present) {
      map['queue_id'] = Variable<String>(queueId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShareReceiptsCompanion(')
          ..write('batchId: $batchId, ')
          ..write('itemIndex: $itemIndex, ')
          ..write('sha256: $sha256, ')
          ..write('byteSize: $byteSize, ')
          ..write('mimeType: $mimeType, ')
          ..write('queueId: $queueId, ')
          ..write('status: $status, ')
          ..write('errorCode: $errorCode, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CaptureReceiptsTable extends CaptureReceipts
    with TableInfo<$CaptureReceiptsTable, CaptureReceipt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CaptureReceiptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _captureIdMeta = const VerificationMeta(
    'captureId',
  );
  @override
  late final GeneratedColumn<String> captureId = GeneratedColumn<String>(
    'capture_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _queueIdMeta = const VerificationMeta(
    'queueId',
  );
  @override
  late final GeneratedColumn<String> queueId = GeneratedColumn<String>(
    'queue_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [captureId, queueId, createdAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'capture_receipts';
  @override
  VerificationContext validateIntegrity(
    Insertable<CaptureReceipt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('capture_id')) {
      context.handle(
        _captureIdMeta,
        captureId.isAcceptableOrUnknown(data['capture_id']!, _captureIdMeta),
      );
    } else if (isInserting) {
      context.missing(_captureIdMeta);
    }
    if (data.containsKey('queue_id')) {
      context.handle(
        _queueIdMeta,
        queueId.isAcceptableOrUnknown(data['queue_id']!, _queueIdMeta),
      );
    } else if (isInserting) {
      context.missing(_queueIdMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {captureId};
  @override
  CaptureReceipt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CaptureReceipt(
      captureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capture_id'],
      )!,
      queueId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}queue_id'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
    );
  }

  @override
  $CaptureReceiptsTable createAlias(String alias) {
    return $CaptureReceiptsTable(attachedDatabase, alias);
  }
}

class CaptureReceipt extends DataClass implements Insertable<CaptureReceipt> {
  final String captureId;
  final String queueId;
  final int createdAtMs;
  const CaptureReceipt({
    required this.captureId,
    required this.queueId,
    required this.createdAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['capture_id'] = Variable<String>(captureId);
    map['queue_id'] = Variable<String>(queueId);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    return map;
  }

  CaptureReceiptsCompanion toCompanion(bool nullToAbsent) {
    return CaptureReceiptsCompanion(
      captureId: Value(captureId),
      queueId: Value(queueId),
      createdAtMs: Value(createdAtMs),
    );
  }

  factory CaptureReceipt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CaptureReceipt(
      captureId: serializer.fromJson<String>(json['captureId']),
      queueId: serializer.fromJson<String>(json['queueId']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'captureId': serializer.toJson<String>(captureId),
      'queueId': serializer.toJson<String>(queueId),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
    };
  }

  CaptureReceipt copyWith({
    String? captureId,
    String? queueId,
    int? createdAtMs,
  }) => CaptureReceipt(
    captureId: captureId ?? this.captureId,
    queueId: queueId ?? this.queueId,
    createdAtMs: createdAtMs ?? this.createdAtMs,
  );
  CaptureReceipt copyWithCompanion(CaptureReceiptsCompanion data) {
    return CaptureReceipt(
      captureId: data.captureId.present ? data.captureId.value : this.captureId,
      queueId: data.queueId.present ? data.queueId.value : this.queueId,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CaptureReceipt(')
          ..write('captureId: $captureId, ')
          ..write('queueId: $queueId, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(captureId, queueId, createdAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CaptureReceipt &&
          other.captureId == this.captureId &&
          other.queueId == this.queueId &&
          other.createdAtMs == this.createdAtMs);
}

class CaptureReceiptsCompanion extends UpdateCompanion<CaptureReceipt> {
  final Value<String> captureId;
  final Value<String> queueId;
  final Value<int> createdAtMs;
  final Value<int> rowid;
  const CaptureReceiptsCompanion({
    this.captureId = const Value.absent(),
    this.queueId = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CaptureReceiptsCompanion.insert({
    required String captureId,
    required String queueId,
    required int createdAtMs,
    this.rowid = const Value.absent(),
  }) : captureId = Value(captureId),
       queueId = Value(queueId),
       createdAtMs = Value(createdAtMs);
  static Insertable<CaptureReceipt> custom({
    Expression<String>? captureId,
    Expression<String>? queueId,
    Expression<int>? createdAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (captureId != null) 'capture_id': captureId,
      if (queueId != null) 'queue_id': queueId,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CaptureReceiptsCompanion copyWith({
    Value<String>? captureId,
    Value<String>? queueId,
    Value<int>? createdAtMs,
    Value<int>? rowid,
  }) {
    return CaptureReceiptsCompanion(
      captureId: captureId ?? this.captureId,
      queueId: queueId ?? this.queueId,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (captureId.present) {
      map['capture_id'] = Variable<String>(captureId.value);
    }
    if (queueId.present) {
      map['queue_id'] = Variable<String>(queueId.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CaptureReceiptsCompanion(')
          ..write('captureId: $captureId, ')
          ..write('queueId: $queueId, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ScanDatabase extends GeneratedDatabase {
  _$ScanDatabase(QueryExecutor e) : super(e);
  $ScanDatabaseManager get managers => $ScanDatabaseManager(this);
  late final $ScanUploadsTable scanUploads = $ScanUploadsTable(this);
  late final $ShareReceiptsTable shareReceipts = $ShareReceiptsTable(this);
  late final $CaptureReceiptsTable captureReceipts = $CaptureReceiptsTable(
    this,
  );
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    scanUploads,
    shareReceipts,
    captureReceipts,
    appSettings,
  ];
}

typedef $$ScanUploadsTableCreateCompanionBuilder =
    ScanUploadsCompanion Function({
      required String id,
      required String payloadPath,
      Value<String?> ocrContentPath,
      Value<String?> ocrSha256,
      required String sha256,
      required int byteSize,
      required String mimeType,
      required String filename,
      Value<int?> sourceMtime,
      Value<double?> ocrConfidence,
      Value<String?> ocrLanguage,
      required String source,
      Value<String?> shareBatchId,
      Value<int?> shareItemIndex,
      required int pageCount,
      required String state,
      Value<int> bytesSent,
      Value<int> attemptCount,
      Value<int?> nextAttemptAtMs,
      Value<int?> identityUserId,
      Value<String?> identityOrigin,
      Value<int?> identitySystemId,
      Value<int?> serverDocumentId,
      Value<int?> serverTaskId,
      Value<int?> splitOriginId,
      Value<String?> splitDocumentIds,
      Value<bool> deduplicated,
      Value<bool> restored,
      Value<bool> split,
      Value<String?> lastErrorCode,
      Value<String?> lastErrorMessage,
      Value<String?> requestId,
      required int createdAtMs,
      required int updatedAtMs,
      Value<int?> completedAtMs,
      Value<int> rowid,
    });
typedef $$ScanUploadsTableUpdateCompanionBuilder =
    ScanUploadsCompanion Function({
      Value<String> id,
      Value<String> payloadPath,
      Value<String?> ocrContentPath,
      Value<String?> ocrSha256,
      Value<String> sha256,
      Value<int> byteSize,
      Value<String> mimeType,
      Value<String> filename,
      Value<int?> sourceMtime,
      Value<double?> ocrConfidence,
      Value<String?> ocrLanguage,
      Value<String> source,
      Value<String?> shareBatchId,
      Value<int?> shareItemIndex,
      Value<int> pageCount,
      Value<String> state,
      Value<int> bytesSent,
      Value<int> attemptCount,
      Value<int?> nextAttemptAtMs,
      Value<int?> identityUserId,
      Value<String?> identityOrigin,
      Value<int?> identitySystemId,
      Value<int?> serverDocumentId,
      Value<int?> serverTaskId,
      Value<int?> splitOriginId,
      Value<String?> splitDocumentIds,
      Value<bool> deduplicated,
      Value<bool> restored,
      Value<bool> split,
      Value<String?> lastErrorCode,
      Value<String?> lastErrorMessage,
      Value<String?> requestId,
      Value<int> createdAtMs,
      Value<int> updatedAtMs,
      Value<int?> completedAtMs,
      Value<int> rowid,
    });

class $$ScanUploadsTableFilterComposer
    extends Composer<_$ScanDatabase, $ScanUploadsTable> {
  $$ScanUploadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadPath => $composableBuilder(
    column: $table.payloadPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ocrContentPath => $composableBuilder(
    column: $table.ocrContentPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ocrSha256 => $composableBuilder(
    column: $table.ocrSha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceMtime => $composableBuilder(
    column: $table.sourceMtime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ocrConfidence => $composableBuilder(
    column: $table.ocrConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ocrLanguage => $composableBuilder(
    column: $table.ocrLanguage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shareBatchId => $composableBuilder(
    column: $table.shareBatchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get shareItemIndex => $composableBuilder(
    column: $table.shareItemIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bytesSent => $composableBuilder(
    column: $table.bytesSent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextAttemptAtMs => $composableBuilder(
    column: $table.nextAttemptAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get identityUserId => $composableBuilder(
    column: $table.identityUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identityOrigin => $composableBuilder(
    column: $table.identityOrigin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get identitySystemId => $composableBuilder(
    column: $table.identitySystemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverDocumentId => $composableBuilder(
    column: $table.serverDocumentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverTaskId => $composableBuilder(
    column: $table.serverTaskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get splitOriginId => $composableBuilder(
    column: $table.splitOriginId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get splitDocumentIds => $composableBuilder(
    column: $table.splitDocumentIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deduplicated => $composableBuilder(
    column: $table.deduplicated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get restored => $composableBuilder(
    column: $table.restored,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get split => $composableBuilder(
    column: $table.split,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorMessage => $composableBuilder(
    column: $table.lastErrorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedAtMs => $composableBuilder(
    column: $table.completedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ScanUploadsTableOrderingComposer
    extends Composer<_$ScanDatabase, $ScanUploadsTable> {
  $$ScanUploadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadPath => $composableBuilder(
    column: $table.payloadPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ocrContentPath => $composableBuilder(
    column: $table.ocrContentPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ocrSha256 => $composableBuilder(
    column: $table.ocrSha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceMtime => $composableBuilder(
    column: $table.sourceMtime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ocrConfidence => $composableBuilder(
    column: $table.ocrConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ocrLanguage => $composableBuilder(
    column: $table.ocrLanguage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shareBatchId => $composableBuilder(
    column: $table.shareBatchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get shareItemIndex => $composableBuilder(
    column: $table.shareItemIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytesSent => $composableBuilder(
    column: $table.bytesSent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextAttemptAtMs => $composableBuilder(
    column: $table.nextAttemptAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get identityUserId => $composableBuilder(
    column: $table.identityUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identityOrigin => $composableBuilder(
    column: $table.identityOrigin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get identitySystemId => $composableBuilder(
    column: $table.identitySystemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverDocumentId => $composableBuilder(
    column: $table.serverDocumentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverTaskId => $composableBuilder(
    column: $table.serverTaskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get splitOriginId => $composableBuilder(
    column: $table.splitOriginId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get splitDocumentIds => $composableBuilder(
    column: $table.splitDocumentIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deduplicated => $composableBuilder(
    column: $table.deduplicated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get restored => $composableBuilder(
    column: $table.restored,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get split => $composableBuilder(
    column: $table.split,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorMessage => $composableBuilder(
    column: $table.lastErrorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAtMs => $composableBuilder(
    column: $table.completedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ScanUploadsTableAnnotationComposer
    extends Composer<_$ScanDatabase, $ScanUploadsTable> {
  $$ScanUploadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payloadPath => $composableBuilder(
    column: $table.payloadPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ocrContentPath => $composableBuilder(
    column: $table.ocrContentPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ocrSha256 =>
      $composableBuilder(column: $table.ocrSha256, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get filename =>
      $composableBuilder(column: $table.filename, builder: (column) => column);

  GeneratedColumn<int> get sourceMtime => $composableBuilder(
    column: $table.sourceMtime,
    builder: (column) => column,
  );

  GeneratedColumn<double> get ocrConfidence => $composableBuilder(
    column: $table.ocrConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ocrLanguage => $composableBuilder(
    column: $table.ocrLanguage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get shareBatchId => $composableBuilder(
    column: $table.shareBatchId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get shareItemIndex => $composableBuilder(
    column: $table.shareItemIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get bytesSent =>
      $composableBuilder(column: $table.bytesSent, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get nextAttemptAtMs => $composableBuilder(
    column: $table.nextAttemptAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get identityUserId => $composableBuilder(
    column: $table.identityUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get identityOrigin => $composableBuilder(
    column: $table.identityOrigin,
    builder: (column) => column,
  );

  GeneratedColumn<int> get identitySystemId => $composableBuilder(
    column: $table.identitySystemId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverDocumentId => $composableBuilder(
    column: $table.serverDocumentId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverTaskId => $composableBuilder(
    column: $table.serverTaskId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get splitOriginId => $composableBuilder(
    column: $table.splitOriginId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get splitDocumentIds => $composableBuilder(
    column: $table.splitDocumentIds,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deduplicated => $composableBuilder(
    column: $table.deduplicated,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get restored =>
      $composableBuilder(column: $table.restored, builder: (column) => column);

  GeneratedColumn<bool> get split =>
      $composableBuilder(column: $table.split, builder: (column) => column);

  GeneratedColumn<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorMessage => $composableBuilder(
    column: $table.lastErrorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get requestId =>
      $composableBuilder(column: $table.requestId, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedAtMs => $composableBuilder(
    column: $table.completedAtMs,
    builder: (column) => column,
  );
}

class $$ScanUploadsTableTableManager
    extends
        RootTableManager<
          _$ScanDatabase,
          $ScanUploadsTable,
          ScanUpload,
          $$ScanUploadsTableFilterComposer,
          $$ScanUploadsTableOrderingComposer,
          $$ScanUploadsTableAnnotationComposer,
          $$ScanUploadsTableCreateCompanionBuilder,
          $$ScanUploadsTableUpdateCompanionBuilder,
          (
            ScanUpload,
            BaseReferences<_$ScanDatabase, $ScanUploadsTable, ScanUpload>,
          ),
          ScanUpload,
          PrefetchHooks Function()
        > {
  $$ScanUploadsTableTableManager(_$ScanDatabase db, $ScanUploadsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScanUploadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScanUploadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScanUploadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> payloadPath = const Value.absent(),
                Value<String?> ocrContentPath = const Value.absent(),
                Value<String?> ocrSha256 = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<String> filename = const Value.absent(),
                Value<int?> sourceMtime = const Value.absent(),
                Value<double?> ocrConfidence = const Value.absent(),
                Value<String?> ocrLanguage = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> shareBatchId = const Value.absent(),
                Value<int?> shareItemIndex = const Value.absent(),
                Value<int> pageCount = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> bytesSent = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int?> nextAttemptAtMs = const Value.absent(),
                Value<int?> identityUserId = const Value.absent(),
                Value<String?> identityOrigin = const Value.absent(),
                Value<int?> identitySystemId = const Value.absent(),
                Value<int?> serverDocumentId = const Value.absent(),
                Value<int?> serverTaskId = const Value.absent(),
                Value<int?> splitOriginId = const Value.absent(),
                Value<String?> splitDocumentIds = const Value.absent(),
                Value<bool> deduplicated = const Value.absent(),
                Value<bool> restored = const Value.absent(),
                Value<bool> split = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastErrorMessage = const Value.absent(),
                Value<String?> requestId = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int?> completedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScanUploadsCompanion(
                id: id,
                payloadPath: payloadPath,
                ocrContentPath: ocrContentPath,
                ocrSha256: ocrSha256,
                sha256: sha256,
                byteSize: byteSize,
                mimeType: mimeType,
                filename: filename,
                sourceMtime: sourceMtime,
                ocrConfidence: ocrConfidence,
                ocrLanguage: ocrLanguage,
                source: source,
                shareBatchId: shareBatchId,
                shareItemIndex: shareItemIndex,
                pageCount: pageCount,
                state: state,
                bytesSent: bytesSent,
                attemptCount: attemptCount,
                nextAttemptAtMs: nextAttemptAtMs,
                identityUserId: identityUserId,
                identityOrigin: identityOrigin,
                identitySystemId: identitySystemId,
                serverDocumentId: serverDocumentId,
                serverTaskId: serverTaskId,
                splitOriginId: splitOriginId,
                splitDocumentIds: splitDocumentIds,
                deduplicated: deduplicated,
                restored: restored,
                split: split,
                lastErrorCode: lastErrorCode,
                lastErrorMessage: lastErrorMessage,
                requestId: requestId,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                completedAtMs: completedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String payloadPath,
                Value<String?> ocrContentPath = const Value.absent(),
                Value<String?> ocrSha256 = const Value.absent(),
                required String sha256,
                required int byteSize,
                required String mimeType,
                required String filename,
                Value<int?> sourceMtime = const Value.absent(),
                Value<double?> ocrConfidence = const Value.absent(),
                Value<String?> ocrLanguage = const Value.absent(),
                required String source,
                Value<String?> shareBatchId = const Value.absent(),
                Value<int?> shareItemIndex = const Value.absent(),
                required int pageCount,
                required String state,
                Value<int> bytesSent = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int?> nextAttemptAtMs = const Value.absent(),
                Value<int?> identityUserId = const Value.absent(),
                Value<String?> identityOrigin = const Value.absent(),
                Value<int?> identitySystemId = const Value.absent(),
                Value<int?> serverDocumentId = const Value.absent(),
                Value<int?> serverTaskId = const Value.absent(),
                Value<int?> splitOriginId = const Value.absent(),
                Value<String?> splitDocumentIds = const Value.absent(),
                Value<bool> deduplicated = const Value.absent(),
                Value<bool> restored = const Value.absent(),
                Value<bool> split = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastErrorMessage = const Value.absent(),
                Value<String?> requestId = const Value.absent(),
                required int createdAtMs,
                required int updatedAtMs,
                Value<int?> completedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScanUploadsCompanion.insert(
                id: id,
                payloadPath: payloadPath,
                ocrContentPath: ocrContentPath,
                ocrSha256: ocrSha256,
                sha256: sha256,
                byteSize: byteSize,
                mimeType: mimeType,
                filename: filename,
                sourceMtime: sourceMtime,
                ocrConfidence: ocrConfidence,
                ocrLanguage: ocrLanguage,
                source: source,
                shareBatchId: shareBatchId,
                shareItemIndex: shareItemIndex,
                pageCount: pageCount,
                state: state,
                bytesSent: bytesSent,
                attemptCount: attemptCount,
                nextAttemptAtMs: nextAttemptAtMs,
                identityUserId: identityUserId,
                identityOrigin: identityOrigin,
                identitySystemId: identitySystemId,
                serverDocumentId: serverDocumentId,
                serverTaskId: serverTaskId,
                splitOriginId: splitOriginId,
                splitDocumentIds: splitDocumentIds,
                deduplicated: deduplicated,
                restored: restored,
                split: split,
                lastErrorCode: lastErrorCode,
                lastErrorMessage: lastErrorMessage,
                requestId: requestId,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                completedAtMs: completedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ScanUploadsTableProcessedTableManager =
    ProcessedTableManager<
      _$ScanDatabase,
      $ScanUploadsTable,
      ScanUpload,
      $$ScanUploadsTableFilterComposer,
      $$ScanUploadsTableOrderingComposer,
      $$ScanUploadsTableAnnotationComposer,
      $$ScanUploadsTableCreateCompanionBuilder,
      $$ScanUploadsTableUpdateCompanionBuilder,
      (
        ScanUpload,
        BaseReferences<_$ScanDatabase, $ScanUploadsTable, ScanUpload>,
      ),
      ScanUpload,
      PrefetchHooks Function()
    >;
typedef $$ShareReceiptsTableCreateCompanionBuilder =
    ShareReceiptsCompanion Function({
      required String batchId,
      required int itemIndex,
      required String sha256,
      required int byteSize,
      required String mimeType,
      Value<String?> queueId,
      required String status,
      Value<String?> errorCode,
      required int createdAtMs,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$ShareReceiptsTableUpdateCompanionBuilder =
    ShareReceiptsCompanion Function({
      Value<String> batchId,
      Value<int> itemIndex,
      Value<String> sha256,
      Value<int> byteSize,
      Value<String> mimeType,
      Value<String?> queueId,
      Value<String> status,
      Value<String?> errorCode,
      Value<int> createdAtMs,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$ShareReceiptsTableFilterComposer
    extends Composer<_$ScanDatabase, $ShareReceiptsTable> {
  $$ShareReceiptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get itemIndex => $composableBuilder(
    column: $table.itemIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get queueId => $composableBuilder(
    column: $table.queueId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ShareReceiptsTableOrderingComposer
    extends Composer<_$ScanDatabase, $ShareReceiptsTable> {
  $$ShareReceiptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get itemIndex => $composableBuilder(
    column: $table.itemIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get queueId => $composableBuilder(
    column: $table.queueId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ShareReceiptsTableAnnotationComposer
    extends Composer<_$ScanDatabase, $ShareReceiptsTable> {
  $$ShareReceiptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get batchId =>
      $composableBuilder(column: $table.batchId, builder: (column) => column);

  GeneratedColumn<int> get itemIndex =>
      $composableBuilder(column: $table.itemIndex, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get queueId =>
      $composableBuilder(column: $table.queueId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$ShareReceiptsTableTableManager
    extends
        RootTableManager<
          _$ScanDatabase,
          $ShareReceiptsTable,
          ShareReceipt,
          $$ShareReceiptsTableFilterComposer,
          $$ShareReceiptsTableOrderingComposer,
          $$ShareReceiptsTableAnnotationComposer,
          $$ShareReceiptsTableCreateCompanionBuilder,
          $$ShareReceiptsTableUpdateCompanionBuilder,
          (
            ShareReceipt,
            BaseReferences<_$ScanDatabase, $ShareReceiptsTable, ShareReceipt>,
          ),
          ShareReceipt,
          PrefetchHooks Function()
        > {
  $$ShareReceiptsTableTableManager(_$ScanDatabase db, $ShareReceiptsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShareReceiptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShareReceiptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShareReceiptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> batchId = const Value.absent(),
                Value<int> itemIndex = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<String?> queueId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShareReceiptsCompanion(
                batchId: batchId,
                itemIndex: itemIndex,
                sha256: sha256,
                byteSize: byteSize,
                mimeType: mimeType,
                queueId: queueId,
                status: status,
                errorCode: errorCode,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String batchId,
                required int itemIndex,
                required String sha256,
                required int byteSize,
                required String mimeType,
                Value<String?> queueId = const Value.absent(),
                required String status,
                Value<String?> errorCode = const Value.absent(),
                required int createdAtMs,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => ShareReceiptsCompanion.insert(
                batchId: batchId,
                itemIndex: itemIndex,
                sha256: sha256,
                byteSize: byteSize,
                mimeType: mimeType,
                queueId: queueId,
                status: status,
                errorCode: errorCode,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ShareReceiptsTableProcessedTableManager =
    ProcessedTableManager<
      _$ScanDatabase,
      $ShareReceiptsTable,
      ShareReceipt,
      $$ShareReceiptsTableFilterComposer,
      $$ShareReceiptsTableOrderingComposer,
      $$ShareReceiptsTableAnnotationComposer,
      $$ShareReceiptsTableCreateCompanionBuilder,
      $$ShareReceiptsTableUpdateCompanionBuilder,
      (
        ShareReceipt,
        BaseReferences<_$ScanDatabase, $ShareReceiptsTable, ShareReceipt>,
      ),
      ShareReceipt,
      PrefetchHooks Function()
    >;
typedef $$CaptureReceiptsTableCreateCompanionBuilder =
    CaptureReceiptsCompanion Function({
      required String captureId,
      required String queueId,
      required int createdAtMs,
      Value<int> rowid,
    });
typedef $$CaptureReceiptsTableUpdateCompanionBuilder =
    CaptureReceiptsCompanion Function({
      Value<String> captureId,
      Value<String> queueId,
      Value<int> createdAtMs,
      Value<int> rowid,
    });

class $$CaptureReceiptsTableFilterComposer
    extends Composer<_$ScanDatabase, $CaptureReceiptsTable> {
  $$CaptureReceiptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get captureId => $composableBuilder(
    column: $table.captureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get queueId => $composableBuilder(
    column: $table.queueId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CaptureReceiptsTableOrderingComposer
    extends Composer<_$ScanDatabase, $CaptureReceiptsTable> {
  $$CaptureReceiptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get captureId => $composableBuilder(
    column: $table.captureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get queueId => $composableBuilder(
    column: $table.queueId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CaptureReceiptsTableAnnotationComposer
    extends Composer<_$ScanDatabase, $CaptureReceiptsTable> {
  $$CaptureReceiptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get captureId =>
      $composableBuilder(column: $table.captureId, builder: (column) => column);

  GeneratedColumn<String> get queueId =>
      $composableBuilder(column: $table.queueId, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );
}

class $$CaptureReceiptsTableTableManager
    extends
        RootTableManager<
          _$ScanDatabase,
          $CaptureReceiptsTable,
          CaptureReceipt,
          $$CaptureReceiptsTableFilterComposer,
          $$CaptureReceiptsTableOrderingComposer,
          $$CaptureReceiptsTableAnnotationComposer,
          $$CaptureReceiptsTableCreateCompanionBuilder,
          $$CaptureReceiptsTableUpdateCompanionBuilder,
          (
            CaptureReceipt,
            BaseReferences<
              _$ScanDatabase,
              $CaptureReceiptsTable,
              CaptureReceipt
            >,
          ),
          CaptureReceipt,
          PrefetchHooks Function()
        > {
  $$CaptureReceiptsTableTableManager(
    _$ScanDatabase db,
    $CaptureReceiptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CaptureReceiptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CaptureReceiptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CaptureReceiptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> captureId = const Value.absent(),
                Value<String> queueId = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CaptureReceiptsCompanion(
                captureId: captureId,
                queueId: queueId,
                createdAtMs: createdAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String captureId,
                required String queueId,
                required int createdAtMs,
                Value<int> rowid = const Value.absent(),
              }) => CaptureReceiptsCompanion.insert(
                captureId: captureId,
                queueId: queueId,
                createdAtMs: createdAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CaptureReceiptsTableProcessedTableManager =
    ProcessedTableManager<
      _$ScanDatabase,
      $CaptureReceiptsTable,
      CaptureReceipt,
      $$CaptureReceiptsTableFilterComposer,
      $$CaptureReceiptsTableOrderingComposer,
      $$CaptureReceiptsTableAnnotationComposer,
      $$CaptureReceiptsTableCreateCompanionBuilder,
      $$CaptureReceiptsTableUpdateCompanionBuilder,
      (
        CaptureReceipt,
        BaseReferences<_$ScanDatabase, $CaptureReceiptsTable, CaptureReceipt>,
      ),
      CaptureReceipt,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$ScanDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$ScanDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$ScanDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$ScanDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$ScanDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$ScanDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$ScanDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$ScanDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;

class $ScanDatabaseManager {
  final _$ScanDatabase _db;
  $ScanDatabaseManager(this._db);
  $$ScanUploadsTableTableManager get scanUploads =>
      $$ScanUploadsTableTableManager(_db, _db.scanUploads);
  $$ShareReceiptsTableTableManager get shareReceipts =>
      $$ShareReceiptsTableTableManager(_db, _db.shareReceipts);
  $$CaptureReceiptsTableTableManager get captureReceipts =>
      $$CaptureReceiptsTableTableManager(_db, _db.captureReceipts);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
}
