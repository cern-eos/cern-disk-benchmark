# SMR Bench

## Prerequisites
- `sysstat` (for `iostat`) — e.g., `sudo dnf install sysstat` on RHEL/Alma.
- `python3` and `pip`
- Python plotting dep: `python3 -m pip install matplotlib`

## Running the write benchmark
Recommended wrapper:
```bash
./run-write-benchmark.sh <mount-path> [parallelism=1] [stop-percent=99]
```
Example:
```bash
./run-write-benchmark.sh /data100/benchmark 4 95
```

- Writes 800–1000 MiB chunks in parallel until the filesystem reaches the configured threshold (default 99%).
- Creates/uses a 1 GiB seed file at `/var/tmp/1GB`.
- Logs per-interval stats to `/var/tmp/write-benchmark-<device>.log`, where `<device>` is the block device backing the mount (e.g., `write-benchmark-sdf1.log`).
- Log line format: `<epoch-seconds> <usage-percent> <MBps>`

### Running via CMake target
```
cmake -S . -B build -DMOUNTPOINT=/data100/benchmark -DPARALLELISM=4 -DSTOP_PERCENT=95
cmake --build build --target benchmark
```
- The target runs `./write-benchmark <mount> <parallelism> <stop-percent>` and then calls `plot_benchmark.py`.
- Plot is written to `write-speed-<device>.jpg` in the project root and the log remains in `/var/tmp/write-benchmark-<device>.log`.

### One-shot helper (no CMake cache args)
```
./run-write-benchmark.sh <mount-path> [parallelism=1] [stop-percent=99]
```
- Uses `cmake -P cmake/run-benchmark.cmake` under the hood (no configure step).

## Plotting the results
```bash
./plot_benchmark.py /var/tmp/write-benchmark-sdf1.log write-speed.jpg
```

This produces `write-speed.jpg` with time (UTC) on the x-axis and write speed (MB/s) on the y-axis. The script skips header and diagnostic lines automatically.

## Update benchmark (rewrite existing files)
```
./run-update-benchmark.sh <mount-path> <parallelism>
```
- Scans `<mount-path>` for files named `file.*` (non-recursive).
- Spawns N workers; each randomly picks a file, deletes it, and recreates it with the same size using the 1 GiB seed.
- Logs to `/var/tmp/update-benchmark-<device>.log` (iostat, 10s interval).
- Helper wraps `scripts/update-benchmark.sh`.

## Full benchmark (write + update, with plots)
```
./run-full-benchmark.sh <mount-path> [parallelism=1] [stop-percent=99]
```
- Runs the write benchmark first, then the update benchmark with the same mount/parallelism.
- Plots are saved as `write-speed-<device>.jpg` and `update-speed-<device>.jpg` in the project root.

## Low-level scripts
- `scripts/write-benchmark.sh`, `scripts/write-benchmark`
- `scripts/update-benchmark.sh`
- These are invoked by the top-level wrappers; you generally don't need to call them directly.

