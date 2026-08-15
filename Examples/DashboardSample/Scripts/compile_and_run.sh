#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME=DurableJobsDashboardSample

pkill -x "$APP_NAME" 2>/dev/null || true

if [[ ${1:-} == "--test" ]]; then
  swift test --package-path "$ROOT"
fi

"$ROOT/Scripts/package_app.sh" debug
open -n "$ROOT/${APP_NAME}.app"
