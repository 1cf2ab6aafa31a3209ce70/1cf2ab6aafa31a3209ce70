#!/bin/bash
# Read-only inventory. Does not boot, restart, or shut down any simulator or device.
set -euo pipefail
xcodebuild -version
sw_vers
xcrun simctl list devices available
xcrun devicectl list devices
