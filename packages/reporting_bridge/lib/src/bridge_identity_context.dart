final class BridgeIdentityContext {
  BridgeIdentityContext({String? branchId, String? userId, String? systemUnit})
    : branchId = _trimmedOrNull(branchId),
      userId = _trimmedOrNull(userId),
      systemUnit = _trimmedOrNull(systemUnit);

  final String? branchId;
  final String? userId;
  final String? systemUnit;

  bool get isEmpty => branchId == null && userId == null && systemUnit == null;

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (userId != null) 'userId': userId,
    if (systemUnit != null) 'systemUnit': systemUnit,
    if (branchId != null) 'branchId': branchId,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BridgeIdentityContext &&
          other.branchId == branchId &&
          other.userId == userId &&
          other.systemUnit == systemUnit;

  @override
  int get hashCode => Object.hash(branchId, userId, systemUnit);
}

String? _trimmedOrNull(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
