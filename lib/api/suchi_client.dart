import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_error.dart';
import 'api_models.dart';
import 'version.dart';

sealed class ThumbnailResult {
  const ThumbnailResult();
}

final class ThumbnailImage extends ThumbnailResult {
  const ThumbnailImage({required this.bytes, required this.etag});

  final Uint8List bytes;
  final String? etag;
}

final class ThumbnailGated extends ThumbnailResult {
  const ThumbnailGated({required this.sensitivity});

  final String sensitivity;
}

final class ThumbnailUnavailable extends ThumbnailResult {
  const ThumbnailUnavailable();
}

final class SuchiClient {
  SuchiClient({required this.origin, this.token, http.Client? httpClient})
    : assert(origin.path.isEmpty),
      _http = httpClient ?? http.Client(),
      _ownsClient = httpClient == null;

  static const _jsonBodyLimit = 8 * 1024 * 1024;
  static const _imageBodyLimit = 16 * 1024 * 1024;
  static const _authTimeout = Duration(seconds: 10);
  static const _readTimeout = Duration(seconds: 20);

  final Uri origin;
  final String? token;
  final http.Client _http;
  final bool _ownsClient;

  Future<Handshake> handshake() async {
    final response = await _request(
      'GET',
      '/api/handshake',
      authenticated: false,
      timeout: _authTimeout,
    );
    final handshake = _parseSuccess(response, Handshake.fromJson);
    if (handshake.product != 'suchi' ||
        handshake.apiVersion != supportedApiVersion ||
        compareSemanticVersions(handshake.minAppVersion, appVersion) > 0) {
      throw ApiException(
        kind: ApiFailureKind.incompatibleServer,
        message: 'This Suchi server is not compatible with this app.',
        statusCode: response.statusCode,
        requestId: response.requestId,
      );
    }
    return handshake;
  }

  Future<String> exchangePassword({
    required String email,
    required String password,
  }) async {
    final response = await _request(
      'POST',
      '/api/token/',
      authenticated: false,
      timeout: _authTimeout,
      jsonBody: {'email': email, 'password': password},
    );
    return _loginToken(response);
  }

  Future<String> exchangePairingCode(
    String code, {
    required String deviceName,
  }) async {
    final response = await _request(
      'POST',
      '/api/mobile/pairing/exchange',
      authenticated: false,
      timeout: _authTimeout,
      jsonBody: {'code': code, 'device_name': deviceName.trim()},
    );
    return _loginToken(response);
  }

  String _loginToken(_ApiResponse response) {
    final json = _parseSuccess(
      response,
      (value) => _asObject(value, 'login response'),
    );
    final value = json['token'];
    if (value is! String || !_validToken(value)) {
      throw ApiException(
        kind: ApiFailureKind.malformedResponse,
        message: 'Suchi returned an invalid login token.',
        statusCode: response.statusCode,
        requestId: response.requestId,
      );
    }
    return value;
  }

  Future<UserSelf> whoAmI() async {
    final response = await _request(
      'GET',
      '/api/whoami',
      timeout: _authTimeout,
    );
    return _parseSuccess(response, UserSelf.fromJson);
  }

  Future<void> logout() async {
    await _request(
      'POST',
      '/api/logout',
      timeout: _authTimeout,
      expectedStatuses: const {204},
    );
  }

  Future<PageEnvelope<DocumentSummary>> listDocuments({
    int page = 1,
    int pageSize = 50,
    String ordering = '-created_at',
    int? jdCategoryId,
    int? splitOriginId,
    bool trashed = false,
    SavedViewFilter? savedViewFilter,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'page_size': '$pageSize',
      'ordering': ordering,
      if (jdCategoryId != null) 'jd_category_id': '$jdCategoryId',
      if (splitOriginId != null) 'split_origin_id': '$splitOriginId',
      if (trashed) 'trashed': '1',
      ...?savedViewFilter?.queryParameters,
    };
    final response = await _request(
      'GET',
      '/api/documents/',
      query: query,
      timeout: _readTimeout,
    );
    final result = _parseSuccess(
      response,
      (value) => PageEnvelope.fromJson(value, DocumentSummary.fromJson),
    );
    if (splitOriginId != null &&
        result.results.any((item) => item.splitOriginId != splitOriginId)) {
      throw _malformed(
        response,
        'Suchi returned a document from the wrong split upload.',
      );
    }
    return result;
  }

