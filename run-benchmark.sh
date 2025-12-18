#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: $0 <mount-path> [parallelism=1] [stop-percent=99]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MOUNT="$1"
PARALLEL="${2:-1}"
STOP="${3:-99}"

exec cmake -P "${SCRIPT_DIR}/cmake/run-benchmark.cmake" "$MOUNT" "$PARALLEL" "$STOP"

