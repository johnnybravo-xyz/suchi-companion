import 'package:flutter_test/flutter_test.dart';
import 'package:suchi_companion/auth/pairing_link.dart';

const _code =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _link =
    'suchi://pair?v=1&server=https%3A%2F%2Fsuchi.example.com&code=$_code';

void main() {
  test('reads only the server and one-time code from a pairing link', () {
    final pairing = PairingLink.parse(_link);
    expect(pairing.origin.toString(), 'https://suchi.example.com');
    expect(pairing.code, _code);
    expect(pairing.toString(), isNot(contains(_code)));
  });

  test('applies the existing local HTTP origin rules', () {
    final pairing = PairingLink.parse(
      _link.replaceFirst(
        'https%3A%2F%2Fsuchi.example.com',
        'http%3A%2F%2F192.168.1.4%3A8000',
      ),
    );
    expect(pairing.origin.toString(), 'http://192.168.1.4:8000');
  });

  for (final invalid in <String, String>{
    'web URL': _link.replaceFirst('suchi:', 'https:'),
    'wrong action': _link.replaceFirst('pair?', 'share?'),
    'nonempty path': _link.replaceFirst('pair?', 'pair/?'),
    'userinfo': _link.replaceFirst('pair?', 'user@pair?'),
    'empty userinfo': _link.replaceFirst('pair?', '@pair?'),
    'port': _link.replaceFirst('pair?', 'pair:123?'),
    'fragment': '$_link#',
    'unknown version': _link.replaceFirst('v=1', 'v=2'),
    'duplicate version': '$_link&v=1',
    'duplicate server': '$_link&server=https%3A%2F%2Fevil.example',
    'duplicate code': '$_link&code=$_code',
    'unknown parameter': '$_link&name=mobile',
    'missing code': _link.replaceFirst('&code=$_code', ''),
    'uppercase code': _link.replaceFirst(_code, _code.toUpperCase()),
    'short code': _link.replaceFirst(_code, 'abc'),
    'server credentials': _link.replaceFirst(
      'suchi.example.com',
      'user%3Asecret%40suchi.example.com',
    ),
    'server path': _link.replaceFirst(
      'suchi.example.com',
      'suchi.example.com%2Farchive',
    ),
    'public HTTP': _link.replaceFirst('https%3A', 'http%3A'),
    'malformed encoding': _link.replaceFirst('server=https', 'server=%xxhttps'),
  }.entries) {
    test('rejects ${invalid.key} without exposing the code', () {
      expect(
        () => PairingLink.parse(invalid.value),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'safe message',
            isNot(contains(_code)),
          ),
        ),
      );
    });
  }
}