  Future<PageEnvelope<SavedView>> listSavedViews({
    int page = 1,
    int pageSize = 100,
  }) async {
    final response = await _request(
      'GET',
      '/api/saved_views/',
      query: {'page': '$page', 'page_size': '$pageSize'},
      timeout: _readTimeout,
    );
    return _parseSuccess(
      response,
      (value) => PageEnvelope.fromJson(value, SavedView.fromJson),
    );
  }

  Future<int> createSavedView({
    required String name,
    required String filterJson,
    required int position,
  }) async {
    final response = await _request(
      'POST',
      '/api/saved_views/',
      jsonBody: {
        'name': name,
        'filter_json': filterJson,
        'display': 'list',
        'position': position,
        'shared': false,
      },
      timeout: _readTimeout,
      expectedStatuses: const {201},
    );
    return _parseSuccess(response, (value) {
      if (value is! Map<String, dynamic>) {
        throw const ApiFormatException(
          'saved view create response must be an object',
        );
      }
      final id = value['id'];
      if (id is! int || id <= 0) {
        throw const ApiFormatException('saved view create id must be positive');
      }
      return id;
    });
  }

  Future<void> deleteSavedView(int id) async {
    await _request(
      'DELETE',
      '/api/saved_views/$id',
      timeout: _readTimeout,
      expectedStatuses: const {204},
    );
  }

  Future<List<DocumentSummary>> splitDocuments(int originId) async {
    final children = <DocumentSummary>[];
    var page = 1;
    while (true) {
      final response = await listDocuments(
        page: page,
        pageSize: 200,
        splitOriginId: originId,
      );
      children.addAll(response.results);
      if (children.length >= response.count) return children;
      if (response.results.isEmpty || page >= 50) {
        throw const ApiException(
          kind: ApiFailureKind.malformedResponse,
          message: 'Suchi returned incomplete split-document results.',
        );
      }
      page++;
    }
  }

  Future<DocumentDetail> document(int id) async {
    final response = await _request(
      'GET',
      '/api/documents/$id',
      query: const {'include_content': '0'},
      timeout: _readTimeout,
    );
    final result = _parseSuccess(response, DocumentDetail.fromJson);
    if (result.id != id) {
      throw _malformed(response, 'Suchi returned the wrong document.');
    }
    return result;
  }

  Future<({String text, String sensitivity})> documentText(int id) async {
    final response = await _request(
      'GET',
      '/api/documents/$id',
      query: const {'include_content': '1'},
      timeout: _readTimeout,
    );
    final json = _decodeSuccessJson(response);
    if (json is! Map<String, dynamic> ||
        json['id'] is! int ||
        json['id'] != id ||
        json['content'] is! String ||
        !const {
          null,
          '',
          'public',
          'internal',
          'confidential',
          'restricted',
        }.contains(json['sensitivity'])) {
      throw _malformed(response, 'Suchi returned invalid document text.');
    }
    return (
      text: json['content'] as String,
      sensitivity: json['sensitivity'] as String? ?? '',
    );
  }

  Future<PageEnvelope<SearchHit>> search({
    required String query,
    int page = 1,
    int pageSize = 25,
  }) async {
    final response = await _request(
      'GET',
      '/api/search/',
      query: {'q': query, 'page': '$page', 'page_size': '$pageSize'},
      timeout: _readTimeout,
    );
    return _parseSuccess(
      response,
      (value) => PageEnvelope.fromJson(value, SearchHit.fromJson),
    );
  }

