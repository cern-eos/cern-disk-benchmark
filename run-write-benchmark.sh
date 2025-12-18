#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: $0 <mount-path> [parallelism=1] [stop-percent=99]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for dep in python3 dd iostat df; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "ERROR: '$dep' not found in PATH" >&2
    exit 1
  fi
done

MOUNT="$1"
PARALLEL="${2:-1}"
STOP="${3:-99}"

exec "${SCRIPT_DIR}/scripts/write-benchmark.sh" "$MOUNT" "$PARALLEL" "$STOP"

