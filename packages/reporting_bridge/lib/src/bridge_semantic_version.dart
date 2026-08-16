/// Small dependency-free semantic version value used by Bridge compatibility
/// checks. Build metadata does not affect ordering.
final class BridgeSemanticVersion implements Comparable<BridgeSemanticVersion> {
  const BridgeSemanticVersion._({
    required this.major,
    required this.minor,
    required this.patch,
    required this.preRelease,
  });

  final int major;
  final int minor;
  final int patch;
  final List<String> preRelease;

  static BridgeSemanticVersion? tryParse(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;

    final match = RegExp(
      r'^[vV]?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
    ).firstMatch(value);
    if (match == null) return null;

    final major = int.tryParse(match.group(1)!);
    final minor = int.tryParse(match.group(2)!);
    final patch = int.tryParse(match.group(3)!);
    if (major == null || minor == null || patch == null) return null;

    final rawPreRelease = match.group(4);
    final preRelease = rawPreRelease == null
        ? const <String>[]
        : List<String>.unmodifiable(rawPreRelease.split('.'));

    return BridgeSemanticVersion._(
      major: major,
      minor: minor,
      patch: patch,
      preRelease: preRelease,
    );
  }

  @override
  int compareTo(BridgeSemanticVersion other) {
    final core = _compareCore(other);
    if (core != 0) return core;

    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;

    final length = preRelease.length > other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var index = 0; index < length; index++) {
      if (index >= preRelease.length) return -1;
      if (index >= other.preRelease.length) return 1;

      final left = preRelease[index];
      final right = other.preRelease[index];
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);

      if (leftNumber != null && rightNumber != null) {
        final result = leftNumber.compareTo(rightNumber);
        if (result != 0) return result;
        continue;
      }
      if (leftNumber != null) return -1;
      if (rightNumber != null) return 1;

      final result = left.compareTo(right);
      if (result != 0) return result;
    }
    return 0;
  }

  int _compareCore(BridgeSemanticVersion other) {
    final majorResult = major.compareTo(other.major);
    if (majorResult != 0) return majorResult;
    final minorResult = minor.compareTo(other.minor);
    if (minorResult != 0) return minorResult;
    return patch.compareTo(other.patch);
  }

  @override
  String toString() {
    final core = '$major.$minor.$patch';
    return preRelease.isEmpty ? core : '$core-${preRelease.join('.')}';
  }
}
