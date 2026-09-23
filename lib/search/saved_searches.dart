import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../auth/session_controller.dart';

final class SavedSearch {
  const SavedSearch({
    required this.id,
    required this.name,
    required this.query,
  });

  final String id;
  final String name;
  final String query;

  Map<String, String> toJson() => {'id': id, 'name': name, 'query': query};
}

final class SavedSearchController extends ChangeNotifier {
  SavedSearchController({required this.session, FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
              synchronizable: false,
            ),
            aOptions: AndroidOptions(),
          ) {
    session.addListener(_identityChanged);
    _identityChanged();
  }

  final SessionController session;
  final FlutterSecureStorage _storage;
  List<SavedSearch> _entries = const [];
  String? _key;
  String? _errorMessage;
  bool _loading = false;
  bool _saving = false;
  bool _disposed = false;
  bool _loaded = false;
  int _generation = 0;
  Future<void>? _pendingWrite;

  List<SavedSearch> get entries => _entries;
  String? get errorMessage => _errorMessage;
  bool get loading => _loading;
  bool get saving => _saving;
  bool get ready =>
      !_disposed && _key != null && _loaded && !_loading && !_saving;

  void _identityChanged() {
    final identity = session.identity;
    final key = identity == null
        ? null
        : 'suchi.mobile.saved-searches.v2.${sha256.convert(utf8.encode(jsonEncode(identity.storageKeyParts)))}';
    if (key == _key) return;
    _key = key;
    _generation++;
    _entries = const [];
    _errorMessage = null;
    _loaded = false;
    _loading = false;
    _saving = false;
    notifyListeners();
    if (key != null) unawaited(reload());
  }

  Future<void> reload() async {
    final key = _key;
    if (_disposed || key == null) return;
    final generation = ++_generation;
    _loading = true;
    _saving = false;
    _errorMessage = null;
    notifyListeners();
    try {
      // A write keeps its original account key even after an identity change.
      // Wait before reading so returning to that account sees the durable value.
      try {
        await _pendingWrite;
      } catch (_) {
        // A failed write leaves the preceding stored value available to read.
      }
      if (!_current(generation)) return;
      final encoded = await _storage.read(key: key);
      if (!_current(generation)) return;
      _entries = _decode(encoded);
      _loaded = true;
    } catch (_) {
      if (!_current(generation)) return;
      _loaded = false;
      _errorMessage = 'Saved searches could not be read. Try again to keep your existing searches safe.';
    } finally {
      if (_current(generation)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> save({required String name, required String query}) async {
    if (!ready) return false;
    final trimmedName = name.trim();
    final trimmedQuery = query.trim();
    if (trimmedName.isEmpty || trimmedQuery.isEmpty) {
      _errorMessage = 'Enter a name and a search before saving.';
      notifyListeners();
      return false;
    }
    return _write([
      ..._entries,
      SavedSearch(
        id: const Uuid().v4(),
        name: trimmedName,
        query: trimmedQuery,
      ),
    ]);
  }

  Future<bool> remove(String id) async {
    if (!ready) return false;
    if (!_entries.any((entry) => entry.id == id)) return true;
    return _write(_entries.where((entry) => entry.id != id).toList());
  }

  Future<bool> _write(List<SavedSearch> entries) async {
    final key = _key!;
    final generation = _generation;
    _saving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final write = _storage.write(
        key: key,
        value: jsonEncode({
          'version': 1,
          'searches': entries.map((entry) => entry.toJson()).toList(),
        }),
      );
      _pendingWrite = write;
      await write;
      if (!_current(generation)) return false;
      _entries = List.unmodifiable(entries);
      return true;
    } catch (_) {
      if (_current(generation)) {
        _errorMessage = 'Saved searches could not be updated. Your previous searches are unchanged; try again.';
      }
      return false;
    } finally {
      if (_current(generation)) {
        _saving = false;
        notifyListeners();
      }
    }
  }

  List<SavedSearch> _decode(String? encoded) {
    if (encoded == null) return const [];
    final value = jsonDecode(encoded);
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['searches'] is! List) {
      throw const FormatException('Invalid saved searches');
    }
    final entries = <SavedSearch>[];
    final ids = <String>{};
    for (final entry in value['searches'] as List) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid saved search');
      }
      final id = entry['id'];
      final name = entry['name'];
      final query = entry['query'];
      if (id is! String ||
          id.isEmpty ||
          !ids.add(id) ||
          name is! String ||
          name.trim().isEmpty ||
          query is! String ||
          query.trim().isEmpty) {
        throw const FormatException('Invalid saved search');
      }
      entries.add(SavedSearch(id: id, name: name, query: query));
    }
    return List.unmodifiable(entries);
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _entries = const [];
    session.removeListener(_identityChanged);
    super.dispose();
  }
}
