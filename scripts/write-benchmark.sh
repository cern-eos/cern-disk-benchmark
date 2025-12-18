#!/usr/bin/env bash
# ----------------------------------------------------------------------
# File: scripts/write-benchmark.sh
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
# Parallel write benchmark
# Usage: ./write-benchmark.sh <mount-path> [parallelism=1] [stop-percent=99]
#
# - Creates /var/tmp/1GB (1 GiB) from /dev/urandom if needed
# - Spawns N parallel writers copying random 800–1000 MiB chunks
#   from /var/tmp/1GB to <path>/file.<counter>.<writer>
# - Stops when the filesystem containing <path> is ≥ 99% full
# - Runs dstat in parallel and logs timestamp + write rate (MB/s)
#   to /var/tmp/write-benchmark.log every 10s
#

set -uo pipefail

ONE_GB_BYTES=$((1024 * 1024 * 1024))
SEED_FILE="/var/tmp/1GB"
LOG_FILE="/var/tmp/write-benchmark.log"
START_TS=$(date +%s)
BASE_USAGE=0
TOTAL_BYTES=0

usage() {
    echo "Usage: $0 <mount-path> [parallelism=1] [stop-percent=99]" >&2
    exit 1
}

if [[ $# -lt 1 || $# -gt 3 ]]; then
    usage
fi

MOUNT_PATH="$1"
PARALLEL="${2:-1}"
STOP_PERCENT="${3:-99}"

if [[ ! -d "$MOUNT_PATH" ]]; then
    echo "ERROR: '$MOUNT_PATH' is not a directory" >&2
    exit 1
fi

if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]] || [[ "$PARALLEL" -le 0 ]]; then
    echo "ERROR: parallelism must be a positive integer" >&2
    exit 1
fi

if ! [[ "$STOP_PERCENT" =~ ^[0-9]+$ ]] || [[ "$STOP_PERCENT" -lt 1 ]] || [[ "$STOP_PERCENT" -gt 100 ]]; then
    echo "ERROR: stop-percent must be an integer between 1 and 100 (got '$STOP_PERCENT')" >&2
    exit 1
fi

if ! command -v dd >/dev/null 2>&1; then
    echo "ERROR: 'dd' not found in PATH" >&2
    exit 1
fi

if ! command -v df >/dev/null 2>&1; then
    echo "ERROR: 'df' not found in PATH" >&2
    exit 1
fi

if ! command -v iostat >/dev/null 2>&1; then
    echo "ERROR: 'iostat' not found in PATH (install sysstat)" >&2
    exit 1
fi

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
        # Use stat -c%s (Linux) or fallback for other systems if needed
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

# --- Disk space check ------------------------------------------------------

print_disk_info() {
    echo "Current disk usage for $MOUNT_PATH:"
    df -h "$MOUNT_PATH"
    echo
}

# --- Parallel writer function ----------------------------------------------

