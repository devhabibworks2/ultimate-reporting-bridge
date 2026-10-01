#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <legacy|modern>" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
fi

profile="$1"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$profile" in
  legacy)
    host_dir="$root/example/compatibility_host_legacy"
    ;;
  modern)
    host_dir="$root/example/compatibility_host_modern"
    ;;
  *)
    usage
    ;;
esac

cd "$host_dir"
rm -rf .dart_tool
rm -f pubspec.lock
flutter pub get
flutter analyze
flutter build apk --debug

echo "BRIDGE_HOST_COMPATIBILITY=PASS"
echo "HOST_PROFILE=$profile"
