#!/bin/bash
# Mobile shell checks for every title manifest; no hardware or macOS application target.
set -euo pipefail
repository_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$(mktemp -d /tmp/gamecore-foundation-verification.XXXXXX)}"
case "$output_dir" in /*) ;; *) echo 'Output directory must be absolute.' >&2; exit 2 ;; esac
mkdir -p "$output_dir"
cd "$repository_dir"
xcodebuild -version
targets="$(python3 scripts/titles.py targets)"
content_packages="$(python3 scripts/titles.py content-packages)"
python3 scripts/generate-project.py --check
python3 scripts/check-foundation.py
swift test --package-path Packages/GameCore --scratch-path "$output_dir/core" 2>&1 | tee "$output_dir/core-tests.log"
swift test --package-path Packages/GamePlatform --scratch-path "$output_dir/platform" 2>&1 | tee "$output_dir/platform-tests.log"
for package in $content_packages; do
  name="$(basename "$package")"
  scratch="$output_dir/content-$name"
  swift test --package-path "$package" --scratch-path "$scratch" 2>&1 | tee "$output_dir/$name-tests.log"
  swift run --package-path "$package" --scratch-path "$scratch" "${name}Validator" "$package/Sources/$name/Resources" 2>&1 | tee "$output_dir/$name-validation.log"
  # A content package may add its own adversarial checks of the real validator binary.
  if [ -f "$package/test-content-cli.py" ]; then
    python3 "$package/test-content-cli.py" "$scratch/debug/${name}Validator" | tee "$output_dir/$name-invalid-fixtures.log"
  fi
done
python3 scripts/test-required-reason-check.py | tee "$output_dir/required-reason-check-tests.log"
for target in $targets; do
  for configuration in Debug Release; do
    xcodebuild -workspace GameCore.xcworkspace -scheme "$target" \
      -configuration "$configuration" -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$output_dir/simulator-$configuration" \
      CODE_SIGNING_ALLOWED=NO build > "$output_dir/$target-simulator-$configuration.log" 2>&1 || {
        tail -60 "$output_dir/$target-simulator-$configuration.log"; exit 1;
      }
    echo "$target $configuration iOS Simulator build passed"
  done
  xcodebuild -workspace GameCore.xcworkspace -scheme "$target" \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath "$output_dir/ios-Release" CODE_SIGNING_ALLOWED=NO build \
    > "$output_dir/$target-ios-Release.log" 2>&1 || { tail -60 "$output_dir/$target-ios-Release.log"; exit 1; }
  echo "$target Release iOS SDK build passed (unsigned; no physical-device run)"
  # The shipped binary's required-reason API references must match its privacy manifest.
  python3 scripts/check-required-reason-apis.py "$output_dir/ios-Release/Build/Products/Release-iphoneos/$target.app" \
    > "$output_dir/$target-required-reason-apis.log" || { cat "$output_dir/$target-required-reason-apis.log"; exit 1; }
  tail -1 "$output_dir/$target-required-reason-apis.log"
done
echo "Verification passed: $output_dir"
echo 'Package logic tests passed; app-hosted and UI tests run via scripts/test-mobile.sh.'
