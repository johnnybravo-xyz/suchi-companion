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
  List<ApprovalTask> _approvals = const [];
  List<PendingDateReview> _dates = const [];
  String? _approvalError;
  String? _dateError;
  Set<int> _busyApprovalIds = const {};
  Set<int> _busyDateIds = const {};
  bool _canReviewDates = false;
  bool _loadingApprovals = false;
  bool _loadingDates = false;
  bool _disposed = false;
  int _accountGeneration = 0;
  int _loadGeneration = 0;

  List<ApprovalTask> get approvals => _approvals;
  List<PendingDateReview> get dates => _dates;
  String? get approvalError => _approvalError;
  String? get dateError => _dateError;
  bool get loadingApprovals => _loadingApprovals;
  bool get loadingDates => _loadingDates;
  bool get loading => _loadingApprovals || _loadingDates;
  bool get hasPending => _approvals.isNotEmpty || _dates.isNotEmpty;
  bool get canReviewDates => _canReviewDates;
  bool approvalBusy(int id) => _busyApprovalIds.contains(id);
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
    _approvals = const [];
    _dates = const [];
    _approvalError = null;
    _dateError = null;
    _busyApprovalIds = const {};
    _busyDateIds = const {};
    _loadingApprovals = false;
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
    _approvalError = null;
    _dateError = null;
    _loadingApprovals = true;
    _loadingDates = _canReviewDates;
    if (!_canReviewDates) _dates = const [];
    notifyListeners();

    await Future.wait([
      _reloadApprovals(client, identity, accountGeneration, loadGeneration),
      if (_canReviewDates)
        _reloadDates(client, identity, accountGeneration, loadGeneration),
    ]);
  }

  Future<void> _reloadApprovals(
    SuchiClient client,
    AccountIdentity identity,
    int accountGeneration,
    int loadGeneration,
  ) async {
    try {
      final approvals = await client.listApprovals();
      if (!_current(identity, client, accountGeneration) ||
          loadGeneration != _loadGeneration) {
        return;
      }
      _requireUnique(approvals.map((entry) => entry.id), 'approvals');
      _approvals = List.unmodifiable(approvals);
    } on ApiException catch (error) {
      if (!_current(identity, client, accountGeneration) ||
          loadGeneration != _loadGeneration) {
        return;
      }
      if (error.expiresSession) {
        await session.expire(error);
        return;
      }
      _approvalError = 'Approvals could not be loaded. ${error.message}';
    } finally {
      if (_current(identity, client, accountGeneration) &&
          loadGeneration == _loadGeneration) {
        _loadingApprovals = false;
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

  Future<void> resolveApproval(int id, String choice) async {
    final client = _client;
    final identity = _identity;
    ApprovalTask? approval;
    for (final candidate in _approvals) {
      if (candidate.id == id) {
        approval = candidate;
        break;
      }
    }
    if (_disposed ||
        client == null ||
        identity == null ||
        _busyApprovalIds.contains(id) ||
        approval == null ||
        !approval.choices.contains(choice)) {
      return;
    }
    final accountGeneration = _accountGeneration;
    _busyApprovalIds = {..._busyApprovalIds, id};
    notifyListeners();
    try {
      await client.resolveApproval(id, choice);
      if (!_current(identity, client, accountGeneration)) return;
      _approvals = List.unmodifiable(
        _approvals.where((entry) => entry.id != id),
      );
      _approvalError = null;
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
        _busyApprovalIds = {..._busyApprovalIds}..remove(id);
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
    _approvals = const [];
    _dates = const [];
    _busyApprovalIds = const {};
    _busyDateIds = const {};
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}
