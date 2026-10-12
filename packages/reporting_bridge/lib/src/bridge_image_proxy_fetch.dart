import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Fetch bounded image content from public web destinations only.
/// Never carries host authorization, user cookies or client request headers.
Future<Uint8List?> fetchBridgePublicImage(
  Uri uri, {
  bool allowInvalidHttpsCertificates = true,
}) async {
  if (!isAllowedBridgeImageUrl(uri)) return null;
  final List<InternetAddress> addresses;
  try {
    addresses = await InternetAddress.lookup(
      uri.host,
    ).timeout(const Duration(seconds: 5));
  } on Object {
    return null;
  }
  // Reject mixed private/public DNS answers. Pin the chosen approved address.
  if (addresses.isEmpty || addresses.any((ip) => !_isPublicAddress(ip))) {
    return null;
  }
  final pinned = addresses.first;
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 5);
  client.findProxy = (_) => 'DIRECT';
  client.connectionFactory = (url, proxyHost, proxyPort) async {
    if (proxyHost != null || proxyPort != null) {
      throw const SocketException('Proxy connections disabled');
    }
    final tcpTask = await Socket.startConnect(pinned, uri.port);
    Future<Socket> connection = tcpTask.socket;
    if (uri.isScheme('https')) {
      connection = connection.then(
        (socket) => SecureSocket.secure(
          socket,
          host: uri.host,
          onBadCertificate: (_) => allowUntrustedImageCertificate(
            uri,
            allowInvalidHttpsCertificates: allowInvalidHttpsCertificates,
          ),
        ),
      );
    }
    return ConnectionTask.fromSocket<Socket>(connection, tcpTask.cancel);
  };
  try {
    return await _downloadImage(
      client,
      uri,
    ).timeout(const Duration(seconds: 15));
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Certificate verification is optional for remote images only.
/// Defaults to permitting invalid HTTPS certificates for image fetching.
/// Set [allowInvalidHttpsCertificates] to false to require valid TLS.
/// This is not used for authentication or backend API calls.
/// Untrusted certificates may allow images to be replaced in transit.
bool allowUntrustedImageCertificate(
  Uri uri, {
  bool allowInvalidHttpsCertificates = true,
}) {
  return uri.isScheme('https') &&
      isAllowedBridgeImageUrl(uri) &&
      allowInvalidHttpsCertificates;
}

bool isAllowedBridgeImageUrl(Uri uri) {
  if ((uri.scheme != 'http' && uri.scheme != 'https') ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return false;
  }
  if (uri.hasPort && uri.port != (uri.isScheme('https') ? 443 : 80)) {
    return false;
  }
  final host = uri.host.toLowerCase();
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.internal') ||
      host.endsWith('.test') ||
      host.endsWith('.invalid') ||
      host.endsWith('.example') ||
      !host.contains('.') ||
      InternetAddress.tryParse(host) != null) {
    return false;
  }
  return true;
}

bool _isPublicAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return false;
  }
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv6) {
    if (b.length != 16 || (b[0] & 0xe0) != 0x20) return false;
    return !(b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8);
  }
  if (b.length != 4) return false;
  final a = b[0], n = b[1], c = b[2];
  return a != 0 &&
      a != 10 &&
      a != 127 &&
      a < 224 &&
      !(a == 100 && n >= 64 && n <= 127) &&
      !(a == 169 && n == 254) &&
      !(a == 172 && n >= 16 && n <= 31) &&
      !(a == 192 &&
          (n == 168 ||
              n == 0 && c == 0 ||
              n == 0 && c == 2 ||
              n == 88 && c == 99)) &&
      !(a == 198 && (n == 18 || n == 19 || n == 51 && c == 100)) &&
      !(a == 203 && n == 0 && c == 113);
}

Future<Uint8List?> _downloadImage(HttpClient client, Uri uri) async {
  const maxBytes = 5 * 1024 * 1024;
  final request = await client.getUrl(uri);
  request.followRedirects = false;
  request.headers.set(
    HttpHeaders.acceptHeader,
    'image/png, image/jpeg, image/webp',
  );
  final response = await request.close();
  // Do not drain rejected oversized responses: abort via client.close(force)
  // so we never download untrusted multi-megabyte content needlessly.
  if (response.statusCode != HttpStatus.ok ||
      response.contentLength > maxBytes) {
    return null;
  }
  final body = BytesBuilder(copy: false);
  var count = 0;
  await for (final chunk in response) {
    count += chunk.length;
    if (count > maxBytes) return null;
    body.add(chunk);
  }
  final bytes = body.takeBytes();
  return bridgeImageMime(bytes) == null ? null : bytes;
}

String? bridgeImageMime(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71 &&
      bytes[4] == 13 &&
      bytes[5] == 10 &&
      bytes[6] == 26 &&
      bytes[7] == 10) {
    return 'image/png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255) {
    return 'image/jpeg';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  return null;
}
