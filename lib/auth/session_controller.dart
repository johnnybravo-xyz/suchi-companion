import 'package:flutter/foundation.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import 'account_identity.dart';
import 'credential_vault.dart';
import 'pairing_link.dart';
import 'server_origin.dart';

enum SessionState { loading, signedOut, verifying, signedIn, expired }

typedef SuchiClientFactory = SuchiClient Function(Uri origin, String? token);

final class SessionController extends ChangeNotifier {
  SessionController({
    required this.vault,
    SuchiClientFactory? clientFactory,
    this.onPauseUploads,
    this.allowDevelopmentHttp = true,
    this.onClearMemoryCaches,
    this.onResumeUploads,
  }) : _clientFactory =
           clientFactory ??
           ((origin, token) => SuchiClient(origin: origin, token: token));

  final CredentialVault vault;
  final Future<void> Function()? onPauseUploads;
  final VoidCallback? onClearMemoryCaches;
  final Future<void> Function()? onResumeUploads;
  // The production policy always rejects HTTP outside debug, even if true.
  final bool allowDevelopmentHttp;
  final SuchiClientFactory _clientFactory;

  SessionState _state = SessionState.loading;
  SuchiClient? _client;
  UserSelf? _user;
  Uri? _origin;
  String? _errorMessage;
  String? _requestId;
  Uri? _preparedOrigin;
  StoredCredentials? _retryCredentials;
  int _generation = 0;

  SessionState get state => _state;
  SuchiClient? get client => _client;
  UserSelf? get user => _user;
  Uri? get origin => _origin;
  AccountIdentity? get identity {
    final user = _user;
    final origin = _origin;
    if (_state != SessionState.signedIn || user == null || origin == null) {
      return null;
    }
    return AccountIdentity(
      origin: origin,
      userId: user.userId,
      systemId: user.systemId,
    );
  }

  String? get errorMessage => _errorMessage;
  String? get requestId => _requestId;
  bool get canRetryStoredCredentials => _retryCredentials != null;
  Uri? get preparedOrigin => _preparedOrigin;

  Future<void> initialize() async {
    final generation = ++_generation;
    _setState(SessionState.loading);
    try {
      final credentials = await vault.read();
      if (generation != _generation) return;
      if (credentials == null) {
        _setState(SessionState.signedOut);
        return;
      }
      _retryCredentials = credentials;
      await _verifyCredentials(
        credentials,
        generation: generation,
        restoring: true,
      );
    } catch (_) {
      if (generation != _generation) return;
      _setState(
        SessionState.signedOut,
        error: 'Secure credentials could not be read on this device.',
      );
    }
  }

  Future<bool> verifyServerAddress(String serverAddress) async {
    final Uri origin;
    try {
      origin = ServerOrigin.parse(
        serverAddress,
        allowDevelopmentHttp: allowDevelopmentHttp,
      );
    } on ServerOriginException catch (error) {
      _preparedOrigin = null;
      _setState(SessionState.signedOut, error: error.message);
      return false;
    }
    final generation = ++_generation;
    _preparedOrigin = null;
    _setState(SessionState.verifying);
    final probe = _clientFactory(origin, null);
    try {
      await probe.handshake();
      if (generation != _generation) return false;
      _preparedOrigin = origin;
      _setState(SessionState.signedOut);
      return true;
    } on ApiException catch (error) {
      if (generation != _generation) return false;
      _setState(
        SessionState.signedOut,
        error: error.message,
        requestId: error.requestId,
      );
    } catch (_) {
      if (generation != _generation) return false;
      _setState(
        SessionState.signedOut,
        error: 'This device could not verify the Suchi server.',
      );
    } finally {
      probe.close();
    }
    return false;
  }

  void clearPreparedServer() {
    if (_state == SessionState.verifying) return;
    _preparedOrigin = null;
    _setState(SessionState.signedOut);
  }

