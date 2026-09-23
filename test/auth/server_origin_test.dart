import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_mobile/auth/server_origin.dart';

void main() {
  group('ServerOrigin', () {
    test('accepts HTTPS origins and removes the root slash', () {
      expect(
        ServerOrigin.parse('https://SUCHI.example.com:8443/').toString(),
        'https://suchi.example.com:8443',
      );
    });

    test('accepts only explicit local HTTP origins', () {
      const accepted = [
        'http://localhost:8000',
        'http://127.0.0.1:8000',
        'http://10.1.2.3',
        'http://172.31.255.1',
        'http://192.168.4.2',
        'http://[::1]:8000',
        'http://[fd00::12]',
      ];
      for (final value in accepted) {
        expect(ServerOrigin.parse(value), isA<Uri>(), reason: value);
      }
    });

    test('rejects public, DNS, link-local, and lookalike HTTP origins', () {
      const rejected = [
        'http://suchi.example.com',
        'http://printer.local',
        'http://localhost.example.com',
        'http://8.8.8.8',
        'http://169.254.1.1',
        'http://[fe80::1]',
        'http://172.32.0.1',
        'http://192.169.0.1',
      ];
      for (final value in rejected) {
        expect(
          () => ServerOrigin.parse(value),
          throwsA(isA<ServerOriginException>()),
          reason: value,
        );
      }
    });

    test('rejects credentials, paths, queries, fragments, and whitespace', () {
      const rejected = [
        'https://user:pass@suchi.example.com',
        'https://suchi.example.com/subpath',
        'https://suchi.example.com?token=secret',
        'https://suchi.example.com/#fragment',
        ' https://suchi.example.com',
        'https://suchi.example.com\n',
        'ftp://suchi.example.com',
        'suchi.example.com',
      ];
      for (final value in rejected) {
        expect(
          () => ServerOrigin.parse(value),
          throwsA(isA<ServerOriginException>()),
          reason: value,
        );
      }
    });
  });
}
