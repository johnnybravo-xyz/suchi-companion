import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/documents/thumbnail_cache.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _origin = Uri.parse('https://suchi.example.com');

void main() {
  test('evicts least-recently-used images at the entry bound', () async {
    final counts = <int, int>{};
    final client = SuchiClient(
      origin: _origin,
      token: _token,
      httpClient: MockClient((request) async {
        final id = int.parse(request.url.pathSegments[2]);
        counts[id] = (counts[id] ?? 0) + 1;
        return http.Response.bytes(
          [id, id + 1],
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    final cache = ThumbnailMemoryCache(maximumEntries: 2, maximumBytes: 32);

    await cache.load(client, 1);
    await cache.load(client, 2);
    await cache.load(client, 1);
    await cache.load(client, 3);
    await cache.load(client, 2);

    expect(counts, {1: 1, 2: 2, 3: 1});
    expect(cache.entryCount, 2);
    expect(cache.byteCount, 4);
  });

  test(
    'clear prevents an in-flight image from entering a new session cache',
    () async {
      final firstResponse = Completer<http.Response>();
      var requests = 0;
      final client = SuchiClient(
        origin: _origin,
        token: _token,
        httpClient: MockClient((request) async {
          requests++;
          if (requests == 1) return firstResponse.future;
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      final cache = ThumbnailMemoryCache();

      final oldRequest = cache.load(client, 7);
      cache.clear();
      firstResponse.complete(
        http.Response.bytes(
          [9, 9, 9],
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      await oldRequest;
      expect(cache.entryCount, 0);

      await cache.load(client, 7);
      expect(requests, 2);
      expect(cache.entryCount, 1);
    },
  );

  test('revealed restricted bytes are never retained', () async {
    final firstResponse = Completer<http.Response>();
    var requests = 0;
    final client = SuchiClient(
      origin: _origin,
      token: _token,
      httpClient: MockClient((request) async {
        requests++;
        if (requests == 1) return firstResponse.future;
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    final cache = ThumbnailMemoryCache();

    final hiddenRequest = cache.load(client, 7, reveal: true);
    cache.evict(7, reveal: true);
    firstResponse.complete(
      http.Response.bytes(
        [9, 9, 9],
        200,
        headers: {'content-type': 'image/png'},
      ),
    );
    await hiddenRequest;

    expect(cache.entryCount, 0);
    await cache.load(client, 7, reveal: true);
    expect(requests, 2);
    expect(cache.entryCount, 0);
  });
}
