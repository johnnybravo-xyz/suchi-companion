import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../api/api_error.dart';
import '../api/suchi_client.dart';
import '../scan/storage_protection.dart';

final class DocumentFiles {
  DocumentFiles({required this.root, MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('page.suchi.companion/documents');

  final Directory root;
  final MethodChannel _channel;
  Future<void>? _operation;
  Future<void> _cleanup = Future.value();
  Completer<void>? _abort;
  int _generation = 0;

  static Future<DocumentFiles> open() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(path.join(support.path, 'suchi-document-exports'));
    await root.create(recursive: true);
    await const NativeStorageProtection().protectDirectory(root.path);
    final files = DocumentFiles(root: root);
    await files.clear();
    return files;
  }

  Future<void> handoff({
    required SuchiClient client,
    required int documentId,
    required bool share,
    bool reveal = false,
  }) async {
    var generation = _generation;
    try {
      await _cleanup;
    } catch (_) {
      if (generation != _generation) return;
      generation++;
      await clear();
    }
    if (generation != _generation) return;
    if (_operation != null) {
      throw PlatformException(
        code: 'document_busy',
        message: 'Another document is already being prepared.',
      );
    }
    final abort = Completer<void>();
    _abort = abort;
    final operation = _handoff(
      client: client,
      documentId: documentId,
      share: share,
      reveal: reveal,
      generation: generation,
      abort: abort.future,
    );
    _operation = operation;
    try {
      await operation;
    } finally {
      _operation = null;
      _abort = null;
    }
  }

  Future<void> handoffLocal({
    required File file,
    required String mimeType,
    required bool share,
  }) async {
    final generation = _generation;
    await _cleanup;
    if (generation != _generation) return;
    if (_operation != null) {
      throw PlatformException(
        code: 'document_busy',
        message: 'Another document is already being prepared.',
      );
    }
    final operation = _channel.invokeMethod<void>(share ? 'share' : 'open', {
      'path': file.path,
      'mime_type': mimeType,
    });
    _operation = operation;
    try {
      await operation;
    } finally {
      _operation = null;
    }
  }

  Future<void> _handoff({
    required SuchiClient client,
    required int documentId,
    required bool share,
    required bool reveal,
    required int generation,
    required Future<void> abort,
  }) async {
    await _removeExpired();
    final directory = await root.createTemp('document-');
    var retained = false;
    try {
      final partial = File(path.join(directory.path, 'download.part'));
      final download = await client.downloadDocument(
        documentId,
        destination: partial,
        preview: !share,
        reveal: reveal,
        abortTrigger: abort,
      );
      if (generation != _generation) return;
      final file = await partial.rename(
        path.join(
          directory.path,
          'document-$documentId${extensionForMimeType(download.mimeType)}',
        ),
      );
      if (generation != _generation) return;
      await _channel.invokeMethod<void>(share ? 'share' : 'open', {
        'path': file.path,
        'mime_type': download.mimeType,
      });
      // Android recipients may read after the chooser returns. Retain until
      // sign-out, next cold launch, or the next export after 24 hours.
      retained = true;
    } finally {
      if (!retained && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  Future<void> clear() {
    cancelPending();
    final operation = _operation;
    return _cleanup = _cleanup.catchError((Object _) {}).then((_) async {
      await _channel.invokeMethod<void>('dismiss');
      try {
        await operation;
      } on ApiException {
        // Cancellation is expected when the paired identity changes.
      } on FileSystemException {
        // Cleanup still removes any remaining completed exports.
      } on PlatformException {
        // A failed handoff does not prevent removing local files.
      }
      await _removeExpired(all: true);
    });
  }

  void cancelPending() {
    _generation++;
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  Future<void> _removeExpired({bool all = false}) async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory ||
          !path.basename(entry.path).startsWith('document-')) {
        continue;
      }
      if (all || (await entry.stat()).modified.isBefore(cutoff)) {
        await entry.delete(recursive: true);
      }
    }
  }

  static String extensionForMimeType(String mimeType) => switch (mimeType) {
    'application/pdf' => '.pdf',
    'image/jpeg' => '.jpg',
    'image/png' => '.png',
    'image/webp' => '.webp',
    'image/heic' || 'image/heif' => '.heic',
    'image/tiff' => '.tiff',
    'text/plain' => '.txt',
    'text/csv' => '.csv',
    'text/html' => '.html',
    'message/rfc822' => '.eml',
    'application/rtf' || 'text/rtf' => '.rtf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
      '.docx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' =>
      '.xlsx',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
      '.pptx',
    'application/msword' => '.doc',
    _ => '.bin',
  };
}
