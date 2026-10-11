import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

// Identity and core image-store contracts. No thumbnail key or encryption.
final class TrustedThumbnailScope {
  TrustedThumbnailScope({
    required Uri apiBase,
    String? tenantId,
    String? userId,
    String? customerContext,
    this.cacheEnabled = true,
    required String systemCode,
    required String templateCode,
  }) : apiBase = normalizeBridgeApiBaseUrl(apiBase),
       tenantId = _optional(tenantId),
       userId = _optional(userId),
       customerContext = _optional(customerContext),
       systemCode = _required(systemCode, 'systemCode'),
       templateCode = _required(templateCode, 'templateCode');

  final Uri apiBase;

  /// Additional cache isolation only. Never required for a thumbnail GET.
  final String? tenantId;

  /// Existing report identity, when available; no new Host configuration.
  final String? userId;

  /// SHA-256 digest of the existing authorization context, never raw secrets.
  final String? customerContext;

  /// False when no authenticated isolation context is available.
  final bool cacheEnabled;
  final String systemCode;
  final String templateCode;

  String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode(<String, String>{
            'apiBase': apiBase.toString(),
            'tenantId': tenantId ?? '',
            'userId': userId ?? '',
            if (customerContext != null) 'customerContext': customerContext!,
            'systemCode': systemCode,
            'templateCode': templateCode,
          }),
        ),
      )
      .toString();

  String get identityFingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode(<String, String>{
            'apiBase': apiBase.toString(),
            'tenantId': tenantId ?? '',
            'userId': userId ?? '',
            if (customerContext != null) 'customerContext': customerContext!,
            'systemCode': systemCode,
          }),
        ),
      )
      .toString();

  TrustedThumbnailScope forTemplateCode(String value) => TrustedThumbnailScope(
    apiBase: apiBase,
    tenantId: tenantId,
    userId: userId,
    customerContext: customerContext,
    cacheEnabled: cacheEnabled,
    systemCode: systemCode,
    templateCode: value,
  );

  String associatedIdentity(BridgePublishedThumbnail ref) =>
      '$fingerprint:${ref.versionNo}:${ref.contentHash}:${ref.mimeType}';
}

abstract interface class PublishedThumbnailImageStore {
  Future<Uint8List?> read(
    TrustedThumbnailScope scope,
    BridgePublishedThumbnail ref,
  );
  Future<void> write(
    TrustedThumbnailScope scope,
    BridgePublishedThumbnail ref,
    Uint8List bytes,
  );
  Future<void> invalidateScope(TrustedThumbnailScope scope);
}

String? _optional(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _required(String value, String name) {
  final result = value.trim();
  if (result.isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
  return result;
}
