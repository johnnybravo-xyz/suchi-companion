import 'package:flutter/services.dart';

abstract interface class StorageProtection {
  Future<void> protectDirectory(String absolutePath);
}

final class NativeStorageProtection implements StorageProtection {
  const NativeStorageProtection({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.suchi.page/storage');

  final MethodChannel _channel;

  @override
  Future<void> protectDirectory(String absolutePath) async {
    if (absolutePath.isEmpty) {
      throw const FormatException('Storage path cannot be empty.');
    }
    await _channel.invokeMethod<void>('protectDirectory', {
      'path': absolutePath,
    });
  }
}
