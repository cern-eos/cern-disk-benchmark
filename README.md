# SMR Bench

## Prerequisites
- `sysstat` (for `iostat`) — e.g., `sudo dnf install sysstat` on RHEL/Alma.
- `python3` and `pip`
- Python plotting dep: `python3 -m pip install matplotlib`

## Running the write benchmark
```bash
./write-benchmark.sh <mount-path> <parallelism>
```
Example:
```bash
./write-benchmark.sh /data100/benchmark 4
```

- The script writes 800–1000 MiB chunks in parallel until the filesystem is ~99% full.
- It creates/uses a 1 GiB seed file at `/var/tmp/1GB`.
- It logs per-interval stats to `/var/tmp/write-benchmark-<device>.log`, where `<device>` is the block device backing the mount (e.g., `write-benchmark-sdf1.log`).
- Log line format: `<epoch-seconds> <usage-percent> <MBps>`

## Plotting the results
```bash
./plot_benchmark.py /var/tmp/write-benchmark-sdf1.log write-speed.jpg
```

This produces `write-speed.jpg` with time (UTC) on the x-axis and write speed (MB/s) on the y-axis. The script skips header and diagnostic lines automatically.

