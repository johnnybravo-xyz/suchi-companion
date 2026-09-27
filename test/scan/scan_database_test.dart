import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:suchi_mobile/scan/scan_database.dart';

void main() {
  test('creates the unreleased queue schema at version one', () async {
    final database = ScanDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await database.allUploads();

    final row = await database.customSelect('PRAGMA user_version').getSingle();
    expect(row.read<int>('user_version'), 1);
  });

  test('refuses an unsupported schema instead of migrating it', () async {
    final database = ScanDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('PRAGMA user_version = 2');
          raw.execute('CREATE TABLE preserved(value TEXT NOT NULL)');
          raw.execute("INSERT INTO preserved(value) VALUES ('queued data')");
        },
      ),
    );
    addTearDown(database.close);

    await expectLater(
      database.allUploads(),
      throwsA(isA<UnsupportedLocalStorageException>()),
    );
  });

  test(
    'classifies an unsupported schema from the background isolate',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'suchi-unsupported-database-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final file = File(path.join(directory.path, ScanDatabase.fileName));
      final seeded = ScanDatabase(NativeDatabase(file));
      try {
        await seeded.allUploads();
        await seeded.customStatement('PRAGMA user_version = 2');
      } finally {
        await seeded.close();
      }

      final database = ScanDatabase.open(directory);
      try {
        await expectLater(
          database.allUploads(),
          throwsA(
            predicate<Object>(
              isUnsupportedLocalStorageError,
              'an unsupported local storage error',
            ),
          ),
        );
      } finally {
        await database.close();
      }
    },
  );

  test('opens the queue database in its protected storage directory', () async {
    final directory = await Directory.systemTemp.createTemp(
      'suchi-queue-database-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final database = ScanDatabase.open(directory);
    addTearDown(database.close);

    await database.allUploads();

    expect(
      await File(path.join(directory.path, ScanDatabase.fileName)).exists(),
      isTrue,
    );
  });

  test('rejects a legacy database without modifying it', () async {
    final directory = await Directory.systemTemp.createTemp(
      'suchi-legacy-database-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final legacy = File(path.join(directory.path, ScanDatabase.fileName));
    const contents = <int>[1, 2, 3, 4];
    await legacy.writeAsBytes(contents, flush: true);

    await expectLater(
      ScanDatabase.rejectLegacyLocation(directory),
      throwsA(isA<UnsupportedLocalStorageException>()),
    );

    expect(await legacy.readAsBytes(), contents);
  });
}
