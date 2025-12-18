#!/usr/bin/env bash
# ----------------------------------------------------------------------
# File: run-full-benchmark.sh
# Author: Andreas-Joachim Peters - CERN
# ----------------------------------------------------------------------
# ************************************************************************
# * EOS - the CERN Disk Storage System                                   *
# * Copyright (C) 2025 CERN/Switzerland                                  *
# *                                                                      *
# * This program is free software: you can redistribute it and/or modify *
# * it under the terms of the GNU General Public License as published by *
# * the Free Software Foundation, either version 3 of the License, or    *
# * (at your option) any later version.                                  *
# *                                                                      *
# * This program is distributed in the hope that it will be useful,      *
# * but WITHOUT ANY WARRANTY; without even the implied warranty of       *
# * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the        *
# * GNU General Public License for more details.                         *
# *                                                                      *
# * You should have received a copy of the GNU General Public License    *
# * along with this program.  If not, see <http://www.gnu.org/licenses/>.*
# ************************************************************************
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: $0 <mount-path> [parallelism=1] [stop-percent=99]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -t 1 ]]; then
  c_info="\033[36m"; c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_reset="\033[0m"
else
  c_info=""; c_ok=""; c_warn=""; c_err=""; c_reset=""
fi

info()  { echo -e "${c_info}[INFO]${c_reset} $*"; }
ok()    { echo -e "${c_ok}[OK]${c_reset} $*"; }
error() { echo -e "${c_err}[ERR]${c_reset} $*"; exit 1; }

for dep in python3 dd iostat df; do
  command -v "$dep" >/dev/null 2>&1 || error "'$dep' not found in PATH"
done
python3 - <<'PY' >/dev/null 2>&1 || { echo "[ERR] python3 missing matplotlib" >&2; exit 1; }
import matplotlib
PY

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

info "Running write benchmark..."
"${SCRIPT_DIR}/run-write-benchmark.sh" "$MOUNT" "$PARALLEL" "$STOP"

info "Plotting write results to ${WRITE_PLOT}..."
python3 "${SCRIPT_DIR}/plot_benchmark.py" "$WRITE_LOG" "$WRITE_PLOT"
ok "Wrote ${WRITE_PLOT}"

info "Running update benchmark..."
"${SCRIPT_DIR}/run-update-benchmark.sh" "$MOUNT" "$PARALLEL"

info "Plotting update results to ${UPDATE_PLOT}..."
python3 "${SCRIPT_DIR}/plot_benchmark.py" "$UPDATE_LOG" "$UPDATE_PLOT"
ok "Wrote ${UPDATE_PLOT}"

ok "Done. Plots:"
echo "  Write : ${WRITE_PLOT}"
echo "  Update: ${UPDATE_PLOT}"

