import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../auth/account_identity.dart';
import '../auth/session_controller.dart';

final class ApprovalsController extends ChangeNotifier {
  ApprovalsController({required this.session}) {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }

  final SessionController session;

  AccountIdentity? _identity;
  SuchiClient? _client;
  List<DocumentChangeApprovalTask> _documentChanges = const [];
  List<PendingDateReview> _dates = const [];
  String? _documentChangeError;
  String? _dateError;
  Set<int> _busyDocumentChangeIds = const {};
  Set<int> _busyDateIds = const {};
  bool _canReviewDates = false;
  bool _loadingDocumentChanges = false;
  bool _loadingDates = false;
  bool _disposed = false;
  int _accountGeneration = 0;
  int _loadGeneration = 0;

  List<DocumentChangeApprovalTask> get documentChanges => _documentChanges;
  List<PendingDateReview> get dates => _dates;
  String? get documentChangeError => _documentChangeError;
  String? get dateError => _dateError;
  bool get loadingDocumentChanges => _loadingDocumentChanges;
  bool get loadingDates => _loadingDates;
  bool get loading => _loadingDocumentChanges || _loadingDates;
  bool get hasPending => _documentChanges.isNotEmpty || _dates.isNotEmpty;
  bool get canReviewDates => _canReviewDates;
  bool documentChangeBusy(int id) => _busyDocumentChangeIds.contains(id);
  bool dateBusy(int id) => _busyDateIds.contains(id);

  void _sessionChanged() {
    final online = session.state == SessionState.signedIn;
    final identity = online ? session.identity : null;
    final client = online ? session.client : null;
    final user = online ? session.user : null;
    final canReviewDates =
        user != null &&
        (user.role == 'admin' ||
            user.capabilities.contains('archive_intelligence'));
    if (identity == _identity &&
        client == _client &&
        canReviewDates == _canReviewDates) {
      return;
    }

    _identity = identity;
    _client = client;
    _canReviewDates = canReviewDates;
    _accountGeneration++;
    _loadGeneration++;
    _documentChanges = const [];
    _dates = const [];
    _documentChangeError = null;
    _dateError = null;
    _busyDocumentChangeIds = const {};
    _busyDateIds = const {};
    _loadingDocumentChanges = false;
    _loadingDates = false;
    notifyListeners();
    if (client != null && identity != null) unawaited(reload());
  }

  Future<void> reload() async {
    final client = _client;
    final identity = _identity;
    if (_disposed || client == null || identity == null) return;
    final accountGeneration = _accountGeneration;
    final loadGeneration = ++_loadGeneration;
    _documentChangeError = null;
    _dateError = null;
    _loadingDocumentChanges = true;
    _loadingDates = _canReviewDates;
    if (!_canReviewDates) _dates = const [];
    notifyListeners();

    await Future.wait([
      _reloadDocumentChanges(
        client,
        identity,
        accountGeneration,
        loadGeneration,
      ),
      if (_canReviewDates)
        _reloadDates(client, identity, accountGeneration, loadGeneration),
    ]);
  }

  Future<void> _reloadDocumentChanges(
    SuchiClient client,
    AccountIdentity identity,
    int accountGeneration,
    int loadGeneration,
  ) async {
    try {
      final changes = await client.listDocumentChangeApprovals();
      if (!_current(identity, client, accountGeneration) ||
          loadGeneration != _loadGeneration) {
        return;
      }
      _requireUnique(changes.map((entry) => entry.id), 'document changes');
      _documentChanges = List.unmodifiable(changes);
    } on ApiException catch (error) {
      if (!_current(identity, client, accountGeneration) ||
          loadGeneration != _loadGeneration) {
        return;
      }
      if (error.expiresSession) {
        await session.expire(error);
        return;
      }
      _documentChangeError =
          'Document suggestions could not be loaded. ${error.message}';
    } finally {
      if (_current(identity, client, accountGeneration) &&
          loadGeneration == _loadGeneration) {
        _loadingDocumentChanges = false;
        notifyListeners();
      }
    }
  }

