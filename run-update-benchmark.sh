#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -t 1 ]]; then
  c_info="\033[36m"; c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_reset="\033[0m"
else
  c_info=""; c_ok=""; c_warn=""; c_err=""; c_reset=""
fi

info()  { echo -e "${c_info}[INFO]${c_reset} $*"; }
ok()    { echo -e "${c_ok}[OK]${c_reset} $*"; }
error() { echo -e "${c_err}[ERR]${c_reset} $*"; exit 1; }

if [[ $# -lt 1 || $# -gt 2 ]]; then
  error "Usage: $0 <mount-path> [parallelism=1]"
fi

for dep in python3 dd iostat df; do
  command -v "$dep" >/dev/null 2>&1 || error "'$dep' not found in PATH"
done
python3 - <<'PY' >/dev/null 2>&1 || { echo "[ERR] python3 missing matplotlib" >&2; exit 1; }
import matplotlib
PY

MOUNT="$1"
PARALLEL="${2:-1}"

info "Starting update benchmark on ${MOUNT} (parallel=${PARALLEL})"
"${SCRIPT_DIR}/scripts/update-benchmark.sh" "$MOUNT" "$PARALLEL"
ok "Update benchmark finished"

