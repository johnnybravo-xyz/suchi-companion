import 'dart:io';

final class ServerOriginException implements Exception {
  const ServerOriginException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class ServerOrigin {
  static Uri parse(String input) {
    final candidate = input.trim();
    if (candidate.isEmpty) {
      throw const ServerOriginException('Enter your Suchi server address.');
    }
    if (candidate != input || candidate.contains(RegExp(r'\s'))) {
      throw const ServerOriginException(
        'Server address cannot contain whitespace.',
      );
    }

    final Uri uri;
    try {
      uri = Uri.parse(candidate);
    } on FormatException {
      throw const ServerOriginException('Enter a valid server address.');
    }
    if (!uri.hasScheme || !uri.hasAuthority || uri.host.isEmpty) {
      throw const ServerOriginException(
        'Server address must include http:// or https://.',
      );
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw const ServerOriginException(
        'Server address must use HTTPS or approved local HTTP.',
      );
    }
    if (uri.userInfo.isNotEmpty) {
      throw const ServerOriginException(
        'Server address cannot contain a username or password.',
      );
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw const ServerOriginException(
        'Server address cannot contain a query or fragment.',
      );
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      throw const ServerOriginException(
        'Suchi must be hosted at the server address root.',
      );
    }
    if (uri.port == 0) {
      throw const ServerOriginException('Server port must be valid.');
    }

    if (uri.scheme == 'http' && !_isApprovedLocalHost(uri.host)) {
      throw const ServerOriginException(
        'HTTP is allowed only for localhost or a private literal IP address.',
      );
    }

    return Uri(
      scheme: uri.scheme,
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
    );
  }

  static bool _isApprovedLocalHost(String host) {
    if (host.toLowerCase() == 'localhost') return true;
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 127 ||
          bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168);
    }
    if (address.type == InternetAddressType.IPv6) {
      final loopback =
          bytes.take(15).every((byte) => byte == 0) && bytes[15] == 1;
      final uniqueLocal = (bytes[0] & 0xfe) == 0xfc;
      return loopback || uniqueLocal;
    }
    return false;
  }
}
