import 'dart:convert';

final class ApiFormatException implements Exception {
  const ApiFormatException(this.message);

  final String message;

  @override
  String toString() => 'ApiFormatException: $message';
}

final class Handshake {
  const Handshake({required this.product, required this.mobileContracts});

  factory Handshake.fromJson(Object? value) {
    final json = _object(value, 'handshake');
    return Handshake(
      product: _string(json, 'product'),
      mobileContracts: json.containsKey('mobile_contracts')
          ? _stringList(json, 'mobile_contracts')
          : null,
    );
  }

  final String product;
  final List<String>? mobileContracts;
}

final class UserSelf {
  const UserSelf({
    required this.kind,
    required this.userId,
    required this.email,
    required this.displayName,
    required this.instanceHost,
    required this.role,
    required this.authenticatedBy,
    required this.avatarUrl,
    required this.systemId,
    required this.systemName,
    required this.systemCode,
    required this.capabilities,
    required this.scopes,
  });

  factory UserSelf.fromJson(Object? value) {
    final json = _object(value, 'user');
    final kind = _string(json, 'kind');
    if (kind != 'token') {
      throw ApiFormatException('user.kind must identify an API token');
    }
    final systemCode = _string(json, 'system_code');
    if (systemCode.isNotEmpty &&
        !RegExp(r'^[A-Z][0-9]{2}$').hasMatch(systemCode)) {
      throw ApiFormatException('user.system_code has an unsupported value');
    }
    return UserSelf(
      kind: kind,
      userId: _positiveInteger(json, 'user_id'),
      email: _string(json, 'email'),
      displayName: _optionalString(json, 'display_name'),
      instanceHost: _string(json, 'instance_host'),
      role: _string(json, 'role'),
      authenticatedBy: _string(json, 'authn_by'),
      avatarUrl: _optionalString(json, 'avatar_url'),
      systemId: _positiveInteger(json, 'system_id'),
      systemName: _nonEmptyString(json, 'system_name'),
      systemCode: systemCode,
      capabilities: _stringList(json, 'capabilities'),
      scopes: _stringList(json, 'scopes'),
    );
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'user_id': userId,
    'email': email,
    'display_name': displayName,
    'instance_host': instanceHost,
    'role': role,
    'authn_by': authenticatedBy,
    'avatar_url': avatarUrl,
    'system_id': systemId,
    'system_name': systemName,
    'system_code': systemCode,
    'capabilities': capabilities,
    'scopes': scopes,
  };

  final String kind;
  final int userId;
  final String email;
  final String? displayName;
  final String instanceHost;
  final String role;
  final String authenticatedBy;
  final String? avatarUrl;
  final int systemId;
  final String systemName;
  final String systemCode;
  final List<String> capabilities;
  final List<String> scopes;

  String get label =>
      displayName?.trim().isNotEmpty == true ? displayName! : email;

  bool get hasMobileScopes =>
      scopes.contains('documents:read') && scopes.contains('documents:write');
}

final class PageEnvelope<T> {
  const PageEnvelope({
    required this.count,
    required this.next,
    required this.previous,
    required this.results,
  });

  factory PageEnvelope.fromJson(
    Object? value,
    T Function(Object? value) parseItem,
  ) {
    final json = _object(value, 'page');
    return PageEnvelope<T>(
      count: _nonNegativeInteger(json, 'count'),
      next: _optionalString(json, 'next'),
      previous: _optionalString(json, 'previous'),
      results: _list(json, 'results').map(parseItem).toList(growable: false),
    );
  }

  final int count;
  final String? next;
  final String? previous;
  final List<T> results;
}

