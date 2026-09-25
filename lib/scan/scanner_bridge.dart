import 'package:flutter/services.dart';

const scannerChannelName = 'page.suchi.companion/scan';

enum CaptureMode { scanner, photo }

class CapturedPage {
  const CapturedPage({required this.path});

  final String path;
}

class CaptureResult {
  const CaptureResult({
    required this.cancelled,
    required this.pageCount,
    required this.pages,
    this.pdfPath,
  });

  final bool cancelled;
  final int pageCount;
  final List<CapturedPage> pages;
  final String? pdfPath;
}

class RecognizedPage {
  const RecognizedPage({
    required this.path,
    required this.text,
    this.confidence,
    this.language,
    this.errorCode,
  });

  final String path;
  final String text;
  final double? confidence;
  final String? language;
  final String? errorCode;
}

class ScannerFailure implements Exception {
  const ScannerFailure({
    required this.code,
    required this.message,
    required this.retryable,
    this.openSettings = false,
  });

  final String code;
  final String message;
  final bool retryable;
  final bool openSettings;

  @override
  String toString() => message;
}

abstract interface class DocumentScanner {
  Future<CaptureResult> capture({CaptureMode mode = CaptureMode.scanner});

  Future<List<RecognizedPage>> recognizeText(List<String> paths);

  Future<void> openSettings();

  Future<void> discardCapture(CaptureResult capture);
}

class ScannerBridge implements DocumentScanner {
  ScannerBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(scannerChannelName);

  final MethodChannel _channel;

  @override
  Future<CaptureResult> capture({
    CaptureMode mode = CaptureMode.scanner,
  }) async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'capture',
        {'mode': mode.name},
      );
      if (response == null) {
        throw const FormatException('Scanner returned no capture result.');
      }
      final cancelled = response['cancelled'];
      final pageCount = response['page_count'];
      final rawPages = response['pages'];
      if (cancelled is! bool || pageCount is! int || rawPages is! List) {
        throw const FormatException(
          'Scanner returned an invalid capture result.',
        );
      }
      final pages = rawPages
          .map((rawPage) {
            if (rawPage is! Map || rawPage['path'] is! String) {
              throw const FormatException('Scanner returned an invalid page.');
            }
            final path = rawPage['path'] as String;
            if (path.isEmpty) {
              throw const FormatException(
                'Scanner returned an empty page path.',
              );
            }
            return CapturedPage(path: path);
          })
          .toList(growable: false);
      final rawPdfPath = response['pdf_path'];
      if (rawPdfPath != null && rawPdfPath is! String) {
        throw const FormatException('Scanner returned an invalid PDF path.');
      }
      final pdfPath = rawPdfPath as String?;
      if (pageCount < 0 || pages.length > pageCount) {
        throw const FormatException('Scanner returned an invalid page count.');
      }
      if (!cancelled && pageCount == 0) {
        throw const FormatException('Scanner returned an empty capture.');
      }
      if (!cancelled && pages.isEmpty && (pdfPath == null || pdfPath.isEmpty)) {
        throw const FormatException('Scanner returned no readable files.');
      }
      return CaptureResult(
        cancelled: cancelled,
        pageCount: pageCount,
        pages: pages,
        pdfPath: pdfPath,
      );
    } on PlatformException catch (error) {
      throw ScannerFailure(
        code: error.code,
        message: error.message ?? 'The document scanner failed.',
        retryable: _isRetryable(error.details),
        openSettings: _canOpenSettings(error.details),
      );
    }
  }

  @override
  Future<List<RecognizedPage>> recognizeText(List<String> paths) async {
    if (paths.isEmpty) {
      return const [];
    }
    try {
      final response = await _channel.invokeListMethod<Object?>(
        'recognizeText',
        {'paths': paths},
      );
      if (response == null || response.length != paths.length) {
        throw const FormatException('OCR returned an invalid page count.');
      }
      return List<RecognizedPage>.generate(paths.length, (index) {
        final rawPage = response[index];
        if (rawPage is! Map ||
            rawPage['path'] != paths[index] ||
            rawPage['text'] is! String) {
          throw const FormatException('OCR returned pages out of order.');
        }
        final rawConfidence = rawPage['confidence'];
        if (rawConfidence != null && rawConfidence is! num) {
          throw const FormatException('OCR returned an invalid confidence.');
        }
        return RecognizedPage(
          path: paths[index],
          text: rawPage['text'] as String,
          confidence: (rawConfidence as num?)?.toDouble(),
          language: rawPage['language'] as String?,
          errorCode: rawPage['error_code'] as String?,
        );
      }, growable: false);
    } on PlatformException catch (error) {
      throw ScannerFailure(
        code: error.code,
        message: error.message ?? 'Text recognition failed.',
        retryable: _isRetryable(error.details),
        openSettings: _canOpenSettings(error.details),
      );
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException catch (error) {
      throw ScannerFailure(
        code: error.code,
        message: error.message ?? 'Settings could not be opened.',
        retryable: _isRetryable(error.details),
      );
    }
  }

  @override
  Future<void> discardCapture(CaptureResult capture) async {
    final paths = <String>[
      ...capture.pages.map((page) => page.path),
      ?capture.pdfPath,
    ];
    if (paths.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('discardCapture', {'paths': paths});
    } on PlatformException catch (error) {
      throw ScannerFailure(
        code: error.code,
        message: error.message ?? 'Scan cleanup failed.',
        retryable: _isRetryable(error.details),
      );
    }
  }

  bool _canOpenSettings(Object? details) {
    return details is Map && details['open_settings'] == true;
  }

  bool _isRetryable(Object? details) {
    return details is Map && details['retryable'] == true;
  }
}
