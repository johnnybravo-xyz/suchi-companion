import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:suchi_mobile/auth/account_identity.dart';
import 'package:suchi_mobile/scan/intake_limits.dart';
import 'package:suchi_mobile/scan/scan_database.dart';
import 'package:suchi_mobile/scan/scan_queue_store.dart';
import 'package:suchi_mobile/scan/storage_protection.dart';
import 'package:suchi_mobile/share/share_bridge.dart';
import 'package:suchi_mobile/share/share_import_controller.dart';

const _batchId = '33333333-3333-4333-8333-333333333333';
const _pdf = <int>[0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34, 0x0a];
final _origin = Uri.parse('https://suchi.example.com');

void main() {
  late Directory temporary;
  late ScanDatabase database;
  late ScanQueueStore queue;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('suchi-share-import-');
    database = ScanDatabase(NativeDatabase.memory());
    queue = await ScanQueueStore.open(
      database: database,
      root: Directory(path.join(temporary.path, 'queue')),
      storageProtection: _NoopProtection(),
      storageCapacity: _NoopProtection(),
    );
  });

  tearDown(() async {
    await queue.close();
    await database.close();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('discards native batch only after every item is durable', () async {
    final first = await _item(temporary, 0, 'first.pdf', _pdf);
    final second = await _item(temporary, 1, 'second.pdf', _pdf);
    final intake = _FakeIntake([
      _batch([first, second], rejected: 1),
    ]);
    intake.onDiscard = (_) async {
      expect(await database.shareReceipt(_batchId, first.index), isNotNull);
      expect(await database.shareReceipt(_batchId, second.index), isNotNull);
      final durable = await database.allUploads();
      expect(durable, hasLength(2));
      for (final upload in durable) {
        expect(await queue.payloadFile(upload).readAsBytes(), _pdf);
      }
    };
    final controller = ShareImportController(
      intake: intake,
      queue: queue,
      currentIdentity: () =>
          AccountIdentity(origin: _origin, userId: 7, systemId: 1),
    );

    final summary = await controller.processPending();

    expect(summary.staged, 2);
    expect(summary.rejected, 1);
    expect(summary.failed, 0);
    expect(intake.discarded, [_batchId]);
    final uploads = await database.allUploads();
    expect(uploads, hasLength(2));
    expect(uploads.every((upload) => upload.state == 'queued'), isTrue);
    expect(await database.shareReceipt(_batchId, first.index), isNotNull);
    expect(await database.shareReceipt(_batchId, second.index), isNotNull);
  });

  test('snapshots one identity for every item in a share batch', () async {
    final first = await _item(temporary, 0, 'first.pdf', _pdf);
    final second = await _item(temporary, 1, 'second.pdf', _pdf);
    final intake = _FakeIntake([
      _batch([first, second]),
    ]);
    var identityReads = 0;
    final controller = ShareImportController(
      intake: intake,
      queue: queue,
      currentIdentity: () {
        identityReads++;
        return AccountIdentity(
          origin: _origin,
          userId: identityReads == 1 ? 7 : 8,
          systemId: 1,
        );
      },
    );

    await controller.processPending();

    final uploads = await database.allUploads();
    expect(uploads.map((upload) => upload.identityUserId), everyElement(7));
  });

  test(
    'terminally rejects a shared item whose declared MIME is false',
    () async {
      final good = await _item(temporary, 0, 'good.pdf', _pdf);
      final badBytes = <int>[0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0];
      final bad = await _item(
        temporary,
        1,
        'bad.pdf',
        badBytes,
        declaredMime: 'application/pdf',
      );
      final intake = _FakeIntake([
        _batch([good, bad]),
      ]);
      final controller = ShareImportController(
        intake: intake,
        queue: queue,
        currentIdentity: () => null,
      );

      final summary = await controller.processPending();

      expect(summary.staged, 1);
      expect(summary.rejected, 1);
      expect(summary.failed, 0);
      expect(intake.discarded, [_batchId]);
      final uploads = await database.allUploads();
      expect(uploads.single.state, 'unassigned');
      expect(await database.shareReceipt(_batchId, 0), isNotNull);
      final receipt = await database.shareReceipt(_batchId, 1);
      expect(receipt?.status, 'rejected');
      expect(receipt?.errorCode, 'mime_mismatch');
    },
  );

  test('a cleanup retry does not duplicate an already staged item', () async {
    final item = await _item(temporary, 0, 'receipt.pdf', _pdf);
    final intake = _FakeIntake([
      _batch([item]),
    ], discardFailures: 1);
    final controller = ShareImportController(
      intake: intake,
      queue: queue,
      currentIdentity: () => null,
    );

    final first = await controller.processPending();
    final retryPhases = <ShareImportPhase>[];
    controller.addListener(() => retryPhases.add(controller.phase));
    final second = await controller.processPending();
    expect(retryPhases, isNot(contains(ShareImportPhase.staging)));

    expect(first.staged, 1);
    expect(second.staged, 0);
    expect(second.alreadyStaged, 1);
    expect(await database.allUploads(), hasLength(1));
    expect(intake.discarded, [_batchId]);
  });

  test('records an oversized shared item as a terminal rejection', () async {
    final item = await _item(
      temporary,
      0,
      'oversized.pdf',
      _pdf,
      declaredSize: maximumDocumentBytes + 1,
    );
    final intake = _FakeIntake([
      _batch([item]),
    ]);
    final controller = ShareImportController(
      intake: intake,
      queue: queue,
      currentIdentity: () => null,
    );

    final summary = await controller.processPending();

    expect(summary.staged, 0);
    expect(summary.rejected, 1);
    expect(summary.failed, 0);
    expect(intake.discarded, [_batchId]);
    expect(await database.allUploads(), isEmpty);
    final receipt = await database.shareReceipt(_batchId, item.index);
    expect(receipt?.status, 'rejected');
    expect(receipt?.errorCode, 'payload_too_large');
  });

  test('skips an incomplete native manifest', () async {
    final item = await _item(temporary, 0, 'incomplete.pdf', _pdf);
    final intake = _FakeIntake([
      _batch([item], complete: false),
    ]);
    final controller = ShareImportController(
      intake: intake,
      queue: queue,
      currentIdentity: () => null,
    );

    final phases = <ShareImportPhase>[];
    controller.addListener(() => phases.add(controller.phase));
    final summary = await controller.processPending();

    expect(summary.staged, 0);
    expect(await database.allUploads(), isEmpty);
    expect(intake.discarded, isEmpty);
    expect(phases, isNot(contains(ShareImportPhase.staging)));
  });

  test(
    'checking is observable and reentrant calls await the whole drain',
    () async {
      final item = await _item(temporary, 0, 'delayed.pdf', _pdf);
      final firstPending = Completer<List<SharedBatch>>();
      final followUpPending = Completer<List<SharedBatch>>();
      final followUpEntered = Completer<void>();
      final intake = _FakeIntake([]);
      intake.onPending = () {
        if (intake.pendingCalls == 1) return firstPending.future;
        followUpEntered.complete();
        return followUpPending.future;
      };
      final controller = ShareImportController(
        intake: intake,
        queue: queue,
        currentIdentity: () =>
            AccountIdentity(origin: _origin, userId: 7, systemId: 1),
      );
      addTearDown(controller.close);
      addTearDown(intake.controller.close);
      Future<ShareImportSummary>? reentrant;
      final phases = <ShareImportPhase>[];
      controller.addListener(() {
        phases.add(controller.phase);
        reentrant ??= controller.processPending();
      });

      final drain = controller.processPending();
      var completed = false;
      unawaited(drain.then((_) => completed = true));
      expect(controller.phase, ShareImportPhase.checking);
      expect(phases, [ShareImportPhase.checking]);
      expect(identical(reentrant, drain), isTrue);
      expect(identical(controller.processPending(), drain), isTrue);
      expect(completed, isFalse);
      expect(await database.allUploads(), isEmpty);

      firstPending.complete([
        _batch([item]),
      ]);
      await followUpEntered.future;
      expect(phases, contains(ShareImportPhase.staging));
      expect(completed, isFalse);
      expect(controller.lastSummary?.staged, 1);
      followUpPending.complete([_batch([], rejected: 2)]);
      final result = await drain;
      expect(await reentrant, same(result));
      expect(result.staged, 0);
      expect(result.rejected, 2);
      expect(controller.lastSummary, same(result));
      expect(controller.phase, ShareImportPhase.idle);
      expect(await database.allUploads(), hasLength(1));
    },
  );

  test(
    'empty checks retain warnings and dismissal preserves durable intake',
    () async {
      final item = await _item(temporary, 0, 'retained.pdf', _pdf);
      final intake = _FakeIntake([
        _batch([item], rejected: 1),
      ], discardFailures: 1);
      final pending = Completer<List<SharedBatch>>();
      intake.onPending = () =>
          intake.pendingCalls == 1 ? pending.future : Future.value([]);
      final controller = ShareImportController(
        intake: intake,
        queue: queue,
        currentIdentity: () => null,
      );
      addTearDown(controller.close);
      addTearDown(intake.controller.close);

      final drain = controller.processPending();
      final coalesced = controller.processPending();
      pending.complete(List.of(intake.batches));
      final empty = await drain;
      expect(await coalesced, same(empty));
      final meaningful = controller.lastSummary!;
      final error = controller.errorMessage;
      expect(meaningful.staged, 1);
      expect(meaningful.rejected, 1);
      expect(error, isNotNull);
      expect(intake.pendingCalls, 2);
      expect(empty.staged, 0);
      expect(empty.rejected, 0);
      expect(controller.lastSummary, same(meaningful));
      expect(controller.errorMessage, error);
      intake.onPending = () async => [
        _batch([item], complete: false),
      ];
      await controller.processPending();
      expect(controller.lastSummary, same(meaningful));
      expect(controller.errorMessage, error);

      controller.dismissResult();
      expect(controller.lastSummary, isNull);
      expect(controller.errorMessage, isNull);
      expect(intake.discarded, isEmpty);
      expect(await File(item.path).readAsBytes(), _pdf);
      expect(await database.shareReceipt(_batchId, 0), isNotNull);
      final upload = (await database.allUploads()).single;
      expect(await queue.payloadFile(upload).readAsBytes(), _pdf);
    },
  );

  for (final transition in [
    (
      label: 'another account',
      before: AccountIdentity(origin: _origin, userId: 7, systemId: 1),
      after: AccountIdentity(origin: _origin, userId: 8, systemId: 1),
    ),
    (
      label: 'pairing from signed out',
      before: null,
      after: AccountIdentity(origin: _origin, userId: 7, systemId: 1),
    ),
    (
      label: 'the same user on another origin',
      before: AccountIdentity(origin: _origin, userId: 7, systemId: 1),
      after: AccountIdentity(
        origin: Uri.parse('https://other.example.com'),
        userId: 7,
        systemId: 1,
      ),
    ),
    (
      label: 'the same account in another filing system',
      before: AccountIdentity(origin: _origin, userId: 7, systemId: 1),
      after: AccountIdentity(origin: _origin, userId: 7, systemId: 2),
    ),
  ]) {
    test('pending intake stays bound across ${transition.label}', () async {
      final first = await _item(temporary, 0, 'original.pdf', _pdf);
      final second = await _item(temporary, 1, 'second-batch.pdf', _pdf);
      final pending = Completer<List<SharedBatch>>();
      final intake = _FakeIntake([]);
      intake.onPending = () => pending.future;
      AccountIdentity? identity = transition.before;
      final controller = ShareImportController(
        intake: intake,
        queue: queue,
        currentIdentity: () => identity,
      );
      addTearDown(controller.close);
      addTearDown(intake.controller.close);

      final drain = controller.processPending();
      expect(controller.phase, ShareImportPhase.checking);
      identity = transition.after;
      controller.concealForIdentityTransition();
      final latePhases = <ShareImportPhase>[];
      controller.addListener(() => latePhases.add(controller.phase));
      pending.complete([
        _batch([first], rejected: 1),
        _batch([second], id: '44444444-4444-4444-8444-444444444444'),
      ]);
      final result = await drain;
      expect(result.staged, 2);
      expect(controller.phase, ShareImportPhase.idle);
      expect(latePhases, isNot(contains(ShareImportPhase.staging)));
      expect(controller.lastSummary, isNull);
      expect(controller.errorMessage, isNull);
      final originalUploads = await database.allUploads();
      expect(originalUploads, hasLength(2));
      for (final upload in originalUploads) {
        expect(upload.identityUserId, transition.before?.userId);
        expect(upload.identityOrigin, transition.before?.origin.toString());
        expect(upload.identitySystemId, transition.before?.systemId);
        expect(
          upload.state,
          transition.before == null ? 'unassigned' : 'queued',
        );
      }

      final next = await _item(temporary, 2, 'new-account.pdf', _pdf);
      intake.onPending = () async => [
        _batch([next], id: '55555555-5555-4555-8555-555555555555'),
      ];
      await controller.processPending();
      final nextUpload = (await database.allUploads()).singleWhere(
        (upload) => upload.filename == 'new-account.pdf',
      );
      expect(nextUpload.identityUserId, transition.after.userId);
      expect(nextUpload.identityOrigin, transition.after.origin.toString());
      expect(nextUpload.identitySystemId, transition.after.systemId);
      expect(controller.lastSummary?.staged, 1);
    });
  }

  test(
    'close waits for staging and native acknowledgement without reruns',
    () async {
      final item = await _item(temporary, 0, 'closing.pdf', _pdf);
      final discardEntered = Completer<void>();
      final allowDiscard = Completer<void>();
      final intake = _FakeIntake([
        _batch([item]),
      ]);
      intake.onDiscard = (_) async {
        discardEntered.complete();
        await allowDiscard.future;
      };
      final controller = ShareImportController(
        intake: intake,
        queue: queue,
        currentIdentity: () =>
            AccountIdentity(origin: _origin, userId: 7, systemId: 1),
      );
      addTearDown(intake.controller.close);
      Future<void>? closing;
      var closed = false;
      controller.addListener(() {
        if (controller.phase == ShareImportPhase.staging && closing == null) {
          closing = controller.close();
          unawaited(closing!.then((_) => closed = true));
        }
      });

      final started = controller.start();
      await discardEntered.future;
      expect(closing, isNotNull);
      expect(closed, isFalse);
      expect(await database.shareReceipt(_batchId, 0), isNotNull);
      final concurrent = controller.processPending();
      allowDiscard.complete();
      await closing;
      await started;
      expect((await concurrent).staged, 1);
      expect(closed, isTrue);
      expect(intake.controller.hasListener, isFalse);
      expect(intake.pendingCalls, 1);
      await controller.start();
      await controller.processPending();
      expect(intake.pendingCalls, 1);
      expect(intake.discarded, [_batchId]);
      final upload = (await database.allUploads()).single;
      expect(await queue.payloadFile(upload).readAsBytes(), _pdf);
    },
  );

  test(
    'unexpected pending failures are safe and survive empty retry',
    () async {
      final intake = _FakeIntake([]);
      intake.onPending = () async {
        throw StateError('Cannot copy /private/native/secret.pdf');
      };
      final controller = ShareImportController(
        intake: intake,
        queue: queue,
        currentIdentity: () => null,
      );
      addTearDown(controller.close);
      addTearDown(intake.controller.close);
      final failure = await controller.processPending();
      expect(controller.phase, ShareImportPhase.idle);
      expect(controller.errorMessage, isNotNull);
      expect(controller.errorMessage, isNot(contains('/private/')));
      expect(controller.errorMessage, isNot(contains('secret.pdf')));
      expect(intake.discarded, isEmpty);
      intake.onPending = () async => [];
      await controller.processPending();
      expect(controller.lastSummary, same(failure));
      expect(controller.errorMessage, isNotNull);
    },
  );
  test(
    'Files and Photos stage into the same account queue with durable receipts',
    () async {
      final owner = AccountIdentity(origin: _origin, userId: 7, systemId: 1);
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final file = await _item(temporary, 0, 'file.pdf', _pdf);
      final photo = await _item(
        temporary,
        0,
        'photo.png',
        png,
        declaredMime: 'image/png',
      );
      final intake = _FakeIntake([]);
      intake.onPick = (source, id) async {
        expect(await queue.shareBatchClaim(id), owner);
        intake.batches.add(_batch([source == 'files' ? file : photo], id: id));
        return id;
      };
      intake.onDiscard = (id) async {
        expect(await queue.shareBatchClaim(id), owner);
        expect(await database.shareReceipt(id, 0), isNotNull);
        expect(
          (await database.allUploads()).where((row) => row.shareBatchId == id),
          hasLength(1),
        );
      };
      final controller = ShareImportController(
        intake: intake,
        queue: queue,
        currentIdentity: () => owner,
      );
      addTearDown(controller.close);
      addTearDown(intake.controller.close);
      await controller.pick('files');
      await controller.pick('photos');
      expect(intake.picks.map((entry) => entry.$1), ['files', 'photos']);
      for (final entry in intake.picks) {
        expect(await queue.shareBatchClaim(entry.$2), isNull);
      }
      final uploads = await database.allUploads();
      expect(uploads.map((upload) => upload.mimeType).toSet(), {
        'application/pdf',
        'image/png',
      });
      expect(uploads.every((upload) => upload.identityUserId == 7), isTrue);
      expect(uploads.every((upload) => upload.source == 'share'), isTrue);
      expect(intake.discarded, intake.picks.map((entry) => entry.$2).toList());
    },
  );

  test('cancel clears only its claim and picker is single-flight', () async {
    final owner = AccountIdentity(origin: _origin, userId: 7, systemId: 1);
    final gate = Completer<String?>();
    final intake = _FakeIntake([]);
    intake.onPick = (_, id) async {
      expect(await queue.shareBatchClaim(id), owner);
      return gate.future;
    };
    final controller = ShareImportController(
      intake: intake,
      queue: queue,
      currentIdentity: () => owner,
    );
    addTearDown(controller.close);
    addTearDown(intake.controller.close);
    final first = controller.pick('files');
    expect(identical(first, controller.pick('photos')), isTrue);
    expect(controller.isPicking, isTrue);
    while (intake.picks.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final id = intake.picks.single.$2;
    gate.complete(null);
    await first;
    expect(controller.isPicking, isFalse);
    expect(await queue.shareBatchClaim(id), isNull);
    expect(intake.picks, hasLength(1));
    expect(await database.allUploads(), isEmpty);
    expect(controller.lastSummary, isNull);
  });

  test(
    'claimed batch waits across account switch and controller restart',
    () async {
      final owner = AccountIdentity(origin: _origin, userId: 7, systemId: 1);
      final other = AccountIdentity(origin: _origin, userId: 8, systemId: 1);
      final file = await _item(temporary, 0, 'owned.pdf', _pdf);
      final intake = _FakeIntake([]);
      final gate = Completer<String?>();
      AccountIdentity? identity = owner;
      intake.onPick = (_, id) async {
        expect(await queue.shareBatchClaim(id), owner);
        intake.batches.add(_batch([file], rejected: 1, id: id));
        return gate.future;
      };
      final first = ShareImportController(
        intake: intake,
        queue: queue,
        currentIdentity: () => identity,
      );
      addTearDown(intake.controller.close);
      final pick = first.pick('files');
      while (intake.picks.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final id = intake.picks.single.$2;
      identity = other;
      first.concealForIdentityTransition();
      gate.complete(id);
      await pick;
      expect(await queue.shareBatchClaim(id), owner);
      expect(await database.allUploads(), isEmpty);
      expect(await database.shareReceipt(id, 0), isNull);
      expect(intake.discarded, isEmpty);
      expect(first.lastSummary, isNull);
      await first.close();

      final restarted = ShareImportController(
        intake: intake,
        queue: queue,
        currentIdentity: () => identity,
      );
      addTearDown(restarted.close);
      final foreign = await restarted.processPending();
      expect(foreign.staged, 0);
      expect(foreign.rejected, 0);
      expect(restarted.lastSummary, isNull);
      identity = owner;
      final imported = await restarted.processPending();
      expect(imported.staged, 1);
      expect(imported.rejected, 1);
      final upload = (await database.allUploads()).single;
      expect(queueUploadBelongsToIdentity(upload, owner), isTrue);
      expect(visibleQueueUploads([upload], other), isEmpty);
      expect(await queue.shareBatchClaim(id), isNull);
      expect(intake.discarded, [id]);
    },
  );

  test('foreign claimed batches do not block ordinary OS shares', () async {
    final owner = AccountIdentity(origin: _origin, userId: 7, systemId: 1);
    final other = AccountIdentity(origin: _origin, userId: 8, systemId: 1);
    const osId = '44444444-4444-4444-8444-444444444444';
    final owned = await _item(temporary, 0, 'owned.pdf', _pdf);
    final shared = await _item(temporary, 1, 'shared.pdf', _pdf);
    await queue.claimShareBatch(_batchId, owner);
    final intake = _FakeIntake([
      _batch([owned], rejected: 2),
      _batch([shared], id: osId),
    ]);
    final controller = ShareImportController(
      intake: intake,
      queue: queue,
      currentIdentity: () => other,
    );
    addTearDown(controller.close);
    addTearDown(intake.controller.close);
    final result = await controller.processPending();
    expect(result.staged, 1);
    expect(result.rejected, 0);
    expect(controller.lastSummary?.rejected, 0);
    expect((await database.allUploads()).single.identityUserId, other.userId);
    expect(await database.shareReceipt(_batchId, 0), isNull);
    expect(await queue.shareBatchClaim(_batchId), owner);
    expect(intake.discarded, [osId]);
  });

  test(
    'over-limit claimed picker batch keeps its original ownership',
    () async {
      final owner = AccountIdentity(origin: _origin, userId: 7, systemId: 1);
      final item = await _item(temporary, 0, 'owned.pdf', _pdf);
      await queue.claimShareBatch(_batchId, owner);
      final intake = _FakeIntake([
        _batch([item], rejected: 20),
      ]);
      final controller = ShareImportController(
        intake: intake,
        queue: queue,
        currentIdentity: () => owner,
      );
      addTearDown(controller.close);
      addTearDown(intake.controller.close);

      final summary = await controller.processPending();
      expect(summary.staged, 0);
      expect(summary.rejected, 0);
      expect(controller.errorMessage, isNotNull);
      expect(await database.allUploads(), isEmpty);
      expect(await queue.shareBatchClaim(_batchId), owner);
      expect(intake.discarded, isEmpty);
    },
  );

  test(
    'native picker errors retain the owner claim without disclosing paths',
    () async {
      final owner = AccountIdentity(origin: _origin, userId: 7, systemId: 1);
      final intake = _FakeIntake([]);
      intake.onPick = (_, _) async {
        throw StateError('Cannot open /private/native/secret.pdf');
      };
      final controller = ShareImportController(
        intake: intake,
        queue: queue,
        currentIdentity: () => owner,
      );
      addTearDown(controller.close);
      addTearDown(intake.controller.close);
      await controller.pick('photos');
      expect(await queue.shareBatchClaim(intake.picks.single.$2), owner);
      expect(controller.errorMessage, isNot(contains('/private/')));
      expect(controller.errorMessage, isNot(contains('secret.pdf')));
      expect(intake.discarded, isEmpty);
    },
  );

  test(
    'partial and oversize picker rejections retain claim until discard',
    () async {
      final owner = AccountIdentity(origin: _origin, userId: 7, systemId: 1);
      final good = await _item(temporary, 0, 'good.pdf', _pdf);
      final oversized = await _item(
        temporary,
        1,
        'oversized.pdf',
        _pdf,
        declaredSize: maximumDocumentBytes + 1,
      );
      final intake = _FakeIntake([], discardFailures: 1);
      intake.onPick = (_, id) async {
        intake.batches.add(_batch([good, oversized], rejected: 1, id: id));
        return id;
      };
      intake.onDiscard = (id) async {
        expect(await queue.shareBatchClaim(id), owner);
        expect(await database.shareReceipt(id, 0), isNotNull);
        expect(
          (await database.shareReceipt(id, 1))?.errorCode,
          'payload_too_large',
        );
      };
      final controller = ShareImportController(
        intake: intake,
        queue: queue,
        currentIdentity: () => owner,
      );
      addTearDown(controller.close);
      addTearDown(intake.controller.close);
      await controller.pick('files');
      final id = intake.picks.single.$2;
      expect(controller.lastSummary?.rejected, 2);
      expect(controller.errorMessage, isNotNull);
      expect(await queue.shareBatchClaim(id), owner);
      expect(await database.allUploads(), hasLength(1));
      expect(intake.discarded, isEmpty);
      final retried = await controller.processPending();
      expect(retried.alreadyStaged, 2);
      expect(await database.allUploads(), hasLength(1));
      expect(await queue.shareBatchClaim(id), isNull);
      expect(intake.discarded, [id]);
    },
  );

  test('corrupt claim cannot stage or discard the pending batch', () async {
    final item = await _item(temporary, 0, 'protected.pdf', _pdf);
    await database.setSetting('share_picker_claim:$_batchId', '{"user_id":7}');
    final intake = _FakeIntake([
      _batch([item], rejected: 1),
    ]);
    final controller = ShareImportController(
      intake: intake,
      queue: queue,
      currentIdentity: () =>
          AccountIdentity(origin: _origin, userId: 8, systemId: 1),
    );
    addTearDown(controller.close);
    addTearDown(intake.controller.close);
    final summary = await controller.processPending();
    expect(summary.staged, 0);
    expect(summary.rejected, 0);
    expect(await database.allUploads(), isEmpty);
    expect(intake.discarded, isEmpty);
    expect(controller.errorMessage, isNotNull);
  });
}

SharedBatch _batch(
  List<SharedItem> items, {
  int rejected = 0,
  bool complete = true,
  String id = _batchId,
}) => SharedBatch(
  id: id,
  createdAt: DateTime.utc(2026),
  items: items,
  rejectedCount: rejected,
  complete: complete,
);

Future<SharedItem> _item(
  Directory directory,
  int index,
  String name,
  List<int> bytes, {
  String declaredMime = 'application/pdf',
  int? declaredSize,
}) async {
  final file = File(path.join(directory.path, '$index-$name'));
  await file.writeAsBytes(bytes, flush: true);
  return SharedItem(
    index: index,
    path: file.path,
    mime: declaredMime,
    name: name,
    size: declaredSize ?? bytes.length,
    sha256: sha256.convert(bytes).toString(),
  );
}

final class _FakeIntake implements ShareIntake {
  _FakeIntake(this.batches, {this.discardFailures = 0});

  final List<SharedBatch> batches;
  int discardFailures;
  int pendingCalls = 0;
  Future<List<SharedBatch>> Function()? onPending;
  Future<void> Function(String batchId)? onDiscard;
  final List<String> discarded = [];
  Future<String?> Function(String source, String batchId)? onPick;
  final List<(String, String)> picks = [];
  final StreamController<void> controller = StreamController<void>.broadcast();

  @override
  Stream<void> get events => controller.stream;

  @override
  Future<String?> pick(String source, String batchId) async {
    picks.add((source, batchId));
    return await onPick?.call(source, batchId);
  }

  @override
  Future<void> discard(String batchId) async {
    await onDiscard?.call(batchId);
    if (discardFailures > 0) {
      discardFailures--;
      throw const ShareFailure(
        code: 'cleanup_failed',
        message: 'Native cleanup failed.',
        retryable: true,
      );
    }
    discarded.add(batchId);
    batches.removeWhere((batch) => batch.id == batchId);
  }

  @override
  Future<List<SharedBatch>> pending() async {
    pendingCalls++;
    return await onPending?.call() ?? List.of(batches);
  }
}

final class _NoopProtection implements StorageProtection, StorageCapacity {
  @override
  Future<int> availableBytes(String absolutePath) async => 1 << 60;

  @override
  Future<void> protectDirectory(String absolutePath) async {}
}
