import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:suchi_companion/scan/native_capture_store.dart';

void main() {
  late Directory temporary;
  late Directory root;
  late NativeCaptureStore store;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('suchi-native-capture-');
    root = Directory(path.join(temporary.path, nativeCaptureDirectoryName));
    await root.create();
    store = NativeCaptureStore(root);
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('recovers every valid native manifest in capture order', () async {
    await _capture(
      root,
      id: 'later',
      createdAt: '2026-09-02T10:00:00Z',
      pageNames: ['page-000.jpg', 'page-001.jpg'],
    );
    await _capture(
      root,
      id: 'earlier',
      createdAt: DateTime.utc(2026, 9, 2, 9).millisecondsSinceEpoch,
      pageNames: const [],
      pdfName: 'document.pdf',
    );

    final recovered = await store.recoverAll();

    expect(recovered, hasLength(2));
    expect(recovered.first.capture.pdfPath, endsWith('document.pdf'));
    expect(
      recovered.last.capture.pages.map((page) => path.basename(page.path)),
      ['page-000.jpg', 'page-001.jpg'],
    );
    expect(recovered.last.capture.pageCount, 2);
  });

  test(
    'removes incomplete and unsafe captures without following links',
    () async {
      final interrupted = Directory(path.join(root.path, 'interrupted'));
      await interrupted.create();
      await File(path.join(interrupted.path, 'page-000.jpg'))
          .writeAsBytes([1, 2, 3], flush: true);

      final malformed = Directory(path.join(root.path, 'malformed'));
      await malformed.create();
      await File(path.join(malformed.path, nativeCaptureManifestName))
          .writeAsString('{bad json', flush: true);

      final outside = File(path.join(temporary.path, 'outside.pdf'));
      await outside.writeAsBytes('%PDF-1.4\n'.codeUnits, flush: true);
      final linked = Directory(path.join(root.path, 'linked'));
      await linked.create();
      await Link(path.join(linked.path, 'document.pdf')).create(outside.path);
      await File(path.join(linked.path, nativeCaptureManifestName))
          .writeAsString(
            jsonEncode({
              'version': nativeCaptureManifestVersion,
              'created_at': DateTime.now().millisecondsSinceEpoch,
              'page_count': 1,
              'pdf_path': 'document.pdf',
              'pages': <String>[],
            }),
            flush: true,
          );

      expect(await store.recoverAll(), isEmpty);
      expect(await interrupted.exists(), isFalse);
      expect(await malformed.exists(), isFalse);
      expect(await linked.exists(), isFalse);
      expect(await outside.exists(), isTrue);
    },
  );
}

Future<void> _capture(
  Directory root, {
  required String id,
  required Object createdAt,
  required List<String> pageNames,
  String? pdfName,
}) async {
  final directory = Directory(path.join(root.path, id));
  await directory.create();
  for (final name in pageNames) {
    await File(path.join(directory.path, name))
        .writeAsBytes([1, 2, 3], flush: true);
  }
  if (pdfName != null) {
    await File(path.join(directory.path, pdfName))
        .writeAsBytes('%PDF-1.4\n'.codeUnits, flush: true);
  }
  await File(path.join(directory.path, nativeCaptureManifestName))
      .writeAsString(
        jsonEncode({
          'version': nativeCaptureManifestVersion,
          'created_at': createdAt,
          'page_count': pageNames.isEmpty ? 1 : pageNames.length,
          'pdf_path': pdfName,
          'pages': pageNames,
        }),
        flush: true,
      );
}
