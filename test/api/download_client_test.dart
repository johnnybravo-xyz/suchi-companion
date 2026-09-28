import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_companion/api/api_error.dart';
import 'package:suchi_companion/api/suchi_client.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late Directory directory;
  late File destination;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('suchi-download-test-');
    destination = File('${directory.path}/document.part');
  });

  tearDown(() async => directory.delete(recursive: true));

  SuchiClient client(http.Client transport) => SuchiClient(
    origin: Uri.parse('https://suchi.example.com'),
    token: _token,
    httpClient: transport,
  );

  test('streams authenticated archive bytes without a token URL', () async {
    final api = client(
      MockClient((request) async {
        expect(
          request.url.toString(),
          'https://suchi.example.com/api/documents/91/download',
        );
        expect(request.headers['Authorization'], 'Token $_token');
        expect(request.followRedirects, false);
        return http.Response(
          '%PDF-test',
          200,
          headers: {'content-type': 'application/pdf; charset=binary'},
        );
      }),
    );

    final download = await api.downloadDocument(91, destination: destination);
    expect(download.mimeType, 'application/pdf');
    expect(download.byteSize, 9);
    expect(
      download.sha256,
      sha256.convert(utf8.encode('%PDF-test')).toString(),
    );
    expect(await destination.readAsString(), '%PDF-test');
  });

  test('reports bytes only after writing each streamed chunk', () async {
    final chunks = StreamController<List<int>>();
    final firstWritten = Completer<void>();
    final progress = <int>[];
    final api = client(
      _StreamClient(
        () => http.StreamedResponse(
          chunks.stream,
          200,
          contentLength: 6,
          headers: {'content-type': 'application/pdf'},
        ),
      ),
    );

    final download = api.downloadDocument(
      91,
      destination: destination,
      onProgress: (bytes) {
        progress.add(bytes);
        if (bytes == 3) firstWritten.complete();
      },
    );
    chunks.add([1, 2, 3]);
    await firstWritten.future;
    expect(await destination.length(), 3);
    expect(progress, [3]);

    chunks.add([4, 5, 6]);
    await chunks.close();
    expect((await download).mimeType, 'application/pdf');
    expect(progress, [3, 6]);
    expect(await destination.readAsBytes(), [1, 2, 3, 4, 5, 6]);
  });

  test('preview requires an explicit reveal query', () async {
    final api = client(
      MockClient((request) async {
        expect(request.url.path, '/api/documents/91/preview');
        expect(request.url.queryParameters, {'reveal': '1'});
        return http.Response(
          '%PDF-test',
          200,
          headers: {'content-type': 'application/pdf'},
        );
      }),
    );

    await api.downloadDocument(
      91,
      destination: destination,
      preview: true,
      reveal: true,
    );
  });

  test('redirects and sensitive gates never create an export file', () async {
    for (final status in [302, 202, 401]) {
      final api = client(
        MockClient(
          (_) async => http.Response(
            '{"gated":true}',
            status,
            headers: {
              'content-type': 'application/json',
              'location': 'https://elsewhere.example/file',
            },
          ),
        ),
      );
      await expectLater(
        api.downloadDocument(91, destination: destination),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            switch (status) {
              302 => ApiFailureKind.redirect,
              401 => ApiFailureKind.unauthorized,
              _ => ApiFailureKind.rejected,
            },
          ),
        ),
      );
      expect(await destination.exists(), false);
    }
  });

  test('refuses oversized declared responses before writing', () async {
    final api = client(
      _StreamClient(
        () => http.StreamedResponse(
          const Stream.empty(),
          200,
          contentLength: 64 * 1024 * 1024 + 1,
          headers: {'content-type': 'application/pdf'},
        ),
      ),
    );
    await expectLater(
      api.downloadDocument(91, destination: destination),
      throwsA(isA<ApiException>()),
    );
    expect(await destination.exists(), false);
  });

  test('removes partial files after an interrupted response', () async {
    final api = client(
      _StreamClient(
        () => http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            [1, 2, 3],
          ]),
          200,
          contentLength: 10,
          headers: {'content-type': 'application/pdf'},
        ),
      ),
    );
    await expectLater(
      api.downloadDocument(91, destination: destination),
      throwsA(isA<ApiException>()),
    );
    expect(await destination.exists(), false);
  });

  test('cancellation removes bytes already downloaded', () async {
    final abort = Completer<void>();
    Stream<List<int>> chunks() async* {
      yield [1, 2, 3];
      abort.complete();
      yield [4, 5];
    }

    final api = client(
      _StreamClient(
        () => http.StreamedResponse(
          chunks(),
          200,
          headers: {'content-type': 'application/pdf'},
        ),
      ),
    );
    await expectLater(
      api.downloadDocument(
        91,
        destination: destination,
        abortTrigger: abort.future,
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.cancelled,
        ),
      ),
    );
    expect(await destination.exists(), false);
  });

  test('never overwrites an existing destination', () async {
    await destination.writeAsString('keep');
    final api = client(MockClient((_) async => throw StateError('unexpected')));
    await expectLater(
      api.downloadDocument(91, destination: destination),
      throwsA(isA<ApiException>()),
    );
    expect(await destination.readAsString(), 'keep');
  });
}

final class _StreamClient extends http.BaseClient {
  _StreamClient(this.response);

  final http.StreamedResponse Function() response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      response();
}
