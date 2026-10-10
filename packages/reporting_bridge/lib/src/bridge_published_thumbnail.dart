/// A validated reference to an image already stored for a published version.
///
/// This value describes availability only. It never requests or creates bytes.
final class BridgePublishedThumbnail {
  const BridgePublishedThumbnail._({
    required this.versionNo,
    required this.contentHash,
    required this.mimeType,
    required this.available,
  });

  static const String pngMimeType = 'image/png';
  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

  final int versionNo;
  final String contentHash;
  final String mimeType;
  final bool available;

  /// Parses a well-formed descriptor, or returns null for legacy/invalid data.
  static BridgePublishedThumbnail? fromMap(Object? value) {
    if (value is! Map) return null;

    final versionNo = value['versionNo'];
    final contentHash = value['contentHash'];
    final mimeType = value['mimeType'];
    final available = value['available'];
    if (versionNo is! int || versionNo <= 0) return null;
    if (contentHash is! String || !_sha256Pattern.hasMatch(contentHash)) {
      return null;
    }
    if (mimeType != pngMimeType || available is! bool) return null;

    return BridgePublishedThumbnail._(
      versionNo: versionNo,
      contentHash: contentHash,
      mimeType: pngMimeType,
      available: available,
    );
  }

  Map<String, Object> toMap() => <String, Object>{
    'versionNo': versionNo,
    'contentHash': contentHash,
    'mimeType': mimeType,
    'available': available,
  };
}
