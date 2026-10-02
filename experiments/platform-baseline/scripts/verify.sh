#!/bin/bash
# Reproduce logic tests, static privacy scan, and unsigned host/simulator builds.
# Usage: ./scripts/verify.sh [absolute-output-directory]
set -euo pipefail
experiment_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-/tmp/gamecore-platform-baseline-verification}"
case "$output_dir" in
  /*) ;;
  *) echo 'Output directory must be absolute.' >&2; exit 2 ;;
esac
mkdir -p "$output_dir"
cd "$experiment_dir"
if [[ ! -d PlatformBaseline.xcodeproj ]]; then
  echo 'Generate PlatformBaseline.xcodeproj following README.md before running verification.' >&2
  exit 2
fi
CLANG_MODULE_CACHE_PATH="$output_dir/swift-module-cache" swift test --scratch-path "$output_dir/swift-build" \
  -Xswiftc -module-cache-path -Xswiftc "$output_dir/swift-module-cache"
./scripts/privacy-scan.sh
for configuration in Debug Release; do
  xcodebuild -project PlatformBaseline.xcodeproj -scheme PlatformBaseline \
    -configuration "$configuration" -destination 'platform=macOS' \
    -derivedDataPath "$output_dir/macos-$configuration" \
    CODE_SIGNING_ALLOWED=NO build
  xcodebuild -project PlatformBaseline.xcodeproj -scheme PlatformBaseline \
    -configuration "$configuration" -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$output_dir/simulator-$configuration" \
    CODE_SIGNING_ALLOWED=NO build
done
echo "Verification passed. Build products: $output_dir"
echo 'These builds do not measure acceptance-device performance or execute UI tests.'
