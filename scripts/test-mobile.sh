#!/bin/bash
set -euo pipefail
repository_dir="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$repository_dir/scripts/run-mobile-tests.py" "$@"
