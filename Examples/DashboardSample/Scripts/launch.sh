#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/DurableQueuerDashboardSample.app"

if [[ ! -d "$APP" ]]; then
  echo "ERROR: Run ./Scripts/package_app.sh first." >&2
  exit 1
fi

open -n "$APP"
