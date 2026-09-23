import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

Future<void> main(List<String> arguments) async {
  var check = false;
  String? serverRoot;
  for (var index = 0; index < arguments.length; index++) {
    switch (arguments[index]) {
      case '--check':
        check = true;
      case '--server-root':
        if (index + 1 >= arguments.length) _usage();
        serverRoot = arguments[++index];
      default:
        stderr.writeln('Unknown argument: ${arguments[index]}');
        _usage();
    }
  }
  if (serverRoot == null) _usage();

  final source = Directory(
    path.join(serverRoot, 'core', 'api', 'testdata', 'mobile', 'v1'),
  );
  final destination = Directory(path.join('test', 'fixtures', 'api', 'v1'));
  if (!source.existsSync()) {
    stderr.writeln('Server fixture directory does not exist: ${source.path}');
    exitCode = 2;
    return;
  }

  final sourceFiles =
      source
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => path.extension(file.path) == '.json')
          .toList()
        ..sort(
          (a, b) => path.basename(a.path).compareTo(path.basename(b.path)),
        );
  if (sourceFiles.isEmpty) {
    stderr.writeln('Server fixture directory contains no JSON fixtures.');
    exitCode = 2;
    return;
  }

  final manifest = StringBuffer();
  final expectedNames = <String>{};
  for (final sourceFile in sourceFiles) {
    final name = path.basename(sourceFile.path);
    expectedNames.add(name);
    manifest.writeln('${sha256.convert(sourceFile.readAsBytesSync())}  $name');
  }
  const manifestName = 'manifest.sha256';
  expectedNames.add(manifestName);
  final manifestBytes = manifest.toString().codeUnits;

  if (check) {
    if (!destination.existsSync()) {
      stderr.writeln('Mobile fixture directory does not exist.');
      exitCode = 1;
      return;
    }
    final actualNames = destination
        .listSync(followLinks: false)
        .whereType<File>()
        .map((file) => path.basename(file.path))
        .toSet();
    if (!_sameSet(expectedNames, actualNames)) {
      stderr.writeln('Mobile fixture file set is out of date.');
      exitCode = 1;
      return;
    }
    for (final sourceFile in sourceFiles) {
      final destinationFile = File(
        path.join(destination.path, path.basename(sourceFile.path)),
      );
      if (!_sameBytes(
        sourceFile.readAsBytesSync(),
        destinationFile.readAsBytesSync(),
      )) {
        stderr.writeln('${path.basename(sourceFile.path)} is out of date.');
        exitCode = 1;
        return;
      }
    }
    final actualManifest = File(path.join(destination.path, manifestName))
        .readAsBytesSync();
    if (!_sameBytes(manifestBytes, actualManifest)) {
      stderr.writeln('Fixture checksum manifest is out of date.');
      exitCode = 1;
      return;
    }
    stdout.writeln('Mobile API fixtures match the server contract.');
    return;
  }

  destination.createSync(recursive: true);
  for (final entity in destination.listSync(followLinks: false)) {
    if (entity is File) entity.deleteSync();
  }
  for (final sourceFile in sourceFiles) {
    sourceFile.copySync(
      path.join(destination.path, path.basename(sourceFile.path)),
    );
  }
  File(path.join(destination.path, manifestName))
      .writeAsBytesSync(manifestBytes, flush: true);
  stdout.writeln('Synchronized ${sourceFiles.length} mobile API fixtures.');
}

Never _usage() {
  stderr.writeln(
    'Usage: dart run tool/sync_api_fixtures.dart [--check] '
    '--server-root <suchi-repo>',
  );
  exit(64);
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
