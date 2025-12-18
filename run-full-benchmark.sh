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

if [[ ! -d "$MOUNT" ]]; then
  echo "ERROR: '$MOUNT' is not a directory" >&2
  exit 1
fi

# Determine device name for log/plot filenames.
TARGET_DEV=$(df -P "$MOUNT" | awk 'NR==2 {print $1}')
RESOLVED_DEV=$(readlink -f "$TARGET_DEV" 2>/dev/null || echo "$TARGET_DEV")
DEV_BASENAME=$(basename "$RESOLVED_DEV")

WRITE_LOG="/var/tmp/write-benchmark-${DEV_BASENAME}.log"
UPDATE_LOG="/var/tmp/update-benchmark-${DEV_BASENAME}.log"
WRITE_PLOT="/var/tmp/write-speed-${DEV_BASENAME}.jpg"
UPDATE_PLOT="/var/tmp/update-speed-${DEV_BASENAME}.jpg"

echo "Running write benchmark..."
"${SCRIPT_DIR}/run-write-benchmark.sh" "$MOUNT" "$PARALLEL" "$STOP"

echo "Plotting write results to ${WRITE_PLOT}..."
"${SCRIPT_DIR}/plot_benchmark.py" "$WRITE_LOG" "$WRITE_PLOT"

echo "Running update benchmark..."
"${SCRIPT_DIR}/run-update-benchmark.sh" "$MOUNT" "$PARALLEL"

echo "Plotting update results to ${UPDATE_PLOT}..."
"${SCRIPT_DIR}/plot_benchmark.py" "$UPDATE_LOG" "$UPDATE_PLOT"

echo "Done. Plots:"
echo "  Write : ${WRITE_PLOT}"
echo "  Update: ${UPDATE_PLOT}"

