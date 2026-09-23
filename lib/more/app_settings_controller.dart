import 'package:flutter/material.dart';

import '../documents/document_list_mode.dart';
import '../scan/scan_database.dart';
import '../scan/scanner_bridge.dart';

final class AppSettingsController extends ChangeNotifier {
  AppSettingsController(this._database);

  static const _serverOcrOnlyKey = 'server_ocr_only';
  static const _themeModeKey = 'theme_mode';
  static const _documentListModeKey = 'document_list_mode';
  static const _captureModeKey = 'capture_mode';

  final ScanDatabase _database;
  bool _serverOcrOnly = false;
  ThemeMode _themeMode = ThemeMode.system;
  DocumentListMode _documentListMode = DocumentListMode.standard;
  CaptureMode _captureMode = CaptureMode.scanner;
  bool _loaded = false;

  bool get serverOcrOnly => _serverOcrOnly;
  ThemeMode get themeMode => _themeMode;
  DocumentListMode get documentListMode => _documentListMode;
  CaptureMode get captureMode => _captureMode;
  bool get loaded => _loaded;

  Future<void> initialize() async {
    final storedOcr = await _database.setting(_serverOcrOnlyKey);
    final storedTheme = await _database.setting(_themeModeKey);
    final storedListMode = await _database.setting(_documentListModeKey);
    final storedCaptureMode = await _database.setting(_captureModeKey);
    _captureMode = storedCaptureMode == 'photo'
        ? CaptureMode.photo
        : CaptureMode.scanner;
    _serverOcrOnly = storedOcr == 'true';
    _themeMode = switch (storedTheme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _documentListMode =
        DocumentListMode.values
            .where((mode) => mode.name == storedListMode)
            .firstOrNull ??
        DocumentListMode.standard;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setServerOcrOnly(bool value) async {
    if (!_loaded || value == _serverOcrOnly) return;
    await _database.setSetting(_serverOcrOnlyKey, value ? 'true' : 'false');
    _serverOcrOnly = value;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    if (!_loaded || value == _themeMode) return;
    await _database.setSetting(_themeModeKey, value.name);
    _themeMode = value;
    notifyListeners();
  }

  Future<void> setDocumentListMode(DocumentListMode value) async {
    if (!_loaded || value == _documentListMode) return;
    await _database.setSetting(_documentListModeKey, value.name);
    _documentListMode = value;
    notifyListeners();
  }

  Future<void> setCaptureMode(CaptureMode value) async {
    if (!_loaded || value == _captureMode) return;
    await _database.setSetting(_captureModeKey, value.name);
    _captureMode = value;
    notifyListeners();
  }
}
