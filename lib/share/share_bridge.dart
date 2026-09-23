import 'dart:async';

import 'package:flutter/services.dart';

const shareChannelName = 'app.suchi.page/share';
const maxSharedItems = 20;

final RegExp _batchIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
const supportedShareMimeTypes = {
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/heic',
  'image/heif',
};

class SharedItem {
  const SharedItem({
    required this.index,
    required this.path,
    required this.mime,
    required this.name,
    required this.size,
    required this.sha256,
  });

  final int index;
  final String path;
  final String mime;
  final String name;
  final int size;
  final String sha256;
}

class SharedBatch {
  const SharedBatch({
    required this.id,
    required this.createdAt,
    required this.items,
    required this.rejectedCount,
    required this.complete,
  });

  final String id;
  final DateTime createdAt;
  final List<SharedItem> items;
  final int rejectedCount;
  final bool complete;
}

class ShareFailure implements Exception {
  const ShareFailure({
    required this.code,
    required this.message,
    required this.retryable,
  });

  final String code;
  final String message;
  final bool retryable;

  @override
  String toString() => message;
}

abstract interface class ShareIntake {
  Stream<void> get events;

  Future<List<SharedBatch>> pending();
  Future<String?> pick(String source, String batchId);

  Future<void> discard(String batchId);
}

class ShareBridge implements ShareIntake {
  ShareBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(shareChannelName) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;
  final StreamController<void> _events = StreamController<void>.broadcast();
  bool _closed = false;

  @override
  Stream<void> get events => _events.stream;

  @override
  Future<List<SharedBatch>> pending() async {
    try {
      final response = await _channel.invokeListMethod<Object?>('pending');
      if (response == null) {
        throw const FormatException('Share intake returned no batches.');
      }
      return response.map(_parseBatch).toList(growable: false)
        ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    } on PlatformException catch (error) {
      throw _failure(error);
    } on MissingPluginException {
      throw const ShareFailure(
        code: 'share_unavailable',
        message: 'Share intake is unavailable.',
        retryable: false,
      );
    }
  }

  @override
  Future<String?> pick(String source, String batchId) async {
    if ((source != 'files' && source != 'photos') ||
        !_batchIdPattern.hasMatch(batchId)) {
      throw const FormatException('Share picker request is invalid.');
    }
    try {
      final result = await _channel.invokeMethod<Object?>('pick', {
        'source': source,
        'batch_id': batchId,
      });
      if (result == null) return null;
      if (result != batchId) {
        throw const FormatException('Share picker returned an invalid batch.');
      }
      return batchId;
    } on PlatformException catch (error) {
      throw _failure(error);
    } on MissingPluginException {
      throw const ShareFailure(
        code: 'share_unavailable',
        message: 'Share intake is unavailable.',
        retryable: false,
      );
    }
  }

  @override
  Future<void> discard(String batchId) async {
    if (!_batchIdPattern.hasMatch(batchId)) {
      throw const FormatException('Share batch id is invalid.');
    }
    try {
      await _channel.invokeMethod<void>('discard', {'batch_id': batchId});
    } on PlatformException catch (error) {
      throw _failure(error);
    } on MissingPluginException {
      throw const ShareFailure(
        code: 'share_unavailable',
        message: 'Share intake is unavailable.',
        retryable: false,
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _channel.setMethodCallHandler(null);
    await _events.close();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'shareEvent') {
      throw MissingPluginException('Unknown share method ${call.method}.');
    }
    _events.add(null);
  }

  SharedBatch _parseBatch(Object? value) {
    if (value is! Map) {
      throw const FormatException('Share intake returned an invalid batch.');
    }
    final id = value['batch_id'];
    final createdAt = value['created_at'];
    final rawItems = value['items'];
    final rejectedCount = value['rejected_count'];
    final complete = value['complete'];
    if (id is! String ||
        !_batchIdPattern.hasMatch(id) ||
        createdAt is! int ||
        createdAt <= 0 ||
        rawItems is! List ||
        rawItems.length > maxSharedItems ||
        rejectedCount is! int ||
        rejectedCount < 0 ||
        complete is! bool) {
      throw const FormatException('Share intake returned invalid metadata.');
    }

    var previousIndex = -1;
    final items = rawItems
        .map((rawItem) {
          if (rawItem is! Map) {
            throw const FormatException(
              'Share intake returned an invalid item.',
            );
          }
          final index = rawItem['index'];
          final path = rawItem['path'];
          final mime = rawItem['mime'];
          final name = rawItem['name'];
          final size = rawItem['size'];
          final sha256 = rawItem['sha256'];
          if (index is! int ||
              index <= previousIndex ||
              path is! String ||
              path.isEmpty ||
              mime is! String ||
              !supportedShareMimeTypes.contains(mime) ||
              name is! String ||
              name.isEmpty ||
              size is! int ||
              size < 0 ||
              sha256 is! String ||
              !_sha256Pattern.hasMatch(sha256)) {
            throw const FormatException(
              'Share intake returned invalid item metadata.',
            );
          }
          previousIndex = index;
          return SharedItem(
            index: index,
            path: path,
            mime: mime,
            name: name,
            size: size,
            sha256: sha256,
          );
        })
        .toList(growable: false);

    return SharedBatch(
      id: id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true),
      items: items,
      rejectedCount: rejectedCount,
      complete: complete,
    );
  }

  ShareFailure _failure(PlatformException error) {
    final details = error.details;
    return ShareFailure(
      code: error.code,
      message: error.message ?? 'Share intake failed.',
      retryable: details is Map && details['retryable'] == true,
    );
  }
}