  Future<PageEnvelope<JDCategory>> jdCategories({
    int page = 1,
    int pageSize = 100,
    String? query,
    int? area,
  }) async {
    final response = await _request(
      'GET',
      '/api/jd/categories/',
      query: {
        'page': '$page',
        'page_size': '$pageSize',
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (area != null) 'area': '$area',
      },
      timeout: _readTimeout,
    );
    return _parseSuccess(
      response,
      (value) => PageEnvelope.fromJson(value, JDCategory.fromJson),
    );
  }

  Future<TasksResponse> tasksForDocument(int documentId) async {
    final response = await _request(
      'GET',
      '/api/tasks/',
      query: {
        'doc_id': '$documentId',
        'kind': 'post-ingest',
        'include': 'jobs',
        'limit': '50',
      },
      timeout: _readTimeout,
    );
    return _parseSuccess(response, TasksResponse.fromJson);
  }

  Future<int> patchDocument(
    int id, {
    String? title,
    String? sensitivity,
    int? jdCategoryId,
    List<String>? languages,
  }) async {
    final body = <String, Object>{
      'title': ?title,
      'sensitivity': ?sensitivity,
      'jd_category_id': ?jdCategoryId,
      'languages': ?languages,
    };
    if (body.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.rejected,
        message: 'No document changes were provided.',
      );
    }
    final response = await _request(
      'PATCH',
      '/api/documents/$id',
      jsonBody: body,
      timeout: _readTimeout,
    );
    final json = _parseSuccess(
      response,
      (value) => _asObject(value, 'update response'),
    );
    final updatedId = json['id'];
    if (updatedId is! int || updatedId != id) {
      throw ApiException(
        kind: ApiFailureKind.malformedResponse,
        message: 'Suchi returned an invalid document update response.',
        statusCode: response.statusCode,
        requestId: response.requestId,
      );
    }
    return updatedId;
  }

  Future<void> trashDocument(int id) async {
    await _request(
      'DELETE',
      '/api/documents/$id',
      expectedStatuses: const {204},
      timeout: _readTimeout,
    );
  }

  Future<void> restoreDocument(int id) async {
    await _request('POST', '/api/documents/$id/restore', timeout: _readTimeout);
  }

  Future<String> emailPreview(int id, {bool reveal = false}) async {
    final response = await _request(
      'GET',
      '/api/documents/$id/preview',
      query: reveal ? const {'reveal': '1'} : null,
      timeout: _readTimeout,
      expectedStatuses: const {200, 202},
      bodyLimit: _jsonBodyLimit,
      accept: 'text/html',
    );
    if (response.statusCode == 202) {
      final json = _parseSuccess(
        response,
        (value) => _asObject(value, 'email preview gate'),
      );
      if (json['gated'] != true || json['sensitivity'] is! String) {
        throw _malformed(
          response,
          'Suchi returned an invalid email preview gate.',
        );
      }
      throw ApiException(
        kind: ApiFailureKind.rejected,
        message: 'Reveal this sensitive document before previewing it.',
        statusCode: response.statusCode,
        requestId: response.requestId,
      );
    }
    final contentType = response.contentType;
    late final MediaType mediaType;
    try {
      mediaType = MediaType.parse(contentType ?? '');
    } on FormatException {
      throw _malformed(
        response,
        'Suchi returned an invalid email preview type.',
      );
    }
    if (mediaType.mimeType != 'text/html' ||
        mediaType.parameters['charset']?.toLowerCase() != 'utf-8') {
      throw _malformed(
        response,
        'Suchi returned an unsupported email preview type.',
      );
    }
    try {
      return utf8.decode(response.body, allowMalformed: false);
    } on FormatException {
      throw _malformed(response, 'Suchi returned invalid UTF-8.');
    }
  }

  Future<String> downloadDocument(
    int id, {
    required File destination,
    bool reveal = false,
    bool preview = false,
    Future<void>? abortTrigger,
  }) async {
    const byteLimit = 64 * 1024 * 1024;
    if (id <= 0 || !_validToken(token ?? '')) {
      throw const ApiException(
        kind: ApiFailureKind.unauthorized,
        message: 'Pair this device with Suchi before continuing.',
      );
    }
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const ApiException(
        kind: ApiFailureKind.rejected,
        message: 'The temporary document file already exists.',
      );
    }
    final abort = Completer<void>();
    var timedOut = false;
    void cancel() {
      if (!abort.isCompleted) abort.complete();
    }

    if (abortTrigger != null) unawaited(abortTrigger.then((_) => cancel()));
    final timer = Timer(const Duration(minutes: 3), () {
      timedOut = true;
      cancel();
    });
    RandomAccessFile? output;
    var completed = false;
    try {
      final request =
          http.AbortableRequest(
              'GET',
              origin.replace(
                path: '/api/documents/$id/${preview ? 'preview' : 'download'}',
                queryParameters: reveal ? const {'reveal': '1'} : null,
              ),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..maxRedirects = 0
            ..headers['Authorization'] = 'Token $token'
            ..headers['Accept'] = '*/*';
      final response = await _http.send(request).timeout(_readTimeout);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        await response.stream.listen((_) {}).cancel();
        throw ApiException(
          kind: ApiFailureKind.redirect,
          message: 'Suchi redirected the document request. Check the server address.',
          statusCode: response.statusCode,
          requestId: _requestId(response.headers),
        );
      }
      if (response.statusCode != 200) {
        final error = await _readResponse(
          response,
          _jsonBodyLimit,
        ).timeout(_readTimeout);
        if (response.statusCode == 202) {
          throw ApiException(
            kind: ApiFailureKind.rejected,
            message:
                'Reveal this sensitive document before opening or sharing it.',
            statusCode: 202,
            requestId: error.requestId,
          );
        }
        throw _httpError(error);
      }
      final mimeType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (mimeType == null ||
          !RegExp(r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$')
              .hasMatch(mimeType)) {
        await response.stream.listen((_) {}).cancel();
        throw const ApiException(
          kind: ApiFailureKind.malformedResponse,
          message: 'Suchi returned an invalid document type.',
        );
      }
      if ((response.contentLength ?? 0) > byteLimit) {
        await response.stream.listen((_) {}).cancel();
        throw const ApiException(
          kind: ApiFailureKind.rejected,
          message: 'Documents larger than 64 MiB must be opened in the Suchi web app.',
        );
      }
      output = await destination.open(mode: FileMode.write);
      var received = 0;
      await for (final chunk in response.stream.timeout(_readTimeout)) {
        if (abort.isCompleted) {
          throw http.RequestAbortedException();
        }
        received += chunk.length;
        if (received > byteLimit) {
          throw const ApiException(
            kind: ApiFailureKind.rejected,
            message: 'Documents larger than 64 MiB must be opened in the Suchi web app.',
          );
        }
        await output.writeFrom(chunk);
      }
      if (abort.isCompleted) throw http.RequestAbortedException();
      if (received == 0 ||
          response.contentLength != null &&
              received != response.contentLength) {
        throw const ApiException(
          kind: ApiFailureKind.malformedResponse,
          message: 'The document download was empty or incomplete.',
        );
      }
      await output.flush();
      completed = true;
      return mimeType;
    } on TimeoutException {
      throw const ApiException(
        kind: ApiFailureKind.timeout,
        message: 'The document download did not finish in time.',
      );
    } on http.RequestAbortedException {
      throw ApiException(
        kind: timedOut ? ApiFailureKind.timeout : ApiFailureKind.cancelled,
        message: timedOut
            ? 'The document download did not finish in time.'
            : 'The document download was cancelled.',
      );
    } on SocketException {
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: 'Could not reach the Suchi server.',
      );
    } on TlsException {
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: 'Could not establish a secure connection to Suchi.',
      );
    } on http.ClientException {
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: 'The document download connection failed.',
      );
    } finally {
      timer.cancel();
      cancel();
      await output?.close();
      if (!completed && output != null && await destination.exists()) {
        await destination.delete();
      }
    }
  }

  Future<ThumbnailResult> thumbnail(
    int id, {
    bool reveal = false,
    int width = 160,
  }) async {
    if (width < 64 || width > 512) {
      throw const ApiException(
        kind: ApiFailureKind.rejected,
        message: 'Thumbnail width must be between 64 and 512 pixels.',
      );
    }
    final response = await _request(
      'GET',
      '/api/documents/$id/thumb',
      query: {'width': '$width', if (reveal) 'reveal': '1'},
      timeout: _readTimeout,
      expectedStatuses: const {200, 202, 404},
      bodyLimit: _imageBodyLimit,
    );
    if (response.statusCode == 404) return const ThumbnailUnavailable();
    if (response.statusCode == 202) {
      final json = _parseSuccess(
        response,
        (value) => _asObject(value, 'thumbnail gate'),
      );
      final sensitivity = json['sensitivity'];
      final gated = json['gated'];
      if (sensitivity is! String || gated != true) {
        throw _malformed(response, 'Suchi returned an invalid thumbnail gate.');
      }
      return ThumbnailGated(sensitivity: sensitivity);
    }
    if (!_isContentType(response.contentType, 'image/png')) {
      throw _malformed(
        response,
        'Suchi returned an unsupported thumbnail type.',
      );
    }
    return ThumbnailImage(bytes: response.body, etag: response.etag);
  }

  Future<UploadResult> uploadDocument({
    required File file,
    required int byteSize,
    required String sha256Hex,
    required String mimeType,
    required String filename,
    required String idempotencyKey,
    int? sourceMtime,
    String? ocrContent,
    double? ocrConfidence,
    String? ocrLanguage,
    void Function(int bytesSent)? onProgress,
    Future<void>? abortTrigger,
  }) async {
    if (!_validToken(token ?? '') ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(idempotencyKey) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256Hex) ||
        byteSize <= 0 ||
        !_validFilename(filename) ||
        !const {
          'application/pdf',
          'image/jpeg',
          'image/png',
          'image/heic',
          'image/heif',
        }.contains(mimeType) ||
        sourceMtime != null && sourceMtime <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.rejected,
        message: 'The staged upload metadata is invalid.',
      );
    }
    final hasOcr =
        ocrContent != null || ocrConfidence != null || ocrLanguage != null;
    if (hasOcr &&
        (mimeType != 'application/pdf' ||
            ocrContent == null ||
            ocrContent.isEmpty ||
            utf8.encode(ocrContent).length > 1024 * 1024 ||
            ocrConfidence == null ||
            !ocrConfidence.isFinite ||
            ocrConfidence < 0 ||
            ocrConfidence > 1 ||
            ocrLanguage == null ||
            !RegExp(r'^[a-z]{2,3}(?:[-_][A-Z]{2})?$').hasMatch(ocrLanguage))) {
      throw const ApiException(
        kind: ApiFailureKind.rejected,
        message: 'The staged device text metadata is invalid.',
      );
    }
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() != byteSize) {
      throw const ApiException(
        kind: ApiFailureKind.rejected,
        message: 'The staged upload payload is missing or changed.',
      );
    }

    final abort = Completer<void>();
    if (abortTrigger != null) {
      unawaited(
        abortTrigger.whenComplete(() {
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }
    var sent = 0;
    Stream<List<int>> countedPayload() async* {
      await for (final chunk in file.openRead()) {
        sent += chunk.length;
        onProgress?.call(sent.clamp(0, byteSize));
        yield chunk;
      }
    }

    final request =
        http.AbortableMultipartRequest(
            'POST',
            origin.replace(path: '/api/documents/'),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..maxRedirects = 0
          ..headers['Accept'] = 'application/json'
          ..headers['Authorization'] = 'Token $token'
          ..headers['Idempotency-Key'] = idempotencyKey
          ..files.add(
            http.MultipartFile(
              'document',
              countedPayload(),
              byteSize,
              filename: filename,
              contentType: MediaType.parse(mimeType),
            ),
          );
    if (sourceMtime != null) request.fields['source_mtime'] = '$sourceMtime';
    if (hasOcr) {
      request.fields['content'] = ocrContent!;
      request.fields['content_source'] = 'device_ocr';
      request.fields['content_confidence'] = ocrConfidence!.toString();
      request.fields['ocr_language'] = ocrLanguage!;
    }

    final response =
        await _sendPrepared(
          request,
          expectedStatuses: const {200, 201},
          bodyLimit: _jsonBodyLimit,
        ).timeout(
          const Duration(minutes: 5),
          onTimeout: () {
            if (!abort.isCompleted) abort.complete();
            throw const ApiException(
              kind: ApiFailureKind.timeout,
              message: 'The document upload did not finish in time.',
            );
          },
        );
    final result = _parseSuccess(
      response,
      (value) => UploadResult.fromJson(value, statusCode: response.statusCode),
    );
    if (result.sha256 != sha256Hex ||
        result.size != byteSize ||
        result.mimeType != mimeType ||
        response.headers['location'] != '/api/documents/${result.id}') {
      throw _malformed(
        response,
        'Suchi returned an inconsistent upload response.',
      );
    }
    return result;
  }

  void close() {
    if (_ownsClient) _http.close();
  }

  Future<_ApiResponse> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object>? jsonBody,
    bool authenticated = true,
    required Duration timeout,
    Set<int> expectedStatuses = const {200, 201},
    int bodyLimit = _jsonBodyLimit,
    String accept = 'application/json',
  }) {
    return _requestUnbounded(
      method,
      path,
      query: query,
      jsonBody: jsonBody,
      authenticated: authenticated,
      expectedStatuses: expectedStatuses,
      bodyLimit: bodyLimit,
      accept: accept,
    ).timeout(
      timeout,
      onTimeout: () => throw const ApiException(
        kind: ApiFailureKind.timeout,
        message: 'Suchi did not respond in time.',
      ),
    );
  }

  Future<_ApiResponse> _requestUnbounded(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object>? jsonBody,
    required bool authenticated,
    required Set<int> expectedStatuses,
    required int bodyLimit,
    required String accept,
  }) async {
    if (!path.startsWith('/api/') || path.contains('?') || path.contains('#')) {
      throw const ApiException(
        kind: ApiFailureKind.rejected,
        message: 'The app attempted an invalid Suchi API path.',
      );
    }
    final uri = origin.replace(path: path, queryParameters: query);
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers['Accept'] = accept;
    if (authenticated) {
      final authToken = token;
      if (authToken == null || !_validToken(authToken)) {
        throw const ApiException(
          kind: ApiFailureKind.unauthorized,
          message: 'Pair this device with Suchi before continuing.',
        );
      }
      request.headers['Authorization'] = 'Token $authToken';
    }
    if (jsonBody != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.bodyBytes = utf8.encode(jsonEncode(jsonBody));
    }

    return _sendPrepared(
      request,
      expectedStatuses: expectedStatuses,
      bodyLimit: bodyLimit,
    );
  }

  Future<_ApiResponse> _sendPrepared(
    http.BaseRequest request, {
    required Set<int> expectedStatuses,
    required int bodyLimit,
  }) async {
    try {
      final streamed = await _http.send(request);
      final response = await _readResponse(streamed, bodyLimit);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw ApiException(
          kind: ApiFailureKind.redirect,
          message:
              'Suchi redirected the API request. Check the server address.',
          statusCode: response.statusCode,
          requestId: response.requestId,
        );
      }
      if (!expectedStatuses.contains(response.statusCode)) {
        throw _httpError(response);
      }
      return response;
    } on ApiException {
      rethrow;
    } on http.RequestAbortedException catch (_) {
      throw const ApiException(
        kind: ApiFailureKind.cancelled,
        message: 'The request was paused.',
      );
    } on SocketException catch (_) {
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: 'Could not reach the Suchi server.',
      );
    } on TlsException catch (_) {
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: 'Could not establish a secure connection to Suchi.',
      );
    } on http.ClientException catch (_) {
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: 'The connection to Suchi failed.',
      );
    }
  }

  Future<_ApiResponse> _readResponse(
    http.StreamedResponse response,
    int limit,
  ) async {
    final declaredLength = response.contentLength;
    if (declaredLength != null && declaredLength > limit) {
      throw ApiException(
        kind: ApiFailureKind.malformedResponse,
        message: 'Suchi returned a response that is too large.',
        statusCode: response.statusCode,
        requestId: _requestId(response.headers),
      );
    }
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response.stream) {
      length += chunk.length;
      if (length > limit) {
        throw ApiException(
          kind: ApiFailureKind.malformedResponse,
          message: 'Suchi returned a response that is too large.',
          statusCode: response.statusCode,
          requestId: _requestId(response.headers),
        );
      }
      builder.add(chunk);
    }
    return _ApiResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: builder.takeBytes(),
    );
  }

  Object? _decodeSuccessJson(_ApiResponse response) {
    if (!_isJson(response.contentType)) {
      throw _malformed(
        response,
        'Suchi returned an unsupported response type.',
      );
    }
    return _decodeJson(response);
  }

  Object? _decodeJson(_ApiResponse response) {
    try {
      return decodeJsonBody(utf8.decode(response.body, allowMalformed: false));
    } on FormatException catch (_) {
      throw _malformed(response, 'Suchi returned invalid UTF-8.');
    } on ApiFormatException catch (error) {
      throw _malformed(response, error.message);
    }
  }

  T _parseSuccess<T>(_ApiResponse response, T Function(Object? value) parser) {
    try {
      return parser(_decodeSuccessJson(response));
    } on ApiFormatException catch (error) {
      throw _malformed(response, error.message);
    }
  }

  ApiException _httpError(_ApiResponse response) {
    Object? json;
    if (_isJson(response.contentType)) {
      try {
        json = _decodeJson(response);
      } on ApiException catch (_) {
        json = null;
      }
    }
    final error = parseApiError(json, response.statusCode);
    final kind = switch (response.statusCode) {
      401 => ApiFailureKind.unauthorized,
      403 => ApiFailureKind.forbidden,
      409 => ApiFailureKind.conflict,
      >= 500 => ApiFailureKind.server,
      _ => ApiFailureKind.rejected,
    };
    return ApiException(
      kind: kind,
      message: error.message,
      statusCode: response.statusCode,
      code: error.code,
      requestId: response.requestId,
      retryAfter: _retryAfter(response.headers['retry-after']),
    );
  }

  ApiException _malformed(_ApiResponse response, String message) =>
      ApiException(
        kind: ApiFailureKind.malformedResponse,
        message: message,
        statusCode: response.statusCode,
        requestId: response.requestId,
      );

  static bool _validFilename(String value) =>
      value.isNotEmpty &&
      value != '.' &&
      value != '..' &&
      utf8.encode(value).length <= 255 &&
      !value.contains('/') &&
      !value.contains('\\') &&
      !value.runes.any((rune) => rune < 0x20 || rune == 0x7f);

  static bool _validToken(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  static bool _isJson(String? contentType) =>
      _isContentType(contentType, 'application/json') ||
      (contentType?.toLowerCase().split(';').first.trim().endsWith('+json') ??
          false);

  static bool _isContentType(String? actual, String expected) =>
      actual?.toLowerCase().split(';').first.trim() == expected;

  static Duration? _retryAfter(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
    try {
      final date = HttpDate.parse(value);
      final duration = date.difference(DateTime.now().toUtc());
      return duration.isNegative ? Duration.zero : duration;
    } on FormatException {
      return null;
    }
  }

  static String? _requestId(Map<String, String> headers) {
    final value = headers['x-request-id']?.trim();
    if (value == null || value.isEmpty || value.length > 200) return null;
    if (value.contains('\n') || value.contains('\r')) return null;
    return value;
  }
}

final class _ApiResponse {
  const _ApiResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Uint8List body;

  String? get contentType => headers['content-type'];
  String? get requestId => SuchiClient._requestId(headers);
  String? get etag => headers['etag'];
}

Map<String, Object?> _asObject(Object? value, String label) {
  if (value is! Map<String, dynamic>) {
    throw ApiFormatException('$label must be a JSON object');
  }
  return value;
}
