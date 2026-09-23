import 'dart:io';

import 'package:flutter/services.dart' show appBuildName;
import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_mobile/api/api_error.dart';
import 'package:suchi_mobile/api/version.dart';

void main() {
  test('mobile API app version matches pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      RegExp(
        r'^version:\s+([^+\s]+)',
        multiLine: true,
      ).firstMatch(pubspec)?.group(1),
      appVersion,
    );
    expect(supportedApiVersion, 1);
    expect(appVersion, appBuildName);
  });

  test('semantic versions compare numeric components strictly', () {
    expect(compareSemanticVersions('0.10.0', '0.2.9'), greaterThan(0));
    expect(compareSemanticVersions('1.0.0', '1.0.0'), 0);
    expect(compareSemanticVersions('1.0.0', '1.0.1'), lessThan(0));
    expect(
      () => compareSemanticVersions('1.0', '1.0.0'),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => compareSemanticVersions('1.0.0-beta', '1.0.0'),
      throwsA(isA<ApiException>()),
    );
  });
}
