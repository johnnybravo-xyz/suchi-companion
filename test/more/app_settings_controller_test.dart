import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_companion/documents/document_list_mode.dart';
import 'package:suchi_companion/more/app_settings_controller.dart';
import 'package:suchi_companion/scan/scan_database.dart';
import 'package:suchi_companion/scan/scanner_bridge.dart';

void main() {
  late ScanDatabase database;
  late AppSettingsController settings;

  setUp(() {
    database = ScanDatabase(NativeDatabase.memory());
    settings = AppSettingsController(database);
  });

  tearDown(() async {
    settings.dispose();
    await database.close();
  });

  test(
    'capture mode defaults safely, persists, and survives a failed write',
    () async {
      await database.setSetting('capture_mode', 'unknown');
      await settings.initialize();
      expect(settings.captureMode, CaptureMode.scanner);
      await settings.setCaptureMode(CaptureMode.photo);
      settings.dispose();
      settings = AppSettingsController(database);
      await settings.initialize();
      expect(settings.captureMode, CaptureMode.photo);
      await database.customStatement('''
      CREATE TRIGGER reject_capture_mode BEFORE INSERT ON app_settings
      WHEN NEW.key = 'capture_mode'
      BEGIN SELECT RAISE(ABORT, 'storage unavailable'); END;
    ''');
      await expectLater(
        settings.setCaptureMode(CaptureMode.scanner),
        throwsA(anything),
      );
      expect(settings.captureMode, CaptureMode.photo);
      await database.customStatement('DROP TRIGGER reject_capture_mode');
      await settings.setCaptureMode(CaptureMode.scanner);
      expect(settings.captureMode, CaptureMode.scanner);
    },
  );

  test('document views default safely and survive reconstruction', () async {
    await settings.initialize();
    expect(settings.documentListMode, DocumentListMode.standard);
    await database.setSetting('document_list_mode', 'unknown');
    await settings.initialize();
    expect(settings.documentListMode, DocumentListMode.standard);
    for (final mode in [
      DocumentListMode.compact,
      DocumentListMode.detailed,
      DocumentListMode.standard,
    ]) {
      await settings.setDocumentListMode(mode);
      settings.dispose();
      settings = AppSettingsController(database);
      await settings.initialize();
      expect(settings.documentListMode, mode);
    }
  });

  test('failed view write keeps the current view and can retry', () async {
    await settings.initialize();
    await database.customStatement('''
      CREATE TRIGGER reject_view_write BEFORE INSERT ON app_settings
      WHEN NEW.key = 'document_list_mode'
      BEGIN SELECT RAISE(ABORT, 'storage unavailable'); END;
    ''');
    await expectLater(
      settings.setDocumentListMode(DocumentListMode.detailed),
      throwsA(anything),
    );
    expect(settings.documentListMode, DocumentListMode.standard);
    await database.customStatement('DROP TRIGGER reject_view_write');
    await settings.setDocumentListMode(DocumentListMode.detailed);
    expect(settings.documentListMode, DocumentListMode.detailed);
  });

  test(
    'publishes loaded only when appearance and capture preferences are ready',
    () async {
      await database.setSetting('theme_mode', 'dark');
      await database.setSetting('server_ocr_only', 'true');
      final observed = <(bool, ThemeMode, bool)>[];
      settings.addListener(() {
        observed.add((
          settings.loaded,
          settings.themeMode,
          settings.serverOcrOnly,
        ));
      });

      expect(settings.loaded, isFalse);
      await settings.initialize();

      expect(observed, [(true, ThemeMode.dark, true)]);
    },
  );

  test(
    'all appearance choices survive reconstruction without changing OCR',
    () async {
      await settings.initialize();
      await settings.setServerOcrOnly(true);

      for (final mode in [ThemeMode.light, ThemeMode.dark, ThemeMode.system]) {
        await settings.setThemeMode(mode);
        expect(await database.setting('theme_mode'), mode.name);
        settings.dispose();
        settings = AppSettingsController(database);
        await settings.initialize();

        expect(settings.themeMode, mode);
        expect(settings.serverOcrOnly, isTrue);
      }
    },
  );

  for (final stored in <String?>[null, 'unknown']) {
    test('${stored ?? 'missing'} appearance follows the system', () async {
      if (stored != null) await database.setSetting('theme_mode', stored);
      await database.setSetting('server_ocr_only', 'true');

      await settings.initialize();

      expect(settings.themeMode, ThemeMode.system);
      expect(settings.serverOcrOnly, isTrue);
    });
  }

  test(
    'failed theme write preserves selection and leaves OCR writable',
    () async {
      await settings.initialize();
      await settings.setThemeMode(ThemeMode.light);
      await database.customStatement('''
      CREATE TRIGGER reject_theme_write
      BEFORE INSERT ON app_settings
      WHEN NEW.key = 'theme_mode'
      BEGIN
        SELECT RAISE(ABORT, 'theme storage unavailable');
      END;
    ''');
      var notifications = 0;
      settings.addListener(() => notifications++);

      await expectLater(
        settings.setThemeMode(ThemeMode.dark),
        throwsA(anything),
      );

      expect(settings.themeMode, ThemeMode.light);
      expect(await database.setting('theme_mode'), 'light');
      expect(notifications, 0);
      await settings.setServerOcrOnly(true);
      expect(settings.serverOcrOnly, isTrue);
      expect(await database.setting('server_ocr_only'), 'true');

      await database.customStatement('DROP TRIGGER reject_theme_write');
      await settings.setThemeMode(ThemeMode.dark);
      expect(settings.themeMode, ThemeMode.dark);
      expect(await database.setting('theme_mode'), 'dark');
    },
  );

  test(
    'failed OCR write preserves capture preference and appearance',
    () async {
      await settings.initialize();
      await settings.setServerOcrOnly(true);
      await database.customStatement('''
      CREATE TRIGGER reject_ocr_write
      BEFORE INSERT ON app_settings
      WHEN NEW.key = 'server_ocr_only'
      BEGIN
        SELECT RAISE(ABORT, 'capture storage unavailable');
      END;
    ''');

      await expectLater(settings.setServerOcrOnly(false), throwsA(anything));

      expect(settings.serverOcrOnly, isTrue);
      expect(await database.setting('server_ocr_only'), 'true');
      await settings.setThemeMode(ThemeMode.dark);
      expect(settings.themeMode, ThemeMode.dark);
      expect(await database.setting('theme_mode'), 'dark');
    },
  );
}
