#!/usr/bin/env bash
set -euo pipefail
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"
if grep -RInE '(^|[^:])//|/\*|\*/' --include='*.sv' rtl tb formal; then
  printf '%s\n' 'Source policy violation'
  exit 1
fi
printf '%s\n' 'Source policy pass'
