#!/bin/bash
# Mobile shell checks; no hardware or macOS application target.
set -euo pipefail
repository_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$(mktemp -d /tmp/gamecore-foundation-verification.XXXXXX)}"
case "$output_dir" in /*) ;; *) echo 'Output directory must be absolute.' >&2; exit 2 ;; esac
mkdir -p "$output_dir"
cd "$repository_dir"
xcodebuild -version
python3 scripts/generate-project.py --check
python3 scripts/check-foundation.py
swift test --package-path Packages/GameCore --scratch-path "$output_dir/core" 2>&1 | tee "$output_dir/core-tests.log"
swift test --package-path Packages/GamePlatform --scratch-path "$output_dir/platform" 2>&1 | tee "$output_dir/platform-tests.log"
swift test --package-path Games/DevelopmentContent --scratch-path "$output_dir/content" 2>&1 | tee "$output_dir/content-tests.log"
swift run --package-path Games/DevelopmentContent --scratch-path "$output_dir/content" content-validator Games/DevelopmentContent/Sources/DevelopmentContent/Resources 2>&1 | tee "$output_dir/content-validation.log"
python3 scripts/test-content-cli.py "$output_dir/content/debug/content-validator" | tee "$output_dir/content-invalid-fixtures.log"
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
echo 'Package logic tests passed; app-hosted and UI tests run via scripts/test-mobile.sh.'
