#!/usr/bin/env python3
"""Generate Sortomat's app-icon ladder without any imaging dependency.

Renders one supersampled master — a rounded-square tile on Apple's macOS icon
grid, with a vertical brand-green gradient and a white "sorting funnel" glyph —
then box-downsamples it through a mip chain to every size in the ladder and
writes them as PNGs straight into the asset catalog.

Pure standard library: it hand-encodes PNG (zlib + CRC), so it runs anywhere,
including a Linux box with no Pillow. On macOS, Tools/GenerateAppIcon.swift
renders the same geometry through Core Graphics.

Three things here are load-bearing and easy to get wrong:

* **The grid.** A macOS app icon is not full-bleed. Apple's own icons put the
  rounded square in 824 of 1024 points, centred, and the system draws every
  icon in the Dock at the same scale — so an icon that fills its canvas renders
  about a quarter larger than its neighbours and looks like a mistake.
* **The corner.** The radius is a fixed fraction *of the body*, not of the
  canvas: 185.4 of 824. Scaling it off the canvas instead is the other half of
  the same mistake.
* **Antialiasing.** The tile and the glyph are drawn by span, with no coverage
  at the edges, so every edge is jagged at native resolution. Rendering the
  master at twice the largest output and box-averaging down is what smooths
  them — and it must apply to the *largest* icon too, which is exactly the one
  a "downsample only when smaller" shortcut leaves aliased.

Usage:
    python3 Tools/generate_icon.py [OUTPUT_APPICONSET_DIR]
"""

import os
import struct
import sys
import zlib

# macOS icon ladder: (point size, scale) -> pixel dimension. Every entry is a
# power of two, which is what lets the mip chain below hit each one exactly.
LADDER = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

# Apple's macOS icon grid, in points on a 1024 canvas.
CANVAS = 1024
BODY = 824.0            # the rounded square, centred
CORNER = 185.4          # its corner radius — a fraction of BODY, not of CANVAS
SUPERSAMPLE = 2         # master is rendered at CANVAS * SUPERSAMPLE

# The brand palette. One place, and the only place: `AccentColor.colorset`
# holds the midpoint of this gradient, so the tint the app draws with and the
# tile it ships in are the same green.
TOP = (0x4F, 0x9E, 0x74)      # lighter green (top of the gradient)
BOTTOM = (0x2F, 0x6B, 0x4C)   # deeper green (bottom)
GLYPH = (0xF6, 0xFB, 0xF8)    # near-white funnel

# The funnel, in coordinates relative to the *body* (y grows downward). Convex,
# which is what lets each scanline be one span.
FUNNEL = [
    (0.20, 0.24), (0.80, 0.24), (0.595, 0.51),
    (0.595, 0.78), (0.405, 0.78), (0.405, 0.51),
]


def _lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def _rounded_rect_span(y, left, top, size, radius):
    """The [x0, x1) span of a rounded square on scanline `y`, or None."""
    if y < top or y >= top + size:
        return None
    dy = y - (top + size / 2.0)
    half = size / 2.0
    inset = half - radius
    if abs(dy) <= inset:
        return (left, left + size)
    # Inside a corner: the span narrows by the circle's chord.
    over = abs(dy) - inset
    if over >= radius:
        return None
    dx = (radius * radius - over * over) ** 0.5
    return (left + radius - dx, left + size - radius + dx)


def _polygon_span(y, poly):
    """The [x0, x1) span of a convex polygon on scanline `y`, or None."""
    crossings = []
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        if y0 == y1:
            continue
        if min(y0, y1) <= y < max(y0, y1):
            crossings.append(x0 + (x1 - x0) * (y - y0) / (y1 - y0))
    if len(crossings) < 2:
        return None
    return (min(crossings), max(crossings))


def _fill(row, span, colour, width):
    if span is None:
        return
    x0 = max(0, int(round(span[0])))
    x1 = min(width, int(round(span[1])))
    if x1 <= x0:
        return
    row[x0 * 4:x1 * 4] = bytes(colour) * (x1 - x0)


def render_master(size):
    """An RGBA master image (a list of rows, each a bytearray)."""
    scale = size / float(CANVAS)
    body = BODY * scale
    corner = CORNER * scale
    left = top = (size - body) / 2.0
    poly = [(left + px * body, top + py * body) for px, py in FUNNEL]

    rows = []
    for py in range(size):
        row = bytearray(size * 4)          # transparent
        yc = py + 0.5
        tile = _rounded_rect_span(yc, left, top, body, corner)
        if tile is not None:
            # The gradient runs over the body, not the canvas: the margin is
            # transparent, so a canvas-relative gradient would start part-way.
            t = min(1.0, max(0.0, (yc - top) / body))
            base = _lerp(TOP, BOTTOM, t) + (255,)
            _fill(row, tile, base, size)
            _fill(row, _polygon_span(yc, poly), GLYPH + (255,), size)
        rows.append(row)
    return rows


def halve(rows, size):
    """Box-average one mip level down: size -> size // 2."""
    half = size // 2
    out = []
    for y in range(half):
        top_row = rows[2 * y]
        bottom_row = rows[2 * y + 1]
        row = bytearray(half * 4)
        for x in range(half):
            o = x * 8
            d = x * 4
            for c in range(4):
                row[d + c] = (top_row[o + c] + top_row[o + 4 + c]
                              + bottom_row[o + c] + bottom_row[o + 4 + c]) // 4
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


def check_grid(rows, size):
    """Fail loudly if the icon has drifted back to filling its canvas.

    The margin is the whole point of the grid, and it is invisible in a diff of
    ten binary files: without this, "the icon looks a bit big" is something a
    person has to notice months later in a Dock full of correctly sized icons.
    """
    corner_alpha = rows[0][3]
    assert corner_alpha == 0, f"the canvas corner is not transparent ({corner_alpha})"
    middle = rows[size // 2]
    edge_alpha = middle[3]
    assert edge_alpha == 0, f"the icon touches the canvas edge ({edge_alpha})"
    expected_margin = round((CANVAS - BODY) / 2 * (size / CANVAS))
    first_opaque = next(x for x in range(size) if middle[x * 4 + 3] > 0)
    assert abs(first_opaque - expected_margin) <= 1, (
        f"body starts at {first_opaque}px, expected about {expected_margin}px"
    )
    print(f"  grid ok: {first_opaque}px margin on a {size}px master")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default_out = os.path.join(
        here, "..", "Sortomat", "Resources", "Assets.xcassets", "AppIcon.appiconset"
    )
    out_dir = sys.argv[1] if len(sys.argv) > 1 else default_out
    os.makedirs(out_dir, exist_ok=True)

    master_size = CANVAS * SUPERSAMPLE
    print(f"Rendering {master_size}px master…")
    levels = {master_size: render_master(master_size)}
    check_grid(levels[master_size], master_size)

    # One mip chain, shared by every size in the ladder: halving costs a
    # quarter of the level above it, so the whole chain is barely more work
    # than the first step. Downsampling each size straight from the master
    # would be ten full passes over four megapixels.
    wanted = sorted({pt * scale for pt, scale in LADDER}, reverse=True)
    size = master_size
    while size > min(wanted):
        levels[size // 2] = halve(levels[size], size)
        size //= 2

    for pt, scale in LADDER:
        px = pt * scale
        name = f"icon_{pt}x{pt}@{scale}x.png"
        write_png(os.path.join(out_dir, name), levels[px], px)
        print(f"  wrote {name} ({px}px)")

    print("Done.")


if __name__ == "__main__":
    main()