final class SavedView {
  const SavedView({
    required this.id,
    required this.name,
    required this.filterJson,
    required this.filter,
    required this.filterError,
    required this.display,
    required this.position,
    required this.shared,
    required this.ownerId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SavedView.fromJson(Object? value) {
    final json = _object(value, 'saved view');
    final filterJson = _string(json, 'filter_json');
    SavedViewFilter? filter;
    String? filterError;
    try {
      filter = SavedViewFilter.fromJsonString(filterJson);
    } on ApiFormatException catch (error) {
      filterError = error.message;
    }
    return SavedView(
      id: _positiveInteger(json, 'id'),
      name: _nonEmptyString(json, 'name'),
      filterJson: filterJson,
      filter: filter,
      filterError: filterError,
      display: _nonEmptyString(json, 'display'),
      position: _integer(json, 'position'),
      shared: _optionalBoolean(json, 'shared') ?? false,
      ownerId: _optionalPositiveInteger(json, 'owner_id'),
      createdAt: _nonNegativeInteger(json, 'created_at'),
      updatedAt: _nonNegativeInteger(json, 'updated_at'),
    );
  }

  final int id;
  final String name;
  final String filterJson;
  final SavedViewFilter? filter;
  final String? filterError;
  final String display;
  final int position;
  final bool shared;
  final int? ownerId;
  final int createdAt;
  final int updatedAt;

  bool get available => filter != null;
}

final class SavedViewFilter {
  const SavedViewFilter({
    required this.query,
    required this.tagIds,
    required this.correspondentIds,
    required this.documentTypeId,
    required this.jdCategoryId,
    required this.sensitivity,
    required this.ordering,
    required this.documentIds,
  });

  factory SavedViewFilter.fromJsonString(String encoded) {
    if (utf8.encode(encoded).length > 2048) {
      throw const ApiFormatException('Saved View filters exceed 2 KiB.');
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      throw const ApiFormatException('Saved View filters are not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ApiFormatException('Saved View filters must be an object.');
    }
    const allowedKeys = {
      'q',
      'tags__id__in',
      'correspondents__id__in',
      'document_type__id',
      'jd_category_id',
      'sensitivity',
      'ordering',
      'document_ids',
    };
    final unknown = decoded.keys.where((key) => !allowedKeys.contains(key));
    if (unknown.isNotEmpty) {
      throw ApiFormatException(
        'Saved View uses an unsupported filter: ${unknown.first}.',
      );
    }
    final query = _filterString(decoded, 'q');
    final tagIds = _filterIds(decoded, 'tags__id__in', allowCsv: true);
    final correspondentIds = _filterIds(
      decoded,
      'correspondents__id__in',
      allowCsv: true,
    );
    final documentTypeId = _filterId(decoded, 'document_type__id');
    final jdCategoryId = _filterId(decoded, 'jd_category_id');
    final sensitivity = _filterString(decoded, 'sensitivity');
    if (sensitivity != null &&
        !const {
          '',
          'public',
          'internal',
          'confidential',
          'restricted',
        }.contains(sensitivity)) {
      throw const ApiFormatException('Saved View sensitivity is unsupported.');
    }
    final ordering = _filterString(decoded, 'ordering');
    if (ordering != null &&
        !const {
          'created_at',
          '-created_at',
          'updated_at',
          '-updated_at',
          'title',
          '-title',
        }.contains(ordering)) {
      throw const ApiFormatException('Saved View ordering is unsupported.');
    }
    final documentIds = _filterIds(
      decoded,
      'document_ids',
      requireNonEmpty: decoded.containsKey('document_ids'),
    );
    return SavedViewFilter(
      query: query,
      tagIds: tagIds,
      correspondentIds: correspondentIds,
      documentTypeId: documentTypeId,
      jdCategoryId: jdCategoryId,
      sensitivity: sensitivity,
      ordering: ordering,
      documentIds: documentIds,
    );
  }

  final String? query;
  final List<int> tagIds;
  final List<int> correspondentIds;
  final int? documentTypeId;
  final int? jdCategoryId;
  final String? sensitivity;
  final String? ordering;
  final List<int> documentIds;

  Map<String, String> get queryParameters => {
    if (query != null && query!.isNotEmpty) 'q': query!,
    if (tagIds.isNotEmpty) 'tags__id__in': tagIds.join(','),
    if (correspondentIds.isNotEmpty)
      'correspondents__id__in': correspondentIds.join(','),
    if (documentTypeId != null) 'document_type__id': '$documentTypeId',
    if (jdCategoryId != null) 'jd_category_id': '$jdCategoryId',
    if (sensitivity != null && sensitivity!.isNotEmpty)
      'sensitivity': sensitivity!,
    'ordering': ?ordering,
    if (documentIds.isNotEmpty) 'document_ids': documentIds.join(','),
  };

  String get summary {
    final parts = <String>[
      if (query?.trim().isNotEmpty == true) query!.trim(),
      if (documentIds.isNotEmpty)
        '${documentIds.length} selected ${documentIds.length == 1 ? 'document' : 'documents'}',
      if (jdCategoryId != null) 'JD category $jdCategoryId',
      if (documentTypeId != null) 'Document type $documentTypeId',
      if (tagIds.isNotEmpty)
        '${tagIds.length} ${tagIds.length == 1 ? 'tag' : 'tags'}',
      if (correspondentIds.isNotEmpty)
        '${correspondentIds.length} ${correspondentIds.length == 1 ? 'correspondent' : 'correspondents'}',
      if (sensitivity?.isNotEmpty == true) sensitivity!,
    ];
    return parts.isEmpty ? 'All documents' : parts.join(' · ');
  }

  static String? _filterString(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key)) return null;
    final value = json[key];
    if (value is! String) {
      throw ApiFormatException('Saved View filter $key must be a string.');
    }
    return value;
  }

  static int? _filterId(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key)) return null;
    return _positiveFilterId(json[key], key);
  }

  static List<int> _filterIds(
    Map<String, dynamic> json,
    String key, {
    bool allowCsv = false,
    bool requireNonEmpty = false,
  }) {
    if (!json.containsKey(key)) return const [];
    final value = json[key];
    final values = switch (value) {
      List<Object?> items => items,
      String text when allowCsv => text.split(',').cast<Object?>(),
      int number when allowCsv => <Object?>[number],
      _ => throw ApiFormatException(
        'Saved View filter $key must be an array of IDs.',
      ),
    };
    if (values.length > 100 || requireNonEmpty && values.isEmpty) {
      throw ApiFormatException(
        'Saved View filter $key has an unsupported number of IDs.',
      );
    }
    return List<int>.unmodifiable(
      values.map((value) => _positiveFilterId(value, key)),
    );
  }

  static int _positiveFilterId(Object? value, String key) {
    final id = switch (value) {
      int number => number,
      String text when RegExp(r'^[1-9][0-9]*$').hasMatch(text.trim()) =>
        int.tryParse(text.trim()),
      _ => null,
    };
    if (id == null || id <= 0) {
      throw ApiFormatException(
        'Saved View filter $key must contain positive integer IDs.',
      );
    }
    return id;
  }
}

