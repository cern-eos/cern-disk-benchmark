# CERN Disk Benchmark Tool

## Prerequisites
- `sysstat` (for `iostat`) — e.g., `sudo dnf install sysstat` on RHEL/Alma
- `python3` and `pip`
- `python3 -m pip install matplotlib`

## One-shot full benchmark + report
```
./run-report.sh <mount-path> [parallelism=1] [stop-percent=99]
```
Runs write, then update, produces plots, and writes a PDF report.
- Plots:
  - `/var/tmp/write-speed-<device>.jpg`
  - `/var/tmp/update-speed-<device>.jpg`
- Report:
  - `/var/tmp/benchmark-report-<device>-<hostname>-<unix_ts>.pdf`
  - Contains host, run time, uname, lsblk, xfs_info, queue settings, hdparm cache, lspci SAS/SATA info, and embeds the plots.

## If you want each step separately

### Write benchmark
```
./run-write-benchmark.sh <mount-path> [parallelism=1] [stop-percent=99]
```
- Writes 800–1000 MiB chunks until the stop threshold.
- Seed file: `/var/tmp/1GB`.
- Log: `/var/tmp/write-benchmark-<device>.log` (usage%, MB/s).

### Update benchmark (rewrite existing files)
```
./run-update-benchmark.sh <mount-path> [parallelism=1]
```
- Rewrites each `file.*` (non-recursive) once with the same size.
- Log: `/var/tmp/update-benchmark-<device>.log` (iostat).

### Plots only
```
./plot_benchmark.py /var/tmp/write-benchmark-<device>.log out.jpg
```
- Generates a JPG plot of usage vs write speed.

### Full benchmark only (write + update, no PDF)
```
./run-full-benchmark.sh <mount-path> [parallelism=1] [stop-percent=99]
```
- Runs write then update; saves the two plots above.

## Low-level scripts (usually not called directly)
- `scripts/write-benchmark.sh`, `scripts/write-benchmark`
- `scripts/update-benchmark.sh`, `scripts/update-benchmark`

