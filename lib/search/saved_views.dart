import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../auth/account_identity.dart';
import '../auth/session_controller.dart';

final class SavedViewController extends ChangeNotifier {
  SavedViewController({required this.session}) {
    session.addListener(_identityChanged);
    _identityChanged();
  }

  final SessionController session;
  List<SavedView> _entries = const [];
  AccountIdentity? _identity;
  SuchiClient? _client;
  String? _errorMessage;
  bool _loading = false;
  bool _saving = false;
  bool _disposed = false;
  bool _loaded = false;
  int _accountGeneration = 0;
  int _loadGeneration = 0;

  List<SavedView> get entries => _entries;
  String? get errorMessage => _errorMessage;
  bool get loading => _loading;
  bool get saving => _saving;
  bool get ready =>
      !_disposed && _client != null && _loaded && !_loading && !_saving;

  void _identityChanged() {
    final identity = session.identity;
    final client = session.client;
    if (identity == _identity && client == _client) return;
    _identity = identity;
    _client = identity == null ? null : client;
    _accountGeneration++;
    _loadGeneration++;
    _entries = const [];
    _errorMessage = null;
    _loaded = false;
    _loading = false;
    _saving = false;
    notifyListeners();
    if (_client != null) unawaited(reload());
  }

  Future<void> reload() async {
    final client = _client;
    if (_disposed || client == null) return;
    final accountGeneration = _accountGeneration;
    final loadGeneration = ++_loadGeneration;
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final entries = await _listAll(client);
      if (!_current(accountGeneration) || loadGeneration != _loadGeneration) {
        return;
      }
      final ids = <int>{};
      if (entries.any((view) => !ids.add(view.id))) {
        throw const ApiException(
          kind: ApiFailureKind.malformedResponse,
          message: 'Suchi returned duplicate Saved Views.',
        );
      }
      _entries = List.unmodifiable(entries);
      _loaded = true;
    } on ApiException catch (error) {
      if (!_current(accountGeneration) || loadGeneration != _loadGeneration) {
        return;
      }
      if (error.expiresSession) {
        await session.expire(error);
        return;
      }
      _errorMessage = 'Saved Views could not be loaded. ${error.message}';
    } finally {
      if (_current(accountGeneration) && loadGeneration == _loadGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<List<SavedView>> _listAll(SuchiClient client) async {
    final entries = <SavedView>[];
    int? expectedCount;
    for (var pageNumber = 1; pageNumber <= 100; pageNumber++) {
      final page = await client.listSavedViews(page: pageNumber, pageSize: 500);
      expectedCount ??= page.count;
      if (page.count != expectedCount ||
          entries.length + page.results.length > expectedCount) {
        throw const ApiException(
          kind: ApiFailureKind.malformedResponse,
          message: 'Suchi returned an inconsistent Saved View list.',
        );
      }
      entries.addAll(page.results);
      if (entries.length == expectedCount && page.next == null) return entries;
      if (page.results.isEmpty || page.next == null) {
        throw const ApiException(
          kind: ApiFailureKind.malformedResponse,
          message: 'Suchi returned an incomplete Saved View list.',
        );
      }
    }
    throw const ApiException(
      kind: ApiFailureKind.malformedResponse,
      message: 'Suchi returned too many Saved View pages.',
    );
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
    final client = _client!;
    final accountGeneration = _accountGeneration;
    var nextPosition = 0;
    for (final view in _entries) {
      if (view.position >= nextPosition) nextPosition = view.position + 1;
    }
    _saving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await client.createSavedView(
        name: trimmedName,
        filterJson: jsonEncode({'q': trimmedQuery}),
        position: nextPosition,
      );
      if (!_current(accountGeneration)) return false;
      _saving = false;
      await reload();
      return true;
    } on ApiException catch (error) {
      if (!_current(accountGeneration)) return false;
      if (error.expiresSession) {
        await session.expire(error);
        return false;
      }
      _errorMessage = 'Saved View could not be created. ${error.message}';
      return false;
    } finally {
      if (_current(accountGeneration) && _saving) {
        _saving = false;
        notifyListeners();
      }
    }
  }

  Future<bool> remove(int id) async {
    if (!ready) return false;
    if (!_entries.any((entry) => entry.id == id)) return true;
    final client = _client!;
    final accountGeneration = _accountGeneration;
    _saving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await client.deleteSavedView(id);
      if (!_current(accountGeneration)) return false;
      _saving = false;
      await reload();
      return true;
    } on ApiException catch (error) {
      if (!_current(accountGeneration)) return false;
      if (error.expiresSession) {
        await session.expire(error);
        return false;
      }
      _errorMessage = 'Saved View could not be deleted. ${error.message}';
      return false;
    } finally {
      if (_current(accountGeneration) && _saving) {
        _saving = false;
        notifyListeners();
      }
    }
  }

  bool _current(int accountGeneration) =>
      !_disposed && accountGeneration == _accountGeneration;

  @override
  void dispose() {
    _disposed = true;
    _accountGeneration++;
    _loadGeneration++;
    _entries = const [];
    session.removeListener(_identityChanged);
    super.dispose();
  }
}
