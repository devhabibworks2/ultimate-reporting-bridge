final class ReportIdentity {
  const ReportIdentity({this.userId, this.branchId, this.systemUnit});

  /// Trims surrounding whitespace and drops empty identity parts.
  factory ReportIdentity.normalized({
    String? userId,
    String? branchId,
    String? systemUnit,
  }) => ReportIdentity(
    userId: _trimmedOrNull(userId),
    branchId: _trimmedOrNull(branchId),
    systemUnit: _trimmedOrNull(systemUnit),
  );

  final String? userId;
  final String? branchId;
  final String? systemUnit;

  bool get isEmpty => userId == null && branchId == null && systemUnit == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportIdentity &&
          other.userId == userId &&
          other.branchId == branchId &&
          other.systemUnit == systemUnit;

  @override
  int get hashCode => Object.hash(userId, branchId, systemUnit);
}

String? _trimmedOrNull(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