final class DocumentSummary {
  const DocumentSummary({
    required this.id,
    required this.title,
    required this.mimeType,
    required this.originalSize,
    required this.jdCategoryId,
    required this.jdCategoryCode,
    required this.jdCategoryName,
    required this.jdAreaName,
    required this.sensitivity,
    required this.thumbnailSha,
    required this.splitOriginId,
    required this.splitIndex,
    required this.createdAt,
    required this.updatedAt,
    required this.trashedAt,
    required this.tags,
    required this.correspondents,
  });

  factory DocumentSummary.fromJson(Object? value) {
    final json = _object(value, 'document summary');
    return DocumentSummary(
      id: _positiveInteger(json, 'id'),
      title: _string(json, 'title'),
      mimeType: _optionalString(json, 'mime_type') ?? '',
      originalSize: _optionalNonNegativeInteger(json, 'original_size') ?? 0,
      jdCategoryId: _optionalPositiveInteger(json, 'jd_category_id'),
      jdCategoryCode: _optionalNonNegativeInteger(json, 'jd_category_code'),
      jdCategoryName: _optionalString(json, 'jd_category_name'),
      jdAreaName: _optionalString(json, 'jd_area_name'),
      sensitivity: _optionalString(json, 'sensitivity') ?? '',
      thumbnailSha: _optionalString(json, 'thumb_sha'),
      splitOriginId: _optionalPositiveInteger(json, 'split_origin_id'),
      splitIndex: _optionalNonNegativeInteger(json, 'split_index'),
      createdAt: _nonNegativeInteger(json, 'created_at'),
      updatedAt: _nonNegativeInteger(json, 'updated_at'),
      trashedAt: _optionalNonNegativeInteger(json, 'trashed_at'),
      tags: _stringList(json, 'tags'),
      correspondents: _optionalStringList(json, 'correspondents'),
    );
  }

  final int id;
  final String title;
  final String mimeType;
  final int originalSize;
  final int? jdCategoryId;
  final int? jdCategoryCode;
  final String? jdCategoryName;
  final String? jdAreaName;
  final String sensitivity;
  final String? thumbnailSha;
  final int? splitOriginId;
  final int? splitIndex;
  final int createdAt;
  final int updatedAt;
  final int? trashedAt;
  final List<String> tags;
  final List<String> correspondents;

