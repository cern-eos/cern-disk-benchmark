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

if [[ $# -lt 1 || $# -gt 3 ]]; then
  error "Usage: $0 <mount-path> [parallelism=1] [stop-percent=99]"
fi

for dep in python3 dd iostat df; do
  command -v "$dep" >/dev/null 2>&1 || error "'$dep' not found in PATH"
done
python3 - <<'PY' >/dev/null 2>&1 || { echo "[ERR] python3 missing matplotlib" >&2; exit 1; }
import matplotlib
PY

MOUNT="$1"
PARALLEL="${2:-1}"
STOP="${3:-99}"

info "Starting write benchmark on ${MOUNT} (parallel=${PARALLEL}, stop=${STOP}%)"
"${SCRIPT_DIR}/scripts/write-benchmark.sh" "$MOUNT" "$PARALLEL" "$STOP"
ok "Write benchmark finished"