writer() {
    local writer_id="$1"
    local mount="$2"
    local counter=0
    local written_bytes=0

    while :; do
        # Check current usage percentage
        local usage
        usage=$(df -P "$mount" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')

        if [[ -z "$usage" ]]; then
            echo "Writer $writer_id: unable to get disk usage, exiting." >&2
            break
        fi

        if [[ "$usage" -ge "$STOP_PERCENT" ]]; then
            echo "Writer $writer_id: filesystem at ${usage}% used (threshold ${STOP_PERCENT}%), stopping."
            printf '\n'
            break
        fi

        # Random file size between 800 and 1000 MiB
        # RANDOM is 0–32767, so this is fine.
        local size_mb=$((800 + RANDOM % 201))
        local outfile="$mount/file.${counter}.${writer_id}"

        local elapsed=$(( $(date +%s) - START_TS ))
        local eta="--:--:--"
        written_bytes=$((written_bytes + size_mb * 1024 * 1024))
        if (( TOTAL_BYTES > 0 )); then
            local progress_milli=$((written_bytes * 100000 / TOTAL_BYTES)) # thousandths of percent
            if (( progress_milli > 0 )); then
                local rem_milli=$(((STOP_PERCENT - BASE_USAGE) * 1000 - progress_milli))
                if (( rem_milli < 0 )); then rem_milli=0; fi
                eta=$(human_eta $(( elapsed * rem_milli / progress_milli )))
            fi
        fi

        # Compact progress line; overwrite in place.
        printf '\rWriter %s: file %s size %sMiB (usage: %s%%, ETA %s) ...' "$writer_id" "$counter" "$size_mb" "$usage" "$eta"

        # Copy from the seed file; fsync to flush
        if ! dd if="$SEED_FILE" of="$outfile" bs=1M count="$size_mb" iflag=fullblock conv=fsync status=none; then
            echo -e "\nWriter $writer_id: dd failed, possibly ENOSPC, exiting loop." >&2
            break
        fi

        counter=$((counter + 1))
    done

    # Ensure we leave the cursor on a new line.
    printf '\n'
}

# --- IO monitor (iostat) ---------------------------------------------------

start_dstat() {
    local device="$1"
    local mount="$2"
    echo "Starting iostat monitor for device '$device'; logging to $LOG_FILE (10s interval)..." >&2

    # Overwrite old log
    : > "$LOG_FILE"
    echo "monitor start $(date -u +\"%Y-%m-%dT%H:%M:%SZ\") dev=$device mount=$mount" >> "$LOG_FILE"

    # iostat parsing:
    #   -d        : device utilization
    #   -x        : extended stats (includes wkB/s)
    #   -k        : kB units
    #   <device>  : limit to the target block device/partition
    # We sample every 10s and extract the wkB/s column for the device.
    stdbuf -oL -eL iostat -dx -k "$device" 10 \
    2> >(stdbuf -oL -eL sed "s/^/[iostat] /" >> "$LOG_FILE") \
    | stdbuf -oL -eL awk -v mount="$mount" -v dev="$device" '
        BEGIN { wkb_col = -1 }

        # Capture header to find wkB/s column index
        /Device/ && wkb_col == -1 {
            for (i = 1; i <= NF; i++) {
                if ($i == "wkB/s" || $i == "wKB/s") {
                    wkb_col = i
                    break
                }
            }
            next
        }

        # Skip until we know the column
        wkb_col == -1 { next }

        # Data lines: first field is device
        $1 == dev {
            wkb = $(wkb_col)
            mb = wkb / 1024

            # Timestamp in ISO-like format UTC
            cmdts = "date -u +\"%s\""
            cmdts | getline ts
            close(cmdts)

            # Fetch current disk usage of the target mount (percentage used)
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

# --- Main ------------------------------------------------------------------

create_seed_file
print_disk_info

BASE_USAGE=$(df -P "$MOUNT_PATH" | awk "NR==2 {gsub(/%/,\"\",\$5); print \$5}")
TOTAL_BYTES=$(df -B1 "$MOUNT_PATH" | awk "NR==2 {print \$2}")
TARGET_DEV=$(df -P "$MOUNT_PATH" | awk "NR==2 {print \$1}")
RESOLVED_DEV=$(readlink -f "$TARGET_DEV" 2>/dev/null || echo "$TARGET_DEV")
DSTAT_DEV=$(basename "$RESOLVED_DEV")

# Include device name in log filename
LOG_FILE="/var/tmp/write-benchmark-${DSTAT_DEV}.log"

echo "Monitoring block device: $DSTAT_DEV (from df device $TARGET_DEV)"
echo "Starting $PARALLEL parallel writers on $MOUNT_PATH (stop at ${STOP_PERCENT}% used)..."
DSTAT_PID=$(start_dstat "$DSTAT_DEV" "$MOUNT_PATH")

WRITER_PIDS=()

for i in $(seq 1 "$PARALLEL"); do
    writer "$i" "$MOUNT_PATH" &
    WRITER_PIDS+=($!)
done

# On exit, try to kill child processes
cleanup() {
    echo "Cleaning up..."
    for pid in "${WRITER_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    if [[ -n "${DSTAT_PID:-}" ]] && kill -0 "$DSTAT_PID" 2>/dev/null; then
        kill "$DSTAT_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Wait for all writers to finish
for pid in "${WRITER_PIDS[@]}"; do
    wait "$pid" || true
done

# Once writers are done, stop dstat
if kill -0 "$DSTAT_PID" 2>/dev/null; then
    echo "Stopping dstat (pid $DSTAT_PID)..."
    kill "$DSTAT_PID" 2>/dev/null || true
fi

echo "Final disk usage:"
df -h "$MOUNT_PATH"

echo
echo "Benchmark complete."
echo "Write performance log: $LOG_FILE"