  Future<void> pairWithToken({
    required String serverAddress,
    required String token,
  }) async {
    final normalizedToken = token.trim();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedToken)) {
      _setState(
        SessionState.signedOut,
        error: 'API token must be 64 lowercase hexadecimal characters.',
      );
      return;
    }
    await _pair(
      serverAddress: serverAddress,
      obtainToken: (probe) async => normalizedToken,
    );
  }

  Future<void> pairWithPassword({
    required String serverAddress,
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      _setState(
        SessionState.signedOut,
        error: 'Enter both your email address and password.',
      );
      return;
    }
    await _pair(
      serverAddress: serverAddress,
      obtainToken: (probe) =>
          probe.exchangePassword(email: normalizedEmail, password: password),
    );
  }

  Future<void> pairWithLink(
    PairingLink pairing, {
    required String deviceName,
  }) => _pair(
    serverAddress: pairing.origin.toString(),
    reuseVerifiedOrigin: false,
    obtainToken: (probe) =>
        probe.exchangePairingCode(pairing.code, deviceName: deviceName),
  );

  Future<void> retryStoredCredentials() async {
    final credentials = _retryCredentials;
    if (credentials == null) return;
    final generation = ++_generation;
    _setState(SessionState.verifying);
    await _verifyCredentials(
      credentials,
      generation: generation,
      restoring: true,
    );
  }

  Future<void> expire(ApiException error) async {
    if (!error.expiresSession || _state == SessionState.expired) return;
    ++_generation;
    try {
      await onPauseUploads?.call();
    } catch (_) {
      // An expired token must fail closed even if local cleanup fails.
    }
    _closeClient();
    _user = null;
    onClearMemoryCaches?.call();
    _preparedOrigin = null;
    _retryCredentials = null;
    try {
      await vault.clear();
    } catch (_) {
      // Authentication still fails closed when secure-storage deletion fails.
    }
    _setState(
      SessionState.expired,
      error: 'Your Suchi session expired. Pair this device again.',
      requestId: error.requestId,
    );
  }

  Future<bool> signOut() async {
    ++_generation;
    try {
      await onPauseUploads?.call();
      await vault.clear();
    } catch (_) {
      _setState(
        SessionState.signedIn,
        error: 'This device could not clear protected local data. You are still signed in.',
      );
      try {
        await onResumeUploads?.call();
      } catch (_) {
        // The credential remains usable even if queued work cannot resume yet.
      }
      return false;
    }
    final client = _client;
    if (client != null) {
      try {
        await client.logout();
      } catch (_) {
        // Local credential deletion is authoritative even if logout is offline.
      }
    }
    _closeClient();
    _user = null;
    _origin = null;
    _retryCredentials = null;
    _preparedOrigin = null;
    onClearMemoryCaches?.call();
    _setState(SessionState.signedOut);
    return true;
  }

  Future<void> _pair({
    required String serverAddress,
    required Future<String> Function(SuchiClient probe) obtainToken,
    bool reuseVerifiedOrigin = true,
  }) async {
    final Uri origin;
    try {
      origin = ServerOrigin.parse(
        serverAddress,
        allowDevelopmentHttp: allowDevelopmentHttp,
      );
    } on ServerOriginException catch (error) {
      _setState(SessionState.signedOut, error: error.message);
      return;
    }

    final generation = ++_generation;
    _setState(SessionState.verifying);
    final probe = _clientFactory(origin, null);
    try {
      final handshakeComplete =
          reuseVerifiedOrigin && _preparedOrigin == origin;
      if (!handshakeComplete) await probe.handshake();
      if (generation != _generation) return;
      final token = await obtainToken(probe);
      if (generation != _generation) return;
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
        throw const ApiException(
          kind: ApiFailureKind.malformedResponse,
          message: 'Suchi returned an invalid API token.',
        );
      }
      final credentials = StoredCredentials(origin: origin, token: token);
      await _verifyCredentials(
        credentials,
        generation: generation,
        restoring: false,
        handshakeComplete: true,
      );
    } on ApiException catch (error) {
      if (generation != _generation) return;
      _setState(
        SessionState.signedOut,
        error: error.message,
        requestId: error.requestId,
      );
    } catch (_) {
      if (generation != _generation) return;
      _setState(
        SessionState.signedOut,
        error: 'This device could not verify the Suchi server.',
      );
    } finally {
      probe.close();
    }
  }

  Future<void> _verifyCredentials(
    StoredCredentials credentials, {
    required int generation,
    required bool restoring,
    bool handshakeComplete = false,
  }) async {
    _setState(SessionState.verifying);
    SuchiClient? client;
    final Uri origin;
    try {
      origin = ServerOrigin.parse(
        credentials.origin.toString(),
        allowDevelopmentHttp: allowDevelopmentHttp,
      );
    } on ServerOriginException catch (error) {
      if (generation == _generation) {
        _setState(SessionState.signedOut, error: error.message);
      }
      return;
    }
    try {
      if (!handshakeComplete) {
        final probe = _clientFactory(origin, null);
        try {
          await probe.handshake();
        } finally {
          probe.close();
        }
      }
      if (generation != _generation) return;
      client = _clientFactory(origin, credentials.token);
      final user = await client.whoAmI();
      if (!user.hasMobileScopes) {
        throw const ApiException(
          kind: ApiFailureKind.forbidden,
          message: 'The token needs documents:read and documents:write scopes.',
        );
      }
      if (generation != _generation) return;
      if (!restoring) await vault.save(credentials);
      if (generation != _generation) return;
      _closeClient();
      _client = client;
      client = null;
      _user = user;
      _origin = origin;
      _retryCredentials = credentials;
      _preparedOrigin = null;
      _setState(SessionState.signedIn);
      await onResumeUploads?.call();
    } on ApiException catch (error) {
      if (generation != _generation) return;
      if (restoring && error.expiresSession) {
        try {
          await vault.clear();
        } catch (_) {
          // Session remains expired and cannot use the rejected credential.
        }
        _retryCredentials = null;
        _setState(
          SessionState.expired,
          error: 'Your saved Suchi token is no longer valid.',
          requestId: error.requestId,
        );
      } else {
        _setState(
          SessionState.signedOut,
          error: error.message,
          requestId: error.requestId,
        );
      }
    } catch (_) {
      if (generation != _generation) return;
      _setState(
        SessionState.signedOut,
        error: 'This device could not verify the Suchi server.',
      );
    } finally {
      client?.close();
    }
  }

  void _setState(SessionState state, {String? error, String? requestId}) {
    _state = state;
    _errorMessage = error;
    _requestId = requestId;
    notifyListeners();
  }

  void _closeClient() {
    _client?.close();
    _client = null;
  }

  @override
  void dispose() {
    ++_generation;
    _closeClient();
    super.dispose();
  }
}