  bool get isSensitive =>
      sensitivity == 'confidential' || sensitivity == 'restricted';
}

final class DocumentSource {
  const DocumentSource({
    required this.kind,
    required this.label,
    required this.detail,
    required this.observedAt,
  });

  factory DocumentSource.fromJson(Object? value) {
    final json = _object(value, 'document source');
    return DocumentSource(
      kind: _string(json, 'kind'),
      label: _string(json, 'label'),
      detail: _optionalString(json, 'detail'),
      observedAt: _nonNegativeInteger(json, 'observed_at'),
    );
  }

  final String kind;
  final String label;
  final String? detail;
  final int observedAt;
}

final class DocumentCorrespondent {
  const DocumentCorrespondent({
    required this.id,
    required this.name,
    required this.role,
  });

  factory DocumentCorrespondent.fromJson(Object? value) {
    final json = _object(value, 'document correspondent');
    return DocumentCorrespondent(
      id: _positiveInteger(json, 'id'),
      name: _string(json, 'name'),
      role: _string(json, 'role'),
    );
  }

  final int id;
  final String name;
  final String role;
}

final class TagView {
  const TagView({
    required this.id,
    required this.name,
    required this.slug,
    required this.color,
    required this.parentId,
    required this.childCount,
  });

  factory TagView.fromJson(Object? value) {
    final json = _object(value, 'tag');
    return TagView(
      id: _positiveInteger(json, 'id'),
      name: _nonEmptyString(json, 'name'),
      slug: _nonEmptyString(json, 'slug'),
      color: _string(json, 'color'),
      parentId: _optionalPositiveInteger(json, 'parent_id'),
      childCount: _nonNegativeInteger(json, 'child_count'),
    );
  }

  final int id;
  final String name;
  final String slug;
  final String color;
  final int? parentId;
  final int childCount;
}

final class DocumentDetail {
  const DocumentDetail({
    required this.id,
    required this.title,
    required this.mimeType,
    required this.originalSize,
    required this.originalBlob,
    required this.jdCategoryId,
    required this.jdCategoryCode,
    required this.jdCategoryName,
    required this.jdAreaName,
    required this.sensitivity,
    required this.createdAt,
    required this.addedAt,
    required this.updatedAt,
    required this.sourceMtime,
    required this.trashedAt,
    required this.sources,
    required this.tags,
    required this.correspondents,
    required this.languages,
    required this.languagesLocked,
  });

  factory DocumentDetail.fromJson(Object? value) {
    final json = _object(value, 'document detail');
    final content = _string(json, 'content');
    if (content.isNotEmpty) {
      throw const ApiFormatException(
        'metadata-only document response unexpectedly included content',
      );
    }
    final originalBlob = _string(json, 'original_blob');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(originalBlob)) {
      throw const ApiFormatException(
        'document original_blob must be a SHA-256 digest',
      );
    }
    return DocumentDetail(
      id: _positiveInteger(json, 'id'),
      title: _string(json, 'title'),
      mimeType: _string(json, 'mime_type'),
      originalSize: _nonNegativeInteger(json, 'original_size'),
      originalBlob: originalBlob,
      jdCategoryId: _optionalPositiveInteger(json, 'jd_category_id'),
      jdCategoryCode: _optionalNonNegativeInteger(json, 'jd_category_code'),
      jdCategoryName: _optionalString(json, 'jd_category_name'),
      jdAreaName: _optionalString(json, 'jd_area_name'),
      sensitivity: _optionalString(json, 'sensitivity') ?? '',
      createdAt: _nonNegativeInteger(json, 'created_at'),
      addedAt: _nonNegativeInteger(json, 'added_at'),
      updatedAt: _nonNegativeInteger(json, 'updated_at'),
      sourceMtime: _optionalNonNegativeInteger(json, 'source_mtime'),
      trashedAt: _optionalNonNegativeInteger(json, 'trashed_at'),
      sources: _list(
        json,
        'sources',
      ).map(DocumentSource.fromJson).toList(growable: false),
      tags: _stringList(json, 'tags'),
      correspondents: _list(
        json,
        'correspondents',
      ).map(DocumentCorrespondent.fromJson).toList(growable: false),
      languages: _optionalString(json, 'languages') ?? '',
      languagesLocked: _optionalBoolean(json, 'languages_locked') ?? false,
    );
  }

  final int id;
  final String title;
  final String mimeType;
  final int originalSize;
  final String originalBlob;
  final int? jdCategoryId;
  final int? jdCategoryCode;
  final String? jdCategoryName;
  final String? jdAreaName;
  final String sensitivity;
  final int createdAt;
  final int addedAt;
  final int updatedAt;
  final int? sourceMtime;
  final int? trashedAt;
  final List<DocumentSource> sources;
  final List<String> tags;
  final List<DocumentCorrespondent> correspondents;
  final String languages;
  final bool languagesLocked;

  bool get isSensitive =>
      sensitivity == 'confidential' || sensitivity == 'restricted';
}

