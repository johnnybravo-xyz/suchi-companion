import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'server_origin.dart';

final class StoredCredentials {
  const StoredCredentials({required this.origin, required this.token});

  final Uri origin;
  final String token;
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

  final FlutterSecureStorage _storage;

  @override
  Future<StoredCredentials?> read() async {
    final encoded = await _storage.read(key: _key);
    if (encoded == null) return null;
    try {
      final value = jsonDecode(encoded);
      if (value is! Map<String, dynamic>) throw const FormatException();
      final origin = value['origin'];
      final token = value['token'];
      if (origin is! String || token is! String || token.isEmpty) {
        throw const FormatException();
      }
      final uri = ServerOrigin.parse(origin);
      return StoredCredentials(origin: uri, token: token);
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
    return _storage.write(
      key: _key,
      value: jsonEncode({
        'origin': credentials.origin.toString(),
        'token': credentials.token,
      }),
    );
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
