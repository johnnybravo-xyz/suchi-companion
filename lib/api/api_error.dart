enum ApiFailureKind {
  network,
  timeout,
  cancelled,
  redirect,
  unauthorized,
  forbidden,
  conflict,
  server,
  rejected,
  malformedResponse,
  incompatibleServer,
}

final class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
    this.requestId,
    this.retryAfter,
  });

  final ApiFailureKind kind;
  final String message;
  final int? statusCode;
  final String? code;
  final String? requestId;
  final Duration? retryAfter;

  bool get expiresSession => kind == ApiFailureKind.unauthorized;

  @override
  String toString() {
    final requestSuffix = requestId == null ? '' : ' (request $requestId)';
    return '$message$requestSuffix';
  }
}

({String? code, String message}) parseApiError(Object? body, int statusCode) {
  const fallback = 'Suchi rejected the request.';
  if (body is! Map<String, dynamic>) {
    return (code: null, message: fallback);
  }

  String? code;
  String? message;
  final nested = body['error'];
  if (nested is Map<String, dynamic>) {
    code = _nonEmptyString(nested['code']);
    message =
        _nonEmptyString(nested['message']) ?? _nonEmptyString(nested['detail']);
  } else if (nested is String) {
    message = _nonEmptyString(nested);
  }
  code ??= _nonEmptyString(body['code']);
  message ??=
      _nonEmptyString(body['message']) ??
      _nonEmptyString(body['detail']) ??
      _nonEmptyString(body['error_description']);

  return (code: code, message: message ?? _statusFallback(statusCode));
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _statusFallback(int statusCode) => switch (statusCode) {
  400 => 'Suchi could not understand the request.',
  401 => 'Your Suchi session is no longer valid.',
  403 => 'This token does not have permission for that action.',
  404 => 'The requested item was not found.',
  409 => 'The request conflicts with existing data.',
  413 => 'The document is too large for this server.',
  429 => 'Suchi is receiving too many requests.',
  >= 500 => 'Suchi could not complete the request.',
  _ => 'Suchi rejected the request.',
};