final class SearchHit {
  const SearchHit({
    required this.id,
    required this.title,
    required this.snippet,
    required this.rank,
    required this.createdAt,
    required this.mimeType,
    required this.sensitivity,
  });

  factory SearchHit.fromJson(Object? value) {
    final json = _object(value, 'search hit');
    final sensitivity = _optionalString(json, 'sensitivity') ?? '';
    final snippet = _string(json, 'snippet');
    if ((sensitivity == 'confidential' || sensitivity == 'restricted') &&
        snippet.isNotEmpty) {
      throw const ApiFormatException('sensitive search hit exposed a snippet');
    }
    return SearchHit(
      id: _positiveInteger(json, 'id'),
      title: _string(json, 'title'),
      snippet: snippet,
      rank: _number(json, 'rank'),
      createdAt: _nonNegativeInteger(json, 'created_at'),
      mimeType: _optionalString(json, 'mime_type') ?? '',
      sensitivity: sensitivity,
    );
  }

  final int id;
  final String title;
  final String snippet;
  final double rank;
  final int createdAt;
  final String mimeType;
  final String sensitivity;

  bool get isSensitive =>
      sensitivity == 'confidential' || sensitivity == 'restricted';
}

final class JDCategory {
  const JDCategory({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.areaCode,
    required this.areaName,
    required this.system,
  });

  factory JDCategory.fromJson(Object? value) {
    final json = _object(value, 'JD category');
    return JDCategory(
      id: _positiveInteger(json, 'id'),
      code: _nonNegativeInteger(json, 'code'),
      name: _string(json, 'name'),
      description: _optionalString(json, 'description') ?? '',
      areaCode: _nonNegativeInteger(json, 'area_code'),
      areaName: _string(json, 'area_name'),
      system: _optionalBoolean(json, 'system') ?? false,
    );
  }

  final int id;
  final int code;
  final String name;
  final String description;
  final int areaCode;
  final String areaName;
  final bool system;

  String get label => '$code $name';
}

final class UploadResult {
  const UploadResult({
    required this.id,
    required this.sha256,
    required this.size,
    required this.mimeType,
    required this.title,
    required this.deduplicated,
    required this.restored,
    required this.idempotentReplay,
    required this.created,
  });

  factory UploadResult.fromJson(Object? value, {required int statusCode}) {
    final json = _object(value, 'upload result');
    final sha = _string(json, 'sha256');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      throw const ApiFormatException('upload result has an invalid SHA-256');
    }
    return UploadResult(
      id: _positiveInteger(json, 'id'),
      sha256: sha,
      size: _nonNegativeInteger(json, 'size'),
      mimeType: _string(json, 'mime_type'),
      title: _string(json, 'title'),
      deduplicated: _optionalBoolean(json, 'deduplicated') ?? false,
      restored: _optionalBoolean(json, 'restored') ?? false,
      idempotentReplay: _optionalBoolean(json, 'idempotent_replay') ?? false,
      created: statusCode == 201,
    );
  }

  final int id;
  final String sha256;
  final int size;
  final String mimeType;
  final String title;
  final bool deduplicated;
  final bool restored;
  final bool idempotentReplay;
  final bool created;
}

final class PostIngestTask {
  const PostIngestTask({
    required this.id,
    required this.kind,
    required this.state,
    required this.attempts,
    required this.documentId,
    required this.lastError,
    required this.createdAt,
    required this.updatedAt,
    required this.nextRunAt,
  });

