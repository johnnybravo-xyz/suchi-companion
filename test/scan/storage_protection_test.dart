import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_companion/scan/storage_protection.dart';

void main() {
  test('write preserves the 512 MiB free-space reserve', () async {
    final capacity = _FixedCapacity(minimumFreeStorageReserveBytes + 1024);

    await ensureWritableStorage(
      capacity: capacity,
      path: '/private/storage',
      byteCount: 1024,
    );
    await expectLater(
      ensureWritableStorage(
        capacity: capacity,
        path: '/private/storage',
        byteCount: 1025,
      ),
      throwsA(isA<StorageCapacityException>()),
    );
  });

  test('negative write sizes are rejected before querying storage', () async {
    final capacity = _FixedCapacity(minimumFreeStorageReserveBytes);

    await expectLater(
      ensureWritableStorage(
        capacity: capacity,
        path: '/private/storage',
        byteCount: -1,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(capacity.queries, 0);
  });
}

final class _FixedCapacity implements StorageCapacity {
  _FixedCapacity(this.bytes);

  final int bytes;
  int queries = 0;

  @override
  Future<int> availableBytes(String absolutePath) async {
    queries++;
    return bytes;
  }
}
