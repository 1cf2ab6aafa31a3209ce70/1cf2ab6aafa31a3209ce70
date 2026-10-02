#!/bin/bash
# Mobile foundation only; no hardware or macOS application checks.
set -euo pipefail
repository_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$(mktemp -d /tmp/gamecore-foundation-verification.XXXXXX)}"
case "$output_dir" in /*) ;; *) echo 'Output directory must be absolute.' >&2; exit 2 ;; esac
mkdir -p "$output_dir"
cd "$repository_dir"
xcodebuild -version
python3 scripts/generate-project.py --check
python3 scripts/check-foundation.py
swift build --package-path Packages/GameCore --scratch-path "$output_dir/core" --build-tests
swift build --package-path Packages/GamePlatform --scratch-path "$output_dir/platform"
for configuration in Debug Release; do
  xcodebuild -workspace GameCore.xcworkspace -scheme DevelopmentTitle \
    -configuration "$configuration" -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$output_dir/simulator-$configuration" \
    CODE_SIGNING_ALLOWED=NO build > "$output_dir/simulator-$configuration.log" 2>&1 || {
      tail -60 "$output_dir/simulator-$configuration.log"; exit 1;
    }
  echo "$configuration iOS Simulator build passed"
done
xcodebuild -workspace GameCore.xcworkspace -scheme DevelopmentTitle \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$output_dir/ios-Release" CODE_SIGNING_ALLOWED=NO build \
  > "$output_dir/ios-Release.log" 2>&1 || { tail -60 "$output_dir/ios-Release.log"; exit 1; }
echo 'Release iOS SDK build passed (unsigned; no physical-device run)'
echo "Verification passed: $output_dir"
echo 'Core is empty: test-target compilation is verified; no runtime core tests exist yet.'
