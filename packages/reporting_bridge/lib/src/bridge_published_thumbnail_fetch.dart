import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'bridge_cache_namespace.dart';
import 'bridge_published_thumbnail.dart';
import 'bridge_runtime_error.dart';
import 'bridge_template_sync.dart' show filterPresenterBridgeHeaders;

abstract final class BridgePublishedThumbnailFetchErrorCodes {
  static const String requestFailed = 'PUBLISHED_THUMBNAIL_REQUEST_FAILED';
  static const String responseInvalid = 'PUBLISHED_THUMBNAIL_RESPONSE_INVALID';
  static const String authorizationFailed =
      'PUBLISHED_THUMBNAIL_AUTHORIZATION_FAILED';
}

const int _maxThumbnailBytes = 2 * 1024 * 1024;
const List<int> _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

/// Retrieves already-stored bytes for the exact published version.
///
/// This transport is GET-only and has no rendering, repair, or publish path.
Future<Uint8List?> fetchPublishedThumbnail({
  required Uri apiBase,
  required String systemCode,
  required String templateCode,
  required BridgePublishedThumbnail descriptor,
  required Map<String, String> headers,
  Future<void>? cancellation,
  HttpClient Function()? httpClientFactory,
}) async {
  if (!descriptor.available) return null;

  final uri = resolveBridgeApiRoute(apiBase, 'presenter/template-thumbnails')
      .replace(
        queryParameters: <String, String>{
          'templateCode': templateCode,
          'systemCode': systemCode,
          'versionNo': descriptor.versionNo.toString(),
          'contentHash': descriptor.contentHash,
        },
      );
  // The injected factory may return a shared client owned by BridgeClient.
  // Never close shared clients when an individual thumbnail is cancelled.
  final ownsClient = httpClientFactory == null;
  final client = (httpClientFactory ?? HttpClient.new)();
  if (ownsClient) client.connectionTimeout = const Duration(seconds: 8);
  HttpClientRequest? activeRequest;
  var cancelled = false;
  if (cancellation != null) {
    unawaited(
      cancellation.then((_) {
        cancelled = true;
        activeRequest?.abort();
        if (ownsClient) client.close(force: true);
      }),
    );
  }

  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 8));
    activeRequest = request;
    if (cancelled) {
      request.abort();
      throw const BridgeRuntimeException(
        BridgePublishedThumbnailFetchErrorCodes.requestFailed,
        'Published thumbnail request was cancelled.',
      );
    }
    for (final entry in filterPresenterBridgeHeaders(headers).entries) {
      request.headers.set(entry.key, entry.value);
    }
    final response = await request.close().timeout(const Duration(seconds: 8));

    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden) {
      throw const BridgeRuntimeException(
        BridgePublishedThumbnailFetchErrorCodes.authorizationFailed,
        'Published thumbnail retrieval is not authorized.',
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      throw BridgeRuntimeException(
        BridgePublishedThumbnailFetchErrorCodes.requestFailed,
        'Published thumbnail retrieval failed with HTTP ${response.statusCode}.',
      );
    }

    final contentType = response.headers.value(HttpHeaders.contentTypeHeader);
    if (_canonicalMimeType(contentType) !=
        BridgePublishedThumbnail.pngMimeType) {
      throw const BridgeRuntimeException(
        BridgePublishedThumbnailFetchErrorCodes.responseInvalid,
        'Published thumbnail response has an unsupported MIME type.',
      );
    }
    if (response.contentLength > _maxThumbnailBytes) {
      throw const BridgeRuntimeException(
        BridgePublishedThumbnailFetchErrorCodes.responseInvalid,
        'Published thumbnail exceeds the 2 MiB limit.',
      );
    }

    final identityHash = response.headers.value('X-URB-Thumbnail-Content-Hash');
    final expectedBytesHash = response.headers.value(
      'X-URB-Thumbnail-Bytes-Sha256',
    );
    if (identityHash != descriptor.contentHash ||
        expectedBytesHash == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedBytesHash)) {
      throw const BridgeRuntimeException(
        BridgePublishedThumbnailFetchErrorCodes.responseInvalid,
        'Published thumbnail integrity headers are missing or mismatched.',
      );
    }

    final bytes = BytesBuilder(copy: false);
    var receivedBytes = 0;
    await for (final chunk in response.timeout(const Duration(seconds: 8))) {
      receivedBytes += chunk.length;
      if (receivedBytes > _maxThumbnailBytes) {
        throw const BridgeRuntimeException(
          BridgePublishedThumbnailFetchErrorCodes.responseInvalid,
          'Published thumbnail exceeds the 2 MiB limit.',
        );
      }
      bytes.add(chunk);
    }
    final result = bytes.takeBytes();

    if (!_hasPngSignature(result) ||
        sha256.convert(result).toString() != expectedBytesHash) {
      throw const BridgeRuntimeException(
        BridgePublishedThumbnailFetchErrorCodes.responseInvalid,
        'Published thumbnail bytes are corrupt or fail their checksum.',
      );
    }
    return result;
  } on BridgeRuntimeException {
    rethrow;
  } on Object catch (error) {
    throw BridgeRuntimeException(
      BridgePublishedThumbnailFetchErrorCodes.requestFailed,
      'Published thumbnail request failed: $error',
    );
  } finally {
    if (ownsClient) client.close(force: true);
  }
}

String? _canonicalMimeType(String? value) {
  if (value == null) return null;
  final separator = value.indexOf(';');
  return (separator < 0 ? value : value.substring(0, separator))
      .trim()
      .toLowerCase();
}

bool _hasPngSignature(List<int> bytes) {
  if (bytes.length < _pngSignature.length) return false;
  for (var index = 0; index < _pngSignature.length; index++) {
    if (bytes[index] != _pngSignature[index]) return false;
  }
  return true;
}
