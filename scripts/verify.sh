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
# Each release gate proves it refuses seeded violations before it judges the real builds.
for gate_test in foundation-check app-bundle-check app-capabilities-check localization-check \
                 asset-provenance-check reproducible-build-check; do
  python3 "scripts/test-$gate_test.py" | tee "$output_dir/$gate_test-tests.log"
done
# Release gates on the built bundles report every failure, then fail verification at the end.
gate_failures=""
release_gate() {
  local name="$1" log="$2"
  shift 2
  if "$@" > "$log" 2> "$log.err"; then
    tail -1 "$log"
  else
    cat "$log.err"
    gate_failures="$gate_failures $name"
  fi
}
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
  app="$output_dir/ios-Release/Build/Products/Release-iphoneos/$target.app"
  release_gate "$target-bundle" "$output_dir/$target-app-bundle.log" python3 scripts/check-app-bundle.py "$app"
  release_gate "$target-capabilities" "$output_dir/$target-app-capabilities.log" \
    python3 scripts/check-app-capabilities.py "$app"
  release_gate "$target-localization" "$output_dir/$target-localization.log" \
    python3 scripts/check-localization.py "Games/$target" --app "$app" \
    --stringsdata "$output_dir/ios-Release/Build/Intermediates.noindex/GameCore.build/Release-iphoneos/$target.build"
  release_gate "$target-provenance" "$output_dir/$target-asset-provenance.log" \
    python3 scripts/check-asset-provenance.py "$app"
done
# Reproducibility: rebuild every Release iOS app from a second clean derived-data directory. Its path
# has the same length as ios-Release because debug-map path lengths change the linker's LC_UUID.
rm -rf "$output_dir/ios-Rebuild"
for target in $targets; do
  xcodebuild -workspace GameCore.xcworkspace -scheme "$target" \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath "$output_dir/ios-Rebuild" CODE_SIGNING_ALLOWED=NO build \
    > "$output_dir/$target-ios-Rebuild.log" 2>&1 || { tail -60 "$output_dir/$target-ios-Rebuild.log"; exit 1; }
  release_gate "$target-reproducible" "$output_dir/$target-reproducible-build.log" \
    python3 scripts/check-reproducible-build.py "$output_dir/ios-Release/Build/Products/Release-iphoneos/$target.app" \
    "$output_dir/ios-Rebuild/Build/Products/Release-iphoneos/$target.app"
done
if [ -n "$gate_failures" ]; then
  echo "Release gates failed:$gate_failures (logs in $output_dir)" >&2
  exit 1
fi
echo "Verification passed: $output_dir"
echo 'Package logic tests passed; app-hosted and UI tests run via scripts/test-mobile.sh.'
