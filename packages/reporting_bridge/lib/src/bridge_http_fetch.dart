import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'bridge_runtime_error.dart';

typedef BridgeDownloadProgress =
    void Function(int receivedBytes, int? totalBytes);

/// Shared GET + JSON helpers for Bridge HTTP callers.
class BridgeHttpFetch {
  BridgeHttpFetch({
    HttpClient Function()? httpClientFactory,
    this.timeout = const Duration(seconds: 8),
    this.closeClientAfterRequest = true,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final HttpClient Function() _httpClientFactory;
  final Duration timeout;
  final bool closeClientAfterRequest;

  Future<List<int>> getBytes(
    Uri uri, {
    required Map<String, String> headers,
    BridgeDownloadProgress? onProgress,
  }) async {
    final client = _httpClientFactory();
    client.connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>().timeout(timeout);
        throw BridgeRuntimeException(
          BridgeRuntimeErrorCodes.runtimeSessionInvalid,
          'HTTP ${response.statusCode} while requesting $uri.',
        );
      }

      final totalBytes = response.contentLength >= 0
          ? response.contentLength
          : null;
      final bytes = <int>[];
      var receivedBytes = 0;
      onProgress?.call(receivedBytes, totalBytes);
      await for (final chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(receivedBytes, totalBytes);
      }
      return bytes;
    } on TimeoutException {
      throw BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Request timed out: $uri',
      );
    } on BridgeRuntimeException {
      rethrow;
    } catch (error) {
      throw BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Request failed ($uri): $error',
      );
    } finally {
      if (closeClientAfterRequest) client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> getJsonObject(
    Uri uri, {
    required Map<String, String> headers,
    required String notValidJsonMessage,
  }) async {
    final bytes = await getBytes(uri, headers: headers);
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    throw BridgeRuntimeException(
      BridgeRuntimeErrorCodes.runtimeSessionInvalid,
      notValidJsonMessage,
    );
  }
}

/// Unwraps `payload['data']` when it is a Map; otherwise returns [envelope].
Map<String, dynamic> unwrapBridgeEnvelopeData(Map<String, dynamic> envelope) {
  final rawData = envelope['data'];
  if (rawData is Map<String, dynamic>) {
    return rawData;
  }
  if (rawData is Map) {
    return Map<String, dynamic>.from(rawData);
  }
  return envelope;
}
