#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if grep -RInE '(^|[^:])//|/\*|\*/' --include='*.sv' rtl tb formal; then
  printf '%s\n' 'Source policy violation'
  exit 1
fi
printf '%s\n' 'Source policy pass'
