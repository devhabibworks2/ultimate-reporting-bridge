import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'bridge_cache_namespace.dart';
import 'bridge_template_sync.dart';

/// Result from the configured URB Backend; never from the original image host.
final class BridgeImageProxyRelayResponse {
  const BridgeImageProxyRelayResponse({
    required this.statusCode,
    required this.contentType,
    required this.bytes,
  });

  final int statusCode;
  final String contentType;
  final Uint8List bytes;
}

/// Isolated, authenticated Backend relay for the same-origin Presenter route.
class BridgeImageProxyRelay {
  BridgeImageProxyRelay({
    required Uri apiBaseUrl,
    required Map<String, String> headers,
    HttpClient Function()? httpClientFactory,
    this.timeout = const Duration(seconds: 8),
  }) : _apiBaseUrl = apiBaseUrl,
       _headers = Map<String, String>.unmodifiable(
         filterPresenterBridgeHeaders(headers),
       ),
       _httpClientFactory = httpClientFactory ?? HttpClient.new {
    if (!_httpUri(apiBaseUrl) ||
        apiBaseUrl.userInfo.isNotEmpty ||
        apiBaseUrl.hasQuery ||
        apiBaseUrl.hasFragment) {
      throw ArgumentError.value(
        apiBaseUrl,
        'apiBaseUrl',
        'Invalid Backend URL',
      );
    }
  }

  static const int maxResponseBytes = 5 * 1024 * 1024;
  static const Set<String> _imageMimes = <String>{
    'image/png',
    'image/jpeg',
    'image/webp',
  };

  final Uri _apiBaseUrl;
  final Map<String, String> _headers;
  final HttpClient Function() _httpClientFactory;
  final Duration timeout;

  Future<BridgeImageProxyRelayResponse> fetch(Uri sourceUri) async {
    if (!_httpUri(sourceUri) || sourceUri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        sourceUri,
        'sourceUri',
        'HTTP(S) image URL required',
      );
    }
    final backendUri = resolveBridgeApiRoute(
      _apiBaseUrl,
      'image-proxy',
    ).replace(queryParameters: <String, String>{'url': sourceUri.toString()});
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(backendUri).timeout(timeout);
      request.followRedirects = false;
      for (final entry in _headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Backend image proxy request failed',
          uri: backendUri,
        );
      }
      final mime = response.headers.contentType?.mimeType.toLowerCase();
      if (mime == null || !_imageMimes.contains(mime)) {
        throw const FormatException('Backend returned unsupported image type');
      }
      if (response.contentLength > maxResponseBytes) {
        throw const FormatException('Backend image exceeds maximum size');
      }
      final data = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in response.timeout(timeout)) {
        length += chunk.length;
        if (length > maxResponseBytes) {
          throw const FormatException('Backend image exceeds maximum size');
        }
        data.add(chunk);
      }
      if (length == 0) {
        throw const FormatException('Backend returned an empty image');
      }
      return BridgeImageProxyRelayResponse(
        statusCode: response.statusCode,
        contentType: mime,
        bytes: data.takeBytes(),
      );
    } finally {
      client.close(force: true);
    }
  }

  static bool _httpUri(Uri uri) =>
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.hasAuthority &&
      uri.host.isNotEmpty;
}
