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

# Determine device name for filenames.
TARGET_DEV=$(df -P "$MOUNT" | awk 'NR==2 {print $1}')
RESOLVED_DEV=$(readlink -f "$TARGET_DEV" 2>/dev/null || echo "$TARGET_DEV")
DEV_BASENAME=$(basename "$RESOLVED_DEV")

WRITE_LOG="/var/tmp/write-benchmark-${DEV_BASENAME}.log"
UPDATE_LOG="/var/tmp/update-benchmark-${DEV_BASENAME}.log"
WRITE_PLOT="/var/tmp/write-speed-${DEV_BASENAME}.jpg"
UPDATE_PLOT="/var/tmp/update-speed-${DEV_BASENAME}.jpg"
REPORT_PDF="/var/tmp/benchmark-report-${DEV_BASENAME}.pdf"

echo "Running full benchmark (write -> update) for $MOUNT ..."
"${SCRIPT_DIR}/run-full-benchmark.sh" "$MOUNT" "$PARALLEL" "$STOP"

echo "Generating report at ${REPORT_PDF} ..."

python3 - "$DEV_BASENAME" "$MOUNT" "$WRITE_PLOT" "$UPDATE_PLOT" "$REPORT_PDF" "$RESOLVED_DEV" <<'PY'
import os
import sys
from typing import Tuple

def get_cmd_output(cmd) -> str:
    import subprocess
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
        return out.strip()
    except subprocess.CalledProcessError as e:
        return f"(command failed: {' '.join(cmd)}):\n{e.output.strip()}"
    except FileNotFoundError:
        return f"(command not found: {cmd[0]})"

def jpeg_size(path: str) -> Tuple[int, int]:
    """Return (width, height) for a JPEG file."""
    with open(path, "rb") as f:
        data = f.read(24)
        if len(data) < 24 or data[0:2] != b"\xff\xd8":
            raise ValueError("Not a JPEG")
        idx = 2
        while idx < len(data):
            if data[idx] != 0xFF:
                break
            marker = data[idx + 1]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                h = int.from_bytes(data[idx + 5:idx + 7], "big")
                w = int.from_bytes(data[idx + 7:idx + 9], "big")
                return w, h
            else:
                length = int.from_bytes(data[idx + 2:idx + 4], "big")
                idx += 2 + length
                if idx + 9 > len(data):
                    data += f.read(1024)
        raise ValueError("SOF marker not found")

