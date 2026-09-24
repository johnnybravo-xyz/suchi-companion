import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_mobile/api/api_models.dart';
import 'package:suchi_mobile/auth/credential_vault.dart';

const _key = 'suchi.mobile.credentials.v1';
const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('round-trips a verified user snapshot with the credential', () async {
    final vault = SecureCredentialVault();
    final snapshot = UserSelf.fromJson(
      jsonDecode(File('test/fixtures/api/v1/whoami.json').readAsStringSync()),
    );

    await vault.save(
      StoredCredentials(
        origin: Uri.parse('https://suchi.example.com'),
        token: _token,
        userSnapshot: snapshot,
      ),
    );
    final restored = await vault.read();

    expect(restored?.origin, Uri.parse('https://suchi.example.com'));
    expect(restored?.token, _token);
    expect(restored?.userSnapshot?.userId, 7);
    expect(restored?.userSnapshot?.systemId, 1);
    expect(restored?.userSnapshot?.scopes, [
      'documents:read',
      'documents:write',
    ]);
  });

  test(
    'reads legacy credentials without treating them as verified offline',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        _key: jsonEncode({
          'origin': 'https://suchi.example.com',
          'token': _token,
        }),
      });

      final restored = await SecureCredentialVault().read();

      expect(restored?.token, _token);
      expect(restored?.userSnapshot, isNull);
    },
  );

  test(
    'deletes malformed or under-scoped snapshots instead of trusting them',
    () async {
      final snapshot = jsonDecode(
        File('test/fixtures/api/v1/whoami.json').readAsStringSync(),
      ) as Map<String, dynamic>..['scopes'] = ['documents:read'];
      FlutterSecureStorage.setMockInitialValues({
        _key: jsonEncode({
          'origin': 'https://suchi.example.com',
          'token': _token,
          'user_snapshot': snapshot,
        }),
      });
      final vault = SecureCredentialVault();

      expect(await vault.read(), isNull);
      expect(await vault.read(), isNull);
    },
  );

  test(
    'deletes snapshots with fields the stored schema does not own',
    () async {
      final snapshot = jsonDecode(
        File('test/fixtures/api/v1/whoami.json').readAsStringSync(),
      ) as Map<String, dynamic>..['unexpected'] = true;
      FlutterSecureStorage.setMockInitialValues({
        _key: jsonEncode({
          'origin': 'https://suchi.example.com',
          'token': _token,
          'user_snapshot': snapshot,
        }),
      });

      expect(await SecureCredentialVault().read(), isNull);
    },
  );

  test('deletes an oversized credential record before decoding it', () async {
    FlutterSecureStorage.setMockInitialValues({
      _key: jsonEncode({
        'origin': 'https://suchi.example.com',
        'token': _token,
        'padding': 'x' * (64 * 1024),
      }),
    });

    expect(await SecureCredentialVault().read(), isNull);
  });
}
