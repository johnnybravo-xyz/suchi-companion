import 'dart:collection';

import '../api/suchi_client.dart';

final class ThumbnailMemoryCache {
  ThumbnailMemoryCache({
    this.maximumEntries = 100,
    this.maximumBytes = 32 * 1024 * 1024,
  });

  final int maximumEntries;
  final int maximumBytes;
  final LinkedHashMap<_ThumbnailKey, ThumbnailImage> _images =
      LinkedHashMap<_ThumbnailKey, ThumbnailImage>();
  int _generation = 0;
  final Map<_ThumbnailKey, Future<ThumbnailResult>> _pending = {};
  int _byteCount = 0;

  int get entryCount => _images.length;
  int get byteCount => _byteCount;

  Future<ThumbnailResult> load(
    SuchiClient client,
    int documentId, {
    int width = 160,
    bool reveal = false,
  }) {
    final key = _ThumbnailKey(documentId, width, reveal);
    final cached = _images.remove(key);
    if (cached != null) {
      _images[key] = cached;
      return Future.value(cached);
    }
    final existing = _pending[key];
    if (existing != null) return existing;
    final generation = _generation;
    late final Future<ThumbnailResult> request;
    request = client
        .thumbnail(documentId, width: width, reveal: reveal)
        .then((result) {
          if (!reveal && generation == _generation) {
            if (result case final ThumbnailImage image) {
              _insert(key, image);
            }
          }
          return result;
        })
        .whenComplete(() {
          if (_pending[key] == request) _pending.remove(key);
        });
    _pending[key] = request;
    return request;
  }

  void evict(int documentId, {bool? reveal}) {
    _pending.removeWhere(
      (key, _) =>
          key.documentId == documentId &&
          (reveal == null || key.reveal == reveal),
    );
    final keys = _images.keys
        .where(
          (key) =>
              key.documentId == documentId &&
              (reveal == null || key.reveal == reveal),
        )
        .toList(growable: false);
    for (final key in keys) {
      final removed = _images.remove(key);
      if (removed != null) _byteCount -= removed.bytes.length;
    }
  }

  void clear() {
    _generation++;
    _images.clear();
    _pending.clear();
    _byteCount = 0;
  }

  void _insert(_ThumbnailKey key, ThumbnailImage image) {
    final replaced = _images.remove(key);
    if (replaced != null) _byteCount -= replaced.bytes.length;
    if (image.bytes.length > maximumBytes) return;
    _images[key] = image;
    _byteCount += image.bytes.length;
    while (_images.length > maximumEntries || _byteCount > maximumBytes) {
      final oldest = _images.keys.first;
      final removed = _images.remove(oldest)!;
      _byteCount -= removed.bytes.length;
    }
  }
}

final class _ThumbnailKey {
  const _ThumbnailKey(this.documentId, this.width, this.reveal);

  final int documentId;
  final int width;
  final bool reveal;

  @override
  bool operator ==(Object other) =>
      other is _ThumbnailKey &&
      other.documentId == documentId &&
      other.width == width &&
      other.reveal == reveal;

  @override
  int get hashCode => Object.hash(documentId, width, reveal);
}
