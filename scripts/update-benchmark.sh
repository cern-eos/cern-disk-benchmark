#!/usr/bin/env bash
# ----------------------------------------------------------------------
# File: scripts/update-benchmark.sh
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
# 
# Update benchmark: repeatedly rewrites existing benchmark files.
# Usage: ./update-benchmark.sh <mount-path> <parallelism>
#
# - Scans <mount-path> for files matching "file.*" (non-recursive)
# - Spawns N workers; each repeatedly picks a random file, deletes it, and
#   recreates it using the same seed/random write approach as write-benchmark.sh
# - Runs iostat in parallel and logs timestamp + write rate (MB/s) to
#   /var/tmp/update-benchmark-<device>.log every 10s
#

set -euo pipefail

ONE_GB_BYTES=$((1024 * 1024 * 1024))
SEED_FILE="/var/tmp/1GB"
LOG_FILE="/var/tmp/update-benchmark.log"
START_TS=$(date +%s)

usage() {
    echo "Usage: $0 <mount-path> <parallelism>" >&2
    exit 1
}

if [[ $# -ne 2 ]]; then
    usage
fi

MOUNT_PATH="$1"
PARALLEL="$2"

if [[ ! -d "$MOUNT_PATH" ]]; then
    echo "ERROR: '$MOUNT_PATH' is not a directory" >&2
    exit 1
fi

if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]] || [[ "$PARALLEL" -le 0 ]]; then
    echo "ERROR: parallelism must be a positive integer" >&2
    exit 1
fi

for dep in dd df iostat find stat flock; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo "ERROR: '$dep' not found in PATH" >&2
        exit 1
    fi
done

human_eta() {
    local s=$1
    if (( s < 0 )); then s=0; fi
    printf "%02d:%02d:%02d" $((s/3600)) $(((s/60)%60)) $((s%60))
}

# --- Create 1 GiB seed file if needed --------------------------------------

create_seed_file() {
    echo "Ensuring seed file $SEED_FILE exists and is 1 GiB..."

    local current_size=0
    if [[ -f "$SEED_FILE" ]]; then
        if current_size=$(stat -c%s "$SEED_FILE" 2>/dev/null); then
            :
        else
            current_size=$(stat -f%z "$SEED_FILE" 2>/dev/null || echo 0)
        fi
    fi

    if [[ "$current_size" -ne "$ONE_GB_BYTES" ]]; then
        echo "Creating new 1 GiB random file at $SEED_FILE (this may take a while)..."
        rm -f "$SEED_FILE"
        dd if=/dev/urandom of="$SEED_FILE" bs=1M count=1024 iflag=fullblock status=progress
        sync
    else
        echo "Seed file already exists with correct size."
    fi
}

# --- IO monitor (iostat) ---------------------------------------------------

start_iostat() {
    local device="$1"
    local mount="$2"
    echo "Starting iostat monitor for device '$device'; logging to $LOG_FILE (10s interval)..." >&2

    : > "$LOG_FILE"
    echo "monitor start $(date -u +\"%Y-%m-%dT%H:%M:%SZ\") dev=$device mount=$mount" >> "$LOG_FILE"

    stdbuf -oL -eL iostat -dx -k "$device" 10 \
    2> >(stdbuf -oL -eL sed "s/^/[iostat] /" >> "$LOG_FILE") \
    | stdbuf -oL -eL awk -v mount="$mount" -v dev="$device" '
        BEGIN { wkb_col = -1 }

        /Device/ && wkb_col == -1 {
            for (i = 1; i <= NF; i++) {
                if ($i == "wkB/s" || $i == "wKB/s") {
                    wkb_col = i
                    break
                }
            }
            next
        }

        wkb_col == -1 { next }

        $1 == dev {
            wkb = $(wkb_col)
            mb = wkb / 1024

            cmdts = "date -u +\"%s\""
            cmdts | getline ts
            close(cmdts)

            cmdu = "df -P " mount " | tail -1"
            line = ""
            if (cmdu | getline line) {
                split(line, a)
                usage = a[5]
                gsub(/%/, "", usage)
            } else {
                usage = "?"
            }
            close(cmdu)

            printf "%s %s %.2f\n", ts, usage, mb
            fflush("")
        }
    ' >> "$LOG_FILE" &
    echo $!
}

# --- File list -------------------------------------------------------------

