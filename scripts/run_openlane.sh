#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v python3 &>/dev/null; then
  python3 scripts/floorplan_analyze.py --check-only
fi
if ! command -v openlane &>/dev/null; then
  printf '%s\n' "OpenLane is not installed in PATH. Install OpenLane 2 and PDK sky130A to run ASIC P&R on openlane/config.json and openlane/user_project_wrapper/config.json."
  exit 0
fi
openlane openlane/config.json
openlane openlane/user_project_wrapper/config.json
