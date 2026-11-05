#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v openlane &>/dev/null; then
  printf '%s\n' "OpenLane is not installed in PATH. Install OpenLane and PDK sky130A before running ASIC tapeout flow."
  exit 0
fi
openlane openlane/config.json