  factory PostIngestTask.fromJson(Object? value) {
    final json = _object(value, 'post-ingest task');
    return PostIngestTask(
      id: _positiveInteger(json, 'id'),
      kind: _string(json, 'kind'),
      state: _string(json, 'state'),
      attempts: _nonNegativeInteger(json, 'attempts'),
      documentId: _optionalPositiveInteger(json, 'doc_id'),
      lastError: _optionalString(json, 'last_error'),
      createdAt: _nonNegativeInteger(json, 'created_at'),
      updatedAt: _nonNegativeInteger(json, 'updated_at'),
      nextRunAt: _optionalNonNegativeInteger(json, 'next_run_at'),
    );
  }

  final int id;
  final String kind;
  final String state;
  final int attempts;
  final int? documentId;
  final String? lastError;
  final int createdAt;
  final int updatedAt;
  final int? nextRunAt;
}

enum DocumentChangeField { title, category, tag }

final class DocumentChangeApprovalTask {
  const DocumentChangeApprovalTask({
    required this.id,
    required this.runId,
    required this.approvalId,
    required this.documentId,
    required this.documentTitle,
    required this.field,
    required this.status,
    required this.currentValue,
    required this.proposedValue,
    required this.score,
    required this.reason,
    required this.source,
    required this.threshold,
    required this.deadlineAt,
    required this.sourceCurrent,
    required this.reviewConflict,
    required this.evidenceSources,
  });

  static DocumentChangeApprovalTask? maybeFromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['approval_name'] != 'document-change') {
      return null;
    }
    final rawVars = value['vars'];
    if (rawVars is! Map<String, dynamic>) return null;
    final field = switch (rawVars['field']) {
      'title' => DocumentChangeField.title,
      'jd_category' => DocumentChangeField.category,
      'tag' => DocumentChangeField.tag,
      _ => null,
    };
    if (field == null) return null;

    final choices = _stringList(value, 'choices');
    if (choices.length != 2 ||
        !choices.contains('apply') ||
        !choices.contains('reject')) {
      throw const ApiFormatException(
        'document change approval choices must be apply and reject',
      );
    }
    final status = _string(value, 'status');
    if (status != 'open' && status != 'claimed') {
      throw const ApiFormatException(
        'document change approval status must be open or claimed',
      );
    }
    if (_string(value, 'state_key') != 'review') {
      throw const ApiFormatException(
        'document change approval state must be review',
      );
    }
    final reason = _string(rawVars, 'reason');
    if (reason != 'review_first' && reason != 'low_confidence') {
      throw const ApiFormatException(
        'document change approval reason is unsupported',
      );
    }
    if (_string(rawVars, 'policy_version') != 'review-first-v1') {
      throw const ApiFormatException(
        'document change approval policy is unsupported',
      );
    }
    final score = _number(rawVars, 'confidence');
    if (score < 0 || score > 1) {
      throw const ApiFormatException(
        'document change approval confidence must be between 0 and 1',
      );
    }
    final source = _optionalString(rawVars, 'source');
    if (source != null &&
        source != 'archive' &&
        source != 'llm' &&
        source != 'language-detector') {
      throw const ApiFormatException(
        'document change approval source is unsupported',
      );
    }
    final threshold = _optionalNumber(rawVars, 'threshold');
    if (threshold != null && (threshold < 0 || threshold > 1)) {
      throw const ApiFormatException(
        'document change approval threshold must be between 0 and 1',
      );
    }
    final rawSources = _list(rawVars, 'sources');
    if (rawSources.length > 16) {
      throw const ApiFormatException(
        'document change approval has too many evidence sources',
      );
    }
    final evidenceSources = rawSources
        .map((value) {
          final sourceJson = _object(
            value,
            'document change approval evidence source',
          );
          _positiveInteger(sourceJson, 'document_id');
          return _nonEmptyString(sourceJson, 'title');
        })
        .toList(growable: false);
    _nonEmptyString(value, 'assignee');
    _nonEmptyString(value, 'prompt');
    _nonNegativeInteger(value, 'created_at');

    return DocumentChangeApprovalTask(
      id: _positiveInteger(value, 'id'),
      runId: _positiveInteger(value, 'run_id'),
      approvalId: _positiveInteger(value, 'approval_id'),
      documentId: _positiveInteger(value, 'doc_id'),
      documentTitle: _nonEmptyString(value, 'doc_title'),
      field: field,
      status: status,
      currentValue: _string(rawVars, 'current_value'),
      proposedValue: _nonEmptyString(rawVars, 'proposed_value'),
      score: score,
      reason: reason,
      source: source,
      threshold: threshold,
      deadlineAt: _optionalNonNegativeInteger(value, 'deadline_at'),
      sourceCurrent: _boolean(rawVars, 'source_current'),
      reviewConflict: _boolean(rawVars, 'review_conflict'),
      evidenceSources: List.unmodifiable(evidenceSources),
    );
  }

  final int id;
  final int runId;
  final int approvalId;
  final int documentId;
  final String documentTitle;
  final DocumentChangeField field;
  final String status;
  final String currentValue;
  final String proposedValue;
  final double score;
  final String reason;
  final String? source;
  final double? threshold;
  final int? deadlineAt;
  final bool sourceCurrent;
  final bool reviewConflict;
  final List<String> evidenceSources;
}

