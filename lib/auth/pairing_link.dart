import 'server_origin.dart';

final class PairingLink {
  const PairingLink._({required this.origin, required this.code});

  factory PairingLink.parse(String input) {
    const invalid = FormatException(
      'This is not a valid Suchi pairing link. Generate a new one in the web app.',
    );
    final candidate = input.trim();
    // Uri normalizes away empty userinfo, so check the raw authority too.
    if (!candidate.startsWith('suchi://pair?')) throw invalid;
    final Uri uri;
    try {
      uri = Uri.parse(candidate);
    } on FormatException {
      throw invalid;
    }
    if (uri.scheme != 'suchi' ||
        uri.authority != 'pair' ||
        uri.path.isNotEmpty ||
        uri.hasFragment) {
      throw invalid;
    }
    final Map<String, List<String>> parameters;
    try {
      parameters = uri.queryParametersAll;
    } on FormatException {
      throw invalid;
    }
    if (parameters.length != 3 ||
        parameters['v']?.singleOrNull != '1' ||
        parameters['server']?.length != 1 ||
        parameters['code']?.length != 1) {
      throw invalid;
    }
    final code = parameters['code']!.single;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(code)) throw invalid;
    final Uri origin;
    try {
      origin = ServerOrigin.parse(parameters['server']!.single);
    } on ServerOriginException catch (error) {
      throw FormatException(error.message);
    }
    return PairingLink._(origin: origin, code: code);
  }

  final Uri origin;
  final String code;
}