read_file_list() {
    local path="$1"
    mapfile -d '' FILES < <(find "$path" -maxdepth 1 -type f -name 'file.*' -print0)
    if [[ ${#FILES[@]} -eq 0 ]]; then
        echo "ERROR: no files matching 'file.*' found under $path" >&2
        exit 1
    fi
    echo "Found ${#FILES[@]} files to cycle."
}

# --- Size helpers ----------------------------------------------------------

size_bytes() {
    local f="$1"
    local sz
    if sz=$(stat -c%s "$f" 2>/dev/null); then
        echo "$sz"
    else
        stat -f%z "$f" 2>/dev/null || echo 0
    fi
}

# --- Worker ---------------------------------------------------------------

worker() {
    local id="$1"
    local mount="$2"
    local count=${#FILES[@]}
    local lfd

    while :; do
        # Atomically claim the next index from the shared counter
        exec {lfd}> "$QUEUE_LOCK"
        flock -x "$lfd"
        local idx
        idx=$(<"$QUEUE_FILE")
        if [[ -z "$idx" ]]; then idx=0; fi
        if (( idx >= count )); then
            flock -u "$lfd"
            exec {lfd}>&-
            break
        fi
        echo $((idx + 1)) > "$QUEUE_FILE"
        flock -u "$lfd"
        exec {lfd}>&-

        local target="${FILES[$idx]}"

        if [[ ! -e "$target" ]]; then
            continue
        fi

        local lock="${target}.lock"
        if ! mkdir "$lock" 2>/dev/null; then
            continue
        fi

        local bytes
        bytes=$(size_bytes "$target")
        if [[ -z "$bytes" || "$bytes" -le 0 ]]; then
            rmdir "$lock" 2>/dev/null || true
            continue
        fi

        local size_mb=$(( (bytes + 1024 * 1024 - 1) / (1024 * 1024) ))
        local base
        base=$(basename "$target")
        local done=$((idx + 1))
        local pct=$((done * 100 / count))
        local elapsed=$(( $(date +%s) - START_TS ))
        local eta="--:--:--"
        if (( done > 0 )); then
            eta=$(human_eta $(( elapsed * (count - done) / done )))
        fi
        printf '\rProgress %3d%% (%d/%d) ETA %s - worker %s: rewriting %s (%s MiB)...' "$pct" "$done" "$count" "$eta" "$id" "$base" "$size_mb"

        rm -f "$target"
        if ! dd if="$SEED_FILE" of="$target" bs=1M count="$size_mb" iflag=fullblock conv=fsync status=none; then
            echo -e "\nWorker $id: dd failed for $target" >&2
        fi

        rmdir "$lock" 2>/dev/null || true
    done

    # Ensure newline at exit.
    printf '\n'
}

# --- Main ------------------------------------------------------------------

create_seed_file
read_file_list "$MOUNT_PATH"

TARGET_DEV=$(df -P "$MOUNT_PATH" | awk "NR==2 {print \$1}")
RESOLVED_DEV=$(readlink -f "$TARGET_DEV" 2>/dev/null || echo "$TARGET_DEV")
DSTAT_DEV=$(basename "$RESOLVED_DEV")

LOG_FILE="/var/tmp/update-benchmark-${DSTAT_DEV}.log"
QUEUE_FILE=$(mktemp /tmp/update-bench-queue.XXXXXX)
QUEUE_LOCK="${QUEUE_FILE}.lock"
echo 0 > "$QUEUE_FILE"

echo "Monitoring block device: $DSTAT_DEV (from df device $TARGET_DEV)"
echo "Starting $PARALLEL parallel updaters on $MOUNT_PATH..."
echo "Each file will be rewritten once (total ${#FILES[@]} files)."
DSTAT_PID=$(start_iostat "$DSTAT_DEV" "$MOUNT_PATH")

WORKER_PIDS=()

for i in $(seq 1 "$PARALLEL"); do
    worker "$i" "$MOUNT_PATH" &
    WORKER_PIDS+=($!)
done

cleanup() {
    echo "Cleaning up..."
    rm -f "$QUEUE_FILE" "$QUEUE_LOCK"
    for pid in "${WORKER_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    if [[ -n "${DSTAT_PID:-}" ]] && kill -0 "$DSTAT_PID" 2>/dev/null; then
        kill "$DSTAT_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

for pid in "${WORKER_PIDS[@]}"; do
    wait "$pid" || true
done

