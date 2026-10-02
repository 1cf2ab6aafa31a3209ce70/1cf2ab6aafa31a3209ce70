#!/bin/bash
# Static source check for accidental persistence, transport, or analytics in the disposable probe.
set -euo pipefail
experiment_dir="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$experiment_dir/Sources"
if ! command -v rg >/dev/null; then
  echo 'Privacy scan requires ripgrep (rg).' >&2
  exit 2
fi
if rg -n '(URLSession|NWConnection|import (Network|Firebase|Sentry|Telemetry)|UserDefaults|FileHandle|write\(to:|SwiftData|CoreData|OSLog|Logger\()' "$source_dir"; then
  echo 'Review matched APIs before accepting this local-only sample.' >&2
  exit 1
fi
echo 'Static scan passed: no listed network, persistence, or telemetry APIs in sample sources.'
echo 'This limited source scan is not a runtime network audit.'
