import 'api_error.dart';

import 'package:flutter/services.dart' show appBuildName;

const supportedApiVersion = 1;
const appVersion = appBuildName ?? '0.0.0';

int compareSemanticVersions(String left, String right) {
  List<int> parse(String value) {
    final match = RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')
        .firstMatch(value);
    if (match == null) {
      throw const ApiException(
        kind: ApiFailureKind.incompatibleServer,
        message: 'Suchi returned an invalid compatibility version.',
      );
    }
    return [
      for (var index = 1; index <= 3; index++) int.parse(match.group(index)!),
    ];
  }

  final a = parse(left);
  final b = parse(right);
  for (var index = 0; index < a.length; index++) {
    final comparison = a[index].compareTo(b[index]);
    if (comparison != 0) return comparison;
  }
  return 0;
}