  Future<void> _reloadDates(
    SuchiClient client,
    AccountIdentity identity,
    int accountGeneration,
    int loadGeneration,
  ) async {
    try {
      final dates = await client.listPendingDates();
      if (!_current(identity, client, accountGeneration) ||
          loadGeneration != _loadGeneration) {
        return;
      }
      _requireUnique(dates.map((entry) => entry.id), 'date reviews');
      _dates = List.unmodifiable(dates);
    } on ApiException catch (error) {
      if (!_current(identity, client, accountGeneration) ||
          loadGeneration != _loadGeneration) {
        return;
      }
      if (error.expiresSession) {
        await session.expire(error);
        return;
      }
      _dateError = 'Dates could not be loaded. ${error.message}';
    } finally {
      if (_current(identity, client, accountGeneration) &&
          loadGeneration == _loadGeneration) {
        _loadingDates = false;
        notifyListeners();
      }
    }
  }

  Future<void> resolveDocumentChange(int id, ReviewDecision decision) async {
    final client = _client;
    final identity = _identity;
    if (_disposed ||
        client == null ||
        identity == null ||
        _busyDocumentChangeIds.contains(id) ||
        !_documentChanges.any((entry) => entry.id == id)) {
      return;
    }
    final accountGeneration = _accountGeneration;
    _busyDocumentChangeIds = {..._busyDocumentChangeIds, id};
    notifyListeners();
    try {
      await client.resolveDocumentChangeApproval(id, decision);
      if (!_current(identity, client, accountGeneration)) return;
      _documentChanges = List.unmodifiable(
        _documentChanges.where((entry) => entry.id != id),
      );
      _documentChangeError = null;
      notifyListeners();
      await reload();
    } on ApiException catch (error) {
      if (!_current(identity, client, accountGeneration)) return;
      if (error.expiresSession) {
        await session.expire(error);
        return;
      }
      if (_reviewChanged(error)) await reload();
      if (_current(identity, client, accountGeneration)) rethrow;
    } finally {
      if (_current(identity, client, accountGeneration)) {
        _busyDocumentChangeIds = {..._busyDocumentChangeIds}..remove(id);
        notifyListeners();
      }
    }
  }

  Future<void> resolveDate(int id, ReviewDecision decision) async {
    final client = _client;
    final identity = _identity;
    if (_disposed ||
        client == null ||
        identity == null ||
        _busyDateIds.contains(id) ||
        !_dates.any((entry) => entry.id == id)) {
      return;
    }
    final accountGeneration = _accountGeneration;
    _busyDateIds = {..._busyDateIds, id};
    notifyListeners();
    try {
      await client.resolvePendingDate(id, decision);
      if (!_current(identity, client, accountGeneration)) return;
      _dates = List.unmodifiable(_dates.where((entry) => entry.id != id));
      _dateError = null;
      notifyListeners();
      await reload();
    } on ApiException catch (error) {
      if (!_current(identity, client, accountGeneration)) return;
      if (error.expiresSession) {
        await session.expire(error);
        return;
      }
      if (_reviewChanged(error)) await reload();
      if (_current(identity, client, accountGeneration)) rethrow;
    } finally {
      if (_current(identity, client, accountGeneration)) {
        _busyDateIds = {..._busyDateIds}..remove(id);
        notifyListeners();
      }
    }
  }

  bool _current(
    AccountIdentity identity,
    SuchiClient client,
    int accountGeneration,
  ) =>
      !_disposed &&
      accountGeneration == _accountGeneration &&
      identity == _identity &&
      identical(client, _client);

  static bool _reviewChanged(ApiException error) =>
      error.statusCode == 404 ||
      error.kind == ApiFailureKind.conflict ||
      const {
        'not_found',
        'no_task',
        'already_resolved',
        'stale_proposal',
        'stale_source',
        'conflict',
      }.contains(error.code);

  static void _requireUnique(Iterable<int> ids, String label) {
    final seen = <int>{};
    for (final id in ids) {
      if (!seen.add(id)) {
        throw ApiException(
          kind: ApiFailureKind.malformedResponse,
          message: 'Suchi returned duplicate $label.',
        );
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _accountGeneration++;
    _loadGeneration++;
    _documentChanges = const [];
    _dates = const [];
    _busyDocumentChangeIds = const {};
    _busyDateIds = const {};
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}