final class PendingDateReview {
  const PendingDateReview({
    required this.id,
    required this.documentId,
    required this.documentTitle,
    required this.role,
    required this.date,
    required this.dateValue,
    required this.precision,
    required this.score,
    required this.reason,
    required this.extractor,
    required this.rawText,
    required this.evidenceText,
    required this.evidenceStart,
  });

  factory PendingDateReview.fromJson(Object? value) {
    final json = _object(value, 'pending date review');
    if (_string(json, 'type') != 'date' ||
        _string(json, 'status') != 'pending') {
      throw const ApiFormatException(
        'pending date review has an unsupported type or status',
      );
    }
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
    final role = _string(json, 'role');
    if (!roles.contains(role)) {
      throw const ApiFormatException('pending date review role is unsupported');
    }
    final dateJson = _object(json['value'], 'pending date value');
    final dateValue = _string(dateJson, 'date');
    final precision = _string(dateJson, 'precision');
    if (precision != 'day' && precision != 'month' && precision != 'year') {
      throw const ApiFormatException(
        'pending date review precision is unsupported',
      );
    }
    final date = _canonicalDate(dateValue);
    if ((precision == 'month' && date.day != 1) ||
        (precision == 'year' && (date.month != 1 || date.day != 1))) {
      throw const ApiFormatException(
        'pending date review does not match its precision',
      );
    }
    if (_string(json, 'sort_value') != dateValue) {
      throw const ApiFormatException(
        'pending date review sort value is inconsistent',
      );
    }
    final score = _number(json, 'confidence');
    if (score < 0 || score > 1) {
      throw const ApiFormatException(
        'pending date confidence must be between 0 and 1',
      );
    }
    final reason = _string(json, 'reason');
    if (reason != 'important_fact' && reason != 'low_confidence') {
      throw const ApiFormatException(
        'pending date review reason is unsupported',
      );
    }
    if (_string(json, 'policy_version') != 'review-first-v1' ||
        !_boolean(json, 'source_current')) {
      throw const ApiFormatException(
        'pending date review source is not current',
      );
    }
    _nonEmptyString(json, 'extractor');
    _positiveInteger(json, 'extraction_version');
    _nonNegativeInteger(json, 'created_at');
    _nonNegativeInteger(json, 'updated_at');
    _optionalString(json, 'document_sensitivity');
    _boolean(json, 'document_has_thumbnail');

    return PendingDateReview(
      id: _positiveInteger(json, 'id'),
      documentId: _positiveInteger(json, 'document_id'),
      documentTitle: _nonEmptyString(json, 'document_title'),
      role: role,
      date: date,
      dateValue: dateValue,
      precision: precision,
      score: score,
      reason: reason,
      extractor: _nonEmptyString(json, 'extractor'),
      rawText: _optionalString(json, 'raw_text') ?? '',
      evidenceText: _string(json, 'evidence_text'),
      evidenceStart: _optionalNonNegativeInteger(json, 'evidence_start'),
    );
  }

  final int id;
  final int documentId;
  final String documentTitle;
  final String role;
  final DateTime date;
  final String dateValue;
  final String precision;
  final double score;
  final String reason;
  final String extractor;
  final String rawText;
  final String evidenceText;
  final int? evidenceStart;
}

