import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_models.dart';
import 'server_origin.dart';

final class StoredCredentials {
  const StoredCredentials({
    required this.origin,
    required this.token,
    this.userSnapshot,
  });

  final Uri origin;
  final String token;
  final UserSelf? userSnapshot;

  StoredCredentials withUserSnapshot(UserSelf snapshot) =>
      StoredCredentials(origin: origin, token: token, userSnapshot: snapshot);
}

abstract interface class CredentialVault {
  Future<StoredCredentials?> read();

  Future<void> save(StoredCredentials credentials);

  Future<void> clear();
}

final class SecureCredentialVault implements CredentialVault {
  SecureCredentialVault({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
              synchronizable: false,
            ),
            aOptions: AndroidOptions(),
          );

  static const _key = 'suchi.mobile.credentials.v1';
  static const _maximumRecordBytes = 64 * 1024;
  static const _snapshotKeys = {
    'kind',
    'user_id',
    'email',
    'display_name',
    'instance_host',
    'role',
    'authn_by',
    'avatar_url',
    'system_id',
    'system_name',
    'system_code',
    'capabilities',
    'scopes',
  };

  final FlutterSecureStorage _storage;

  @override
  Future<StoredCredentials?> read() async {
    final encoded = await _storage.read(key: _key);
    if (encoded == null) return null;
    if (encoded.length > _maximumRecordBytes ||
        utf8.encode(encoded).length > _maximumRecordBytes) {
      await clear();
      return null;
    }
    try {
      final value = jsonDecode(encoded);
      if (value is! Map<String, dynamic> ||
          value.keys.any(
            (key) => !const {'origin', 'token', 'user_snapshot'}.contains(key),
          )) {
        throw const FormatException();
      }
      final origin = value['origin'];
      final token = value['token'];
      if (origin is! String ||
          token is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
        throw const FormatException();
      }
      final snapshotValue = value['user_snapshot'];
      if (snapshotValue != null &&
          (snapshotValue is! Map<String, dynamic> ||
              snapshotValue.length != _snapshotKeys.length ||
              !snapshotValue.keys.toSet().containsAll(_snapshotKeys))) {
        throw const FormatException();
      }
      final snapshot = snapshotValue == null
          ? null
          : UserSelf.fromJson(snapshotValue);
      if (snapshot != null && !snapshot.hasMobileScopes) {
        throw const FormatException();
      }
      final uri = ServerOrigin.canonicalizeStoredIdentity(origin);
      return StoredCredentials(
        origin: uri,
        token: token,
        userSnapshot: snapshot,
      );
    } on ApiFormatException catch (_) {
      await clear();
      return null;
    } on FormatException catch (_) {
      await clear();
      return null;
    } on ServerOriginException catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(StoredCredentials credentials) {
    final encoded = jsonEncode({
      'origin': credentials.origin.toString(),
      'token': credentials.token,
      if (credentials.userSnapshot case final snapshot?)
        'user_snapshot': snapshot.toJson(),
    });
    if (encoded.length > _maximumRecordBytes ||
        utf8.encode(encoded).length > _maximumRecordBytes) {
      throw const FormatException('Credential record exceeds its size limit.');
    }
    return _storage.write(key: _key, value: encoded);
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
