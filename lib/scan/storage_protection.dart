import 'package:flutter/services.dart';

abstract interface class StorageProtection {
  Future<void> protectDirectory(String absolutePath);
}

const minimumFreeStorageReserveBytes = 512 * 1024 * 1024;

final class StorageCapacityException implements Exception {
  const StorageCapacityException();

  static const message =
      'Free at least 512 MiB of device storage before saving more documents.';

  @override
  String toString() => message;
}

abstract interface class StorageCapacity {
  Future<int> availableBytes(String absolutePath);
}

final class NativeStorageCapacity implements StorageCapacity {
  const NativeStorageCapacity({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('page.suchi.companion/storage');

  final MethodChannel _channel;

  @override
  Future<int> availableBytes(String absolutePath) async {
    if (absolutePath.isEmpty) {
      throw const FormatException('Storage path cannot be empty.');
    }
    final available = await _channel.invokeMethod<int>('availableBytes', {
      'path': absolutePath,
    });
    if (available == null || available < 0) {
      throw const FormatException('Available storage is invalid.');
    }
    return available;
  }
}

Future<void> ensureWritableStorage({
  required StorageCapacity capacity,
  required String path,
  required int byteCount,
}) async {
  if (byteCount < 0) {
    throw const FormatException('Write size cannot be negative.');
  }
  final available = await capacity.availableBytes(path);
  if (available - byteCount < minimumFreeStorageReserveBytes) {
    throw const StorageCapacityException();
  }
}

final class NativeStorageProtection implements StorageProtection {
  const NativeStorageProtection({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('page.suchi.companion/storage');

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
