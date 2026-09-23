import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_mobile/share/share_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('share-bridge-test');
  late ShareBridge bridge;

  setUp(() {
    bridge = ShareBridge(channel: channel);
  });

  tearDown(() async {
    await bridge.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('pending parses batches and preserves native item order', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'pending');
          return <Object?>[
            {
              'batch_id': 'c4652f32-b979-4fc0-adbe-1d761beb2209',
              'created_at': 2000,
              'rejected_count': 1,
              'complete': true,
              'items': [
                {
                  'index': 0,
                  'path': '/incoming/first.pdf',
                  'mime': 'application/pdf',
                  'name': 'first.pdf',
                  'size': 12,
                  'sha256': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                },
                {
                  'index': 2,
                  'path': '/incoming/second.png',
                  'mime': 'image/png',
                  'name': 'second.png',
                  'size': 34,
                  'sha256': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                },
              ],
            },
            {
              'batch_id': 'eb85ada3-235c-49f7-9939-2851d411e614',
              'created_at': 1000,
              'rejected_count': 0,
              'complete': false,
              'items': <Object?>[],
            },
          ];
        });

    final batches = await bridge.pending();

    expect(batches.map((batch) => batch.id), [
      'eb85ada3-235c-49f7-9939-2851d411e614',
      'c4652f32-b979-4fc0-adbe-1d761beb2209',
    ]);
    expect(batches.last.items.map((item) => item.index), [0, 2]);
    expect(batches.last.rejectedCount, 1);
    expect(batches.first.complete, isFalse);
  });

  test('pending accepts an OS share with more than twenty inputs', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => [
            {
              'batch_id': 'c4652f32-b979-4fc0-adbe-1d761beb2209',
              'created_at': 2000,
              'rejected_count': 21,
              'complete': true,
              'items': [
                {
                  'index': 19,
                  'path': '/incoming/last.pdf',
                  'mime': 'application/pdf',
                  'name': 'last.pdf',
                  'size': 12,
                  'sha256': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                },
              ],
            },
          ],
        );

    final batch = (await bridge.pending()).single;
    expect(batch.items.single.index, 19);
    expect(batch.rejectedCount, 21);
  });

  test('pending rejects reordered native items', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <Object?>[
            {
              'batch_id': 'c4652f32-b979-4fc0-adbe-1d761beb2209',
              'created_at': 2000,
              'rejected_count': 0,
              'complete': true,
              'items': [
                {
                  'index': 2,
                  'path': '/incoming/second.png',
                  'mime': 'image/png',
                  'name': 'second.png',
                  'size': 34,
                  'sha256': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                },
                {
                  'index': 1,
                  'path': '/incoming/first.png',
                  'mime': 'image/png',
                  'name': 'first.png',
                  'size': 12,
                  'sha256': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                },
              ],
            },
          ];
        });

    await expectLater(bridge.pending(), throwsA(isA<FormatException>()));
  });

  test('discard sends the stable batch receipt', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'discard');
          expect(call.arguments, {
            'batch_id': 'c4652f32-b979-4fc0-adbe-1d761beb2209',
          });
          return null;
        });

    await bridge.discard('c4652f32-b979-4fc0-adbe-1d761beb2209');
  });

  test(
    'picker sends source and batch id and rejects mismatched receipts',
    () async {
      const id = 'c4652f32-b979-4fc0-adbe-1d761beb2209';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'pick');
            expect(call.arguments, {'source': 'photos', 'batch_id': id});
            return id;
          });
      expect(await bridge.pick('photos', id), id);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => 'eb85ada3-235c-49f7-9939-2851d411e614',
          );
      await expectLater(bridge.pick('photos', id), throwsFormatException);
      await expectLater(bridge.pick('camera', id), throwsFormatException);
    },
  );

  test('picker cancellation returns null without a batch', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.arguments['source'], 'files');
          return null;
        });
    expect(
      await bridge.pick('files', 'c4652f32-b979-4fc0-adbe-1d761beb2209'),
      isNull,
    );
  });

  test('shareEvent notifies a warm harness', () async {
    final event = bridge.events.first;

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('shareEvent'),
          ),
          (_) {},
        );

    await event;
  });
}