def pdf_with_text_and_images(out_path: str, title: str, info_lines, images):
    """
    Create a simple multi-page PDF:
      - First page: text lines (info_lines)
      - Subsequent pages: each image from images list (path, label)
    Uses only standard library and embeds JPEGs directly.
    """
    objects = []

    def add_object(obj: str) -> int:
        objects.append(obj)
        return len(objects)

    # Font object
    font_obj = add_object("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

    # Text content stream
    y_start = 750
    lines = [title, ""] + info_lines
    text_parts = ["BT", "/F1 12 Tf", "1 0 0 1 50 %d Tm" % y_start]
    for line in lines:
        safe = line.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
        text_parts.append(f"({safe}) Tj")
        text_parts.append("0 -16 Td")
    text_parts.append("ET")
    text_stream = "\n".join(text_parts).encode("utf-8")
    text_stream_obj = add_object(f"<< /Length {len(text_stream)} >>\nstream\n{text_stream.decode('utf-8')}\nendstream")

    # First page
    page1_obj = add_object(
        f"<< /Type /Page /Parent 0 0 R /MediaBox [0 0 612 792] "
        f"/Contents {text_stream_obj} 0 R "
        f"/Resources << /Font << /F1 {font_obj} 0 R >> >> >>"
    )

    page_objs = [page1_obj]

    # Image pages
    for idx, (img_path, label) in enumerate(images):
        if not os.path.exists(img_path):
            continue
        try:
            w, h = jpeg_size(img_path)
        except Exception as e:
            info_lines.append(f"Image '{label}' skipped (could not read size: {e})")
            continue
        with open(img_path, "rb") as f:
            img_data = f.read()
        img_obj = add_object(
            f"<< /Type /XObject /Subtype /Image /Width {w} /Height {h} "
            f"/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length {len(img_data)} >>\nstream\n"
            f"{img_data.decode('latin1')}\nendstream"
        )
        # Page content to place image
        content = f"q {w} 0 0 {h} 0 0 cm /Im0 Do Q"
        content_obj = add_object(f"<< /Length {len(content)} >>\nstream\n{content}\nendstream")
        page_obj = add_object(
            f"<< /Type /Page /Parent 0 0 R /MediaBox [0 0 {w} {h}] "
            f"/Contents {content_obj} 0 R "
            f"/Resources << /XObject << /Im0 {img_obj} 0 R >> >> >>"
        )
        page_objs.append(page_obj)

    # Pages tree
    kids = " ".join(f"{p} 0 R" for p in page_objs)
    pages_obj = add_object(f"<< /Type /Pages /Count {len(page_objs)} /Kids [ {kids} ] >>")

    # Fix parent references (now that pages_obj is known)
    def fix_parent(obj_str):
        return obj_str.replace("/Parent 0 0 R", f"/Parent {pages_obj} 0 R")
    objects[:] = [fix_parent(o) for o in objects]

    # Catalog
    catalog_obj = add_object(f"<< /Type /Catalog /Pages {pages_obj} 0 R >>")

    # Assemble PDF
    parts = [b"%PDF-1.4\n"]
    offsets = []
    for i, obj in enumerate(objects, start=1):
        offsets.append(sum(len(p) for p in parts))
        parts.append(f"{i} 0 obj\n".encode("latin1"))
        parts.append(obj.encode("latin1"))
        parts.append(b"\nendobj\n")
    xref_pos = sum(len(p) for p in parts)
    xref_lines = ["xref", f"0 {len(objects)+1}", "0000000000 65535 f "]
    for off in offsets:
        xref_lines.append(f"{off:010d} 00000 n ")
    trailer = [
        "trailer",
        f"<< /Size {len(objects)+1} /Root {catalog_obj} 0 R >>",
        "startxref",
        str(xref_pos),
        "%%EOF",
    ]
    parts.append("\n".join(xref_lines).encode("latin1") + b"\n")
    parts.append("\n".join(trailer).encode("latin1") + b"\n")
    with open(out_path, "wb") as f:
        for p in parts:
            f.write(p)

def main():
    if len(sys.argv) != 6:
        print("usage: script <dev> <mount> <write_jpg> <update_jpg> <pdf_out> <device_path>", file=sys.stderr)
        sys.exit(1)
    dev, mount, write_jpg, update_jpg, pdf_out, device_path = sys.argv[1:]

    dev_base = os.path.basename(device_path)
    sysfs_base = f"/sys/block/{dev_base}"

    def read_sysfs(relpath: str) -> str:
        p = os.path.join(sysfs_base, relpath)
        try:
            with open(p, "r", encoding="utf-8") as f:
                return f.read().strip()
        except FileNotFoundError:
            return f"(not found: {p})"
        except PermissionError:
            return f"(permission denied: {p})"

    info_lines = [
        f"Device: {device_path}",
        f"Mount:  {mount}",
        "",
        "lsblk:",
        get_cmd_output(["lsblk", "-d", "-o", "NAME,MODEL,SIZE,SERIAL", device_path]),
        "",
        "xfs_info:",
        get_cmd_output(["xfs_info", mount]),
        "",
        "Queue and I/O settings:",
        f"  queue_depth       : {read_sysfs('device/queue_depth')}",
        f"  nr_requests       : {read_sysfs('queue/nr_requests')}",
        f"  max_sectors_kb    : {read_sysfs('queue/max_sectors_kb')}",
        f"  scheduler         : {read_sysfs('queue/scheduler')}",
        f"  write_cache (sys) : {read_sysfs('queue/write_cache')}",
        "",
        "Write cache (hdparm -W):",
        get_cmd_output(["hdparm", "-W", device_path]),
        "",
        "SAS/SATA controller (lspci):",
        get_cmd_output(["sh", "-c", "lspci | egrep -i 'sas|sata|lsi|broadcom'"]),
    ]

    images = [
        (write_jpg, f"Write plot ({write_jpg})"),
        (update_jpg, f"Update plot ({update_jpg})"),
    ]

    pdf_with_text_and_images(pdf_out, f"Benchmark Report for {mount}", info_lines, images)

if __name__ == "__main__":
    main()
PY

echo "Report written to ${REPORT_PDF}"

