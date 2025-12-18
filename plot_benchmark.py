#!/usr/bin/env python3
"""
Plot write-benchmark log: timestamp (epoch seconds) vs write speed (MB/s).

Usage:
    ./plot_benchmark.py /var/tmp/write-benchmark-<device>.log output.jpg

Dependencies:
    pip install matplotlib
"""

import sys
from datetime import datetime
from typing import List, Tuple

import matplotlib.pyplot as plt


def read_log(path: str) -> Tuple[List[datetime], List[float]]:
    ts: List[datetime] = []
    mbps: List[float] = []

    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("monitor start") or line.startswith("[iostat]"):
                continue

            parts = line.split()
            if len(parts) < 3:
                continue

            try:
                epoch = int(float(parts[0]))
                speed = float(parts[2])
            except ValueError:
                continue

            ts.append(datetime.utcfromtimestamp(epoch))
            mbps.append(speed)

    return ts, mbps


def plot(ts: List[datetime], mbps: List[float], title: str, out_path: str) -> None:
    plt.figure(figsize=(10, 4))
    plt.plot(ts, mbps, marker="o", linestyle="-", linewidth=1)
    plt.xlabel("Time (UTC)")
    plt.ylabel("Write speed (MB/s)")
    plt.title(title)
    plt.grid(True, linestyle="--", alpha=0.4)
    plt.tight_layout()
    plt.savefig(out_path, dpi=150, format="jpg")


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <log-file> <output.jpg>", file=sys.stderr)
        return 1

    log_path, out_path = sys.argv[1], sys.argv[2]
    ts, mbps = read_log(log_path)
    if not ts:
        print("No data points found.", file=sys.stderr)
        return 1

    plot(ts, mbps, f"Write speed: {log_path}", out_path)
    print(f"Wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

