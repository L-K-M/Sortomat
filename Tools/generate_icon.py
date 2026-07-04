#!/usr/bin/env python3
"""Generate Sortomat's app-icon ladder without any imaging dependency.

Renders a single high-resolution master (a rounded-square tile with a vertical
brand-green gradient and a white "sorting funnel" glyph), then box-downsamples it
to every macOS icon size and writes them as PNGs straight into the asset catalog.

Pure standard library — it hand-encodes PNG (zlib + CRC), so it runs anywhere,
including the Linux CI/dev box where Pillow/cairo aren't installed. On macOS you
can instead run Tools/GenerateAppIcon.swift for a Core Graphics render.

Usage:
    python3 Tools/generate_icon.py [OUTPUT_APPICONSET_DIR]
"""

import os
import struct
import sys
import zlib

# macOS icon ladder: (point size, scale) -> pixel dimension.
LADDER = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

# Brand palette (matches AccentColor.colorset).
TOP = (0x4F, 0x9E, 0x74)      # lighter green (top of gradient)
BOTTOM = (0x2F, 0x6B, 0x4C)   # deeper green (bottom of gradient)
GLYPH = (0xF6, 0xFB, 0xF8)    # near-white funnel


def _lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def _rounded_rect_alpha(x, y, size, radius):
    """Coverage-free inside test for a rounded rectangle in [0,size]^2."""
    r = radius
    lo, hi = r, size - r
    cx = min(max(x, lo), hi)
    cy = min(max(y, lo), hi)
    dx, dy = x - cx, y - cy
    return (dx * dx + dy * dy) <= r * r


def _point_in_polygon(x, y, poly):
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y):
            xcross = (xj - xi) * (y - yi) / (yj - yi) + xi
            if x < xcross:
                inside = not inside
        j = i
    return inside


def render_master(size):
    """Render an RGBA master image (list of rows, each a bytearray)."""
    radius = size * 0.225
    # Funnel glyph as a closed polygon in unit coords (y grows downward).
    unit = [
        (0.23, 0.27), (0.77, 0.27), (0.575, 0.52),
        (0.575, 0.75), (0.425, 0.75), (0.425, 0.52),
    ]
    poly = [(px * size, py * size) for px, py in unit]

    rows = []
    for py in range(size):
        row = bytearray(size * 4)
        t = py / (size - 1)
        base = _lerp(TOP, BOTTOM, t)
        yc = py + 0.5
        for px in range(size):
            xc = px + 0.5
            off = px * 4
            if not _rounded_rect_alpha(xc, yc, size, radius):
                continue  # transparent outside the squircle
            if _point_in_polygon(xc, yc, poly):
                r, g, b = GLYPH
            else:
                r, g, b = base
            row[off] = r
            row[off + 1] = g
            row[off + 2] = b
            row[off + 3] = 255
        rows.append(row)
    return rows


def downsample(master, msize, target):
    """Box-average the master down to target x target RGBA rows."""
    if msize == target:
        return master
    scale = msize / target
    out = []
    for ty in range(target):
        row = bytearray(target * 4)
        y0 = int(ty * scale)
        y1 = max(y0 + 1, int((ty + 1) * scale))
        for tx in range(target):
            x0 = int(tx * scale)
            x1 = max(x0 + 1, int((tx + 1) * scale))
            r = g = b = a = 0
            count = 0
            for sy in range(y0, y1):
                srow = master[sy]
                for sx in range(x0, x1):
                    o = sx * 4
                    r += srow[o]
                    g += srow[o + 1]
                    b += srow[o + 2]
                    a += srow[o + 3]
                    count += 1
            o = tx * 4
            row[o] = r // count
            row[o + 1] = g // count
            row[o + 2] = b // count
            row[o + 3] = a // count
        out.append(row)
    return out


def write_png(path, rows, size):
    raw = bytearray()
    for row in rows:
        raw.append(0)  # filter type 0 (None)
        raw.extend(row)

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return out + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", ihdr)
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default_out = os.path.join(
        here, "..", "Sortomat", "Resources", "Assets.xcassets", "AppIcon.appiconset"
    )
    out_dir = sys.argv[1] if len(sys.argv) > 1 else default_out
    os.makedirs(out_dir, exist_ok=True)

    master_size = 1024
    print(f"Rendering {master_size}px master…")
    master = render_master(master_size)

    for pt, scale in LADDER:
        px = pt * scale
        name = f"icon_{pt}x{pt}@{scale}x.png"
        rows = downsample(master, master_size, px)
        write_png(os.path.join(out_dir, name), rows, px)
        print(f"  wrote {name} ({px}px)")

    print("Done.")


if __name__ == "__main__":
    main()
