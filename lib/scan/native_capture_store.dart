import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'scanner_bridge.dart';
import 'storage_protection.dart';

const nativeCaptureManifestVersion = 1;
const nativeCaptureDirectoryName = 'suchi-scanner-captures';
const nativeCaptureManifestName = 'manifest.json';

final class PendingNativeCapture {
  const PendingNativeCapture({required this.capture, required this.createdAt});

  final CaptureResult capture;
  final DateTime createdAt;
}

final class NativeCaptureStore {
  NativeCaptureStore(this.root);

  final Directory root;

  static Future<NativeCaptureStore> open({
    StorageProtection storageProtection = const NativeStorageProtection(),
  }) async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(path.join(support.path, nativeCaptureDirectoryName));
    await root.create(recursive: true);
    await storageProtection.protectDirectory(root.absolute.path);
    return NativeCaptureStore(root.absolute);
  }

  Future<List<PendingNativeCapture>> recoverAll() async {
    if (!await root.exists()) return const [];
    final rootPath = await root.resolveSymbolicLinks();
    final pending = <PendingNativeCapture>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory ||
          await FileSystemEntity.type(entry.path, followLinks: false) !=
              FileSystemEntityType.directory) {
        continue;
      }
      final directoryPath = await entry.resolveSymbolicLinks();
      if (Directory(directoryPath).parent.path != rootPath) continue;
      final manifest = File(path.join(entry.path, nativeCaptureManifestName));
      if (await FileSystemEntity.type(manifest.path, followLinks: false) !=
          FileSystemEntityType.file) {
        await _discardInvalidCapture(entry);
        continue;
      }
      try {
        pending.add(await _readManifest(manifest));
      } on FormatException {
        await _discardInvalidCapture(entry);
        continue;
      } on FileSystemException {
        continue;
      }
    }
    pending.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return List.unmodifiable(pending);
  }

  Future<void> _discardInvalidCapture(Directory directory) async {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // A later resume retries cleanup without hiding valid captures.
    }
  }

  Future<PendingNativeCapture> _readManifest(File manifest) async {
    if (await manifest.length() > 64 * 1024) {
      throw const FormatException('Capture manifest is too large.');
    }
    final decoded = jsonDecode(await manifest.readAsString(encoding: utf8));
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != nativeCaptureManifestVersion ||
        decoded['page_count'] is! int ||
        decoded['pages'] is! List) {
      throw const FormatException('Capture manifest is invalid.');
    }
    final pageCount = decoded['page_count'] as int;
    final rawPages = decoded['pages'] as List;
    if (pageCount <= 0 ||
        pageCount > 100 ||
        rawPages.length > pageCount ||
        rawPages.length > 100) {
      throw const FormatException('Capture page count is invalid.');
    }
    final directory = manifest.parent;
    final pages = <CapturedPage>[];
    for (final value in rawPages) {
      final file = await _regularCaptureFile(directory, value);
      pages.add(CapturedPage(path: file.path));
    }
    final rawPdf = decoded['pdf_path'];
    final pdf = rawPdf == null
        ? null
        : await _regularCaptureFile(directory, rawPdf);
    if (pages.isEmpty && pdf == null) {
      throw const FormatException('Capture has no recoverable files.');
    }
    return PendingNativeCapture(
      capture: CaptureResult(
        cancelled: false,
        pageCount: pageCount,
        pages: List.unmodifiable(pages),
        pdfPath: pdf?.path,
      ),
      createdAt: _createdAt(decoded['created_at']),
    );
  }

  Future<File> _regularCaptureFile(Directory directory, Object? rawName) async {
    if (rawName is! String || !_validBasename(rawName)) {
      throw const FormatException('Capture filename is invalid.');
    }
    final file = File(path.join(directory.path, rawName));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('Capture file is missing or unsafe.');
    }
    final resolvedDirectory = await directory.resolveSymbolicLinks();
    final resolvedFile = await file.resolveSymbolicLinks();
    if (File(resolvedFile).parent.path != resolvedDirectory) {
      throw const FormatException('Capture file escaped its directory.');
    }
    return File(resolvedFile);
  }

  DateTime _createdAt(Object? value) {
    if (value is int && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    throw const FormatException('Capture timestamp is invalid.');
  }

  bool _validBasename(String value) =>
      value.isNotEmpty &&
      value != '.' &&
      value != '..' &&
      path.basename(value) == value &&
      !value.contains('/') &&
      !value.contains('\\') &&
      !value.runes.any((rune) => rune < 0x20 || rune == 0x7f);
}