final class ReviewMutationResult {
  const ReviewMutationResult({
    required this.id,
    required this.ok,
    required this.code,
  });

  factory ReviewMutationResult.fromJson(Object? value) {
    final json = _object(value, 'review mutation result');
    final ok = _boolean(json, 'ok');
    final code = _optionalString(json, 'code');
    if ((ok && code != null) || (!ok && (code == null || code.isEmpty))) {
      throw const ApiFormatException('review mutation result is inconsistent');
    }
    return ReviewMutationResult(
      id: _positiveInteger(json, 'id'),
      ok: ok,
      code: code,
    );
  }

  final int id;
  final bool ok;
  final String? code;
}

final class TasksResponse {
  const TasksResponse({
    required this.results,
    required this.documentChangeApprovals,
  });

  factory TasksResponse.fromJson(Object? value) {
    final json = _object(value, 'tasks response');
    final rawCounts = _object(json['counts'], 'task counts');
    for (final entry in rawCounts.entries) {
      if (entry.value is! int || (entry.value as int) < 0) {
        throw ApiFormatException('task count ${entry.key} is invalid');
      }
    }
    final approvals = <DocumentChangeApprovalTask>[];
    if (json.containsKey('approval_tasks')) {
      for (final value in _list(json, 'approval_tasks')) {
        final approval = DocumentChangeApprovalTask.maybeFromJson(value);
        if (approval != null) approvals.add(approval);
      }
    }
    return TasksResponse(
      results: _list(
        json,
        'results',
      ).map(PostIngestTask.fromJson).toList(growable: false),
      documentChangeApprovals: List.unmodifiable(approvals),
    );
  }

  final List<PostIngestTask> results;
  final List<DocumentChangeApprovalTask> documentChangeApprovals;
}

Object? decodeJsonBody(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    throw const ApiFormatException('response body is not valid JSON');
  }
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, dynamic>) {
    throw ApiFormatException('$label must be a JSON object');
  }
  return value;
}

List<Object?> _list(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw ApiFormatException('$key must be a JSON array');
  }
  return value.cast<Object?>();
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw ApiFormatException('$key must be a string');
  }
  return value;
}

String _nonEmptyString(Map<String, Object?> json, String key) {
  final value = _string(json, key);
  if (value.trim().isEmpty) {
    throw ApiFormatException('$key must not be empty');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw ApiFormatException('$key must be a string when present');
  }
  return value;
}

bool? _optionalBoolean(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! bool) {
    throw ApiFormatException('$key must be a boolean when present');
  }
  return value;
}

bool _boolean(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw ApiFormatException('$key must be a boolean');
  }
  return value;
}

int _integer(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw ApiFormatException('$key must be an integer');
  }
  return value;
}

int _positiveInteger(Map<String, Object?> json, String key) {
  final value = _integer(json, key);
  if (value <= 0) throw ApiFormatException('$key must be positive');
  return value;
}

int _nonNegativeInteger(Map<String, Object?> json, String key) {
  final value = _integer(json, key);
  if (value < 0) throw ApiFormatException('$key must not be negative');
  return value;
}

int? _optionalPositiveInteger(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int || value <= 0) {
    throw ApiFormatException('$key must be positive when present');
  }
  return value;
}

int? _optionalNonNegativeInteger(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw ApiFormatException('$key must not be negative when present');
  }
  return value;
}

double _number(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) {
    throw ApiFormatException('$key must be a finite number');
  }
  return value.toDouble();
}

double? _optionalNumber(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num || !value.isFinite) {
    throw ApiFormatException('$key must be a finite number when present');
  }
  return value.toDouble();
}

DateTime _canonicalDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw const ApiFormatException(
      'pending date review date must use YYYY-MM-DD',
    );
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime.utc(year, month, day);
  if (year == 0 ||
      date.year != year ||
      date.month != month ||
      date.day != day) {
    throw const ApiFormatException('pending date review date is invalid');
  }
  return date;
}

List<String> _stringList(Map<String, Object?> json, String key) {
  final value = _list(json, key);
  if (value.any((item) => item is! String)) {
    throw ApiFormatException('$key must contain only strings');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

List<String> _optionalStringList(Map<String, Object?> json, String key) {
  if (!json.containsKey(key) || json[key] == null) return const [];
  return _stringList(json, key);
}
