#!/usr/bin/env python3
"""Fit Sortomat's icon artwork to Apple's macOS icon grid.

Reads the master artwork committed at `media-sources/icon.png`, places it on
the rounded square macOS reserves for an app icon, and writes every size in the
ladder straight into the asset catalog.

Pure standard library: it decodes *and* encodes PNG by hand (zlib + CRC), so it
runs anywhere, including a Linux box with no Pillow. On macOS,
Tools/GenerateAppIcon.swift produces the same geometry through Core Graphics.

Four things here are load-bearing and easy to get wrong:

* **The grid.** A macOS app icon is not full-bleed. Apple's own icons put the
  rounded square in 824 of 1024 points, centred, and the system draws every
  icon in the Dock at the same scale — so an icon that fills its canvas renders
  about a quarter larger than its neighbours and looks like a mistake. The
  artwork is square and edge-to-edge, so it *is* the tile: it gets scaled into
  the 824 body, not pasted onto the 1024 canvas.
* **The corner.** The radius is a fixed fraction *of the body*, not of the
  canvas: 185.4 of 824. Scaling it off the canvas instead is the other half of
  the same mistake.
* **Resampling.** The artwork is photographic, so the ladder is a real
  downscale: a triangle filter whose support grows with the reduction ratio
  (every source pixel contributes to exactly one output pixel's neighbourhood),
  then a box mip chain for the smaller sizes. Nearest-neighbour or a
  fixed-width filter would alias the machine's edges into noise at 32px.
* **Premultiplied alpha.** Averaging *unpremultiplied* RGBA blends the tile's
  colour toward transparent black at the rounded corners, which is a dark halo
  on every icon edge. Everything below the mask is premultiplied; the
  un-premultiply happens once, on the way into the PNG.

Usage:
    python3 Tools/generate_icon.py [-s SOURCE_PNG] [OUTPUT_APPICONSET_DIR]
"""

import argparse
import math
import os
import struct
import sys
import zlib
from array import array

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

# Vertical subsamples per row when measuring the rounded square's coverage.
# Horizontal coverage is computed exactly (a span's fractional endpoints), so
# this only has to resolve the near-horizontal top and bottom of each corner.
SUBSAMPLES = 8

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
DEFAULT_SOURCE = os.path.join(ROOT, "media-sources", "icon.png")
DEFAULT_OUT = os.path.join(
    ROOT, "Sortomat", "Resources", "Assets.xcassets", "AppIcon.appiconset"
)


# --------------------------------------------------------------------------
# PNG in
# --------------------------------------------------------------------------

CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}     # colour type -> samples per pixel


def read_png(path):
    """Decode an 8-bit non-interlaced PNG into (width, height, RGBA rows)."""
    with open(path, "rb") as fh:
        blob = fh.read()
    if blob[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")

    header, data = None, bytearray()
    pos = 8
    while pos + 8 <= len(blob):
        (length,) = struct.unpack(">I", blob[pos:pos + 4])
        tag = blob[pos + 4:pos + 8]
        if tag == b"IHDR":
            header = blob[pos + 8:pos + 8 + length]
        elif tag == b"IDAT":
            data += blob[pos + 8:pos + 8 + length]
        elif tag == b"IEND":
            break
        pos += 12 + length              # length + tag + payload + CRC

    if header is None:
        raise ValueError(f"{path}: no IHDR chunk")
    width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", header)
    if depth != 8 or colour not in CHANNELS or interlace != 0:
        raise ValueError(
            f"{path}: need an 8-bit non-interlaced greyscale/RGB/RGBA PNG "
            f"(got depth {depth}, colour type {colour}, interlace {interlace}). "
            "Re-save it without a palette or interlacing."
        )

    bpp = CHANNELS[colour]
    stride = width * bpp
    raw = zlib.decompress(bytes(data))
    expected = (stride + 1) * height
    if len(raw) < expected:
        raise ValueError(f"{path}: truncated image data")

    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(height):
        kind = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        _unfilter(kind, line, prev, bpp, stride)
        rows.append(line)
        prev = line

    return width, height, [_to_rgba(row, colour, width) for row in rows]


def _unfilter(kind, line, prev, bpp, stride):
    """Undo one PNG scanline filter, in place."""
    if kind == 0:
        return
    if kind == 1:
        for i in range(bpp, stride):
            line[i] = (line[i] + line[i - bpp]) & 0xFF
    elif kind == 2:
        for i in range(stride):
            line[i] = (line[i] + prev[i]) & 0xFF
    elif kind == 3:
        for i in range(stride):
            left = line[i - bpp] if i >= bpp else 0
            line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
    elif kind == 4:
        for i in range(stride):
            left = line[i - bpp] if i >= bpp else 0
            upleft = prev[i - bpp] if i >= bpp else 0
            up = prev[i]
            guess = left + up - upleft
            dl, du, dul = abs(guess - left), abs(guess - up), abs(guess - upleft)
            if dl <= du and dl <= dul:
                pick = left
            elif du <= dul:
                pick = up
            else:
                pick = upleft
            line[i] = (line[i] + pick) & 0xFF
    else:
        raise ValueError(f"unknown PNG filter type {kind}")


def _to_rgba(row, colour, width):
    """Widen one decoded scanline to premultiplied RGBA."""
    if colour == 6:                                     # RGBA
        out = bytearray(row)
    elif colour == 2:                                   # RGB
        out = bytearray(width * 4)
        out[0::4], out[1::4], out[2::4] = row[0::3], row[1::3], row[2::3]
        out[3::4] = b"\xff" * width
    elif colour == 0:                                   # grey
        out = bytearray(width * 4)
        out[0::4] = out[1::4] = out[2::4] = row
        out[3::4] = b"\xff" * width
    else:                                               # grey + alpha
        out = bytearray(width * 4)
        out[0::4] = out[1::4] = out[2::4] = row[0::2]
        out[3::4] = row[1::2]
    return _premultiply(out, width)


def _premultiply(row, width):
    for x in range(width):
        alpha = row[x * 4 + 3]
        if alpha != 255:
            for c in range(3):
                i = x * 4 + c
                row[i] = (row[i] * alpha + 127) // 255
    return row


# --------------------------------------------------------------------------
# Resampling
# --------------------------------------------------------------------------

def _taps(src_len, dst_len):
    """Triangle-filter taps per output sample, normalized to sum to 1."""
    ratio = src_len / float(dst_len)
    support = max(1.0, ratio)           # widens with the reduction, so nothing
    table = []                          # in the source is skipped over
    for i in range(dst_len):
        centre = (i + 0.5) * ratio
        lo = max(0, int(math.floor(centre - support)))
        hi = min(src_len, int(math.ceil(centre + support)))
        taps, total = [], 0.0
        for s in range(lo, hi):
            weight = 1.0 - abs((s + 0.5 - centre) / support)
            if weight > 0.0:
                taps.append((s, weight))
                total += weight
        if not taps:                    # degenerate ratio; fall back to nearest
            s = min(src_len - 1, max(0, int(centre)))
            taps, total = [(s, 1.0)], 1.0
        table.append([(s, w / total) for s, w in taps])
    return table


def resize(rows, src_w, src_h, dst_w, dst_h):
    """Resample premultiplied RGBA rows, one separable pass per axis."""
    horizontal = _taps(src_w, dst_w)
    wide = []
    for row in rows:
        out = array("f", bytes(dst_w * 16))
        for x, taps in enumerate(horizontal):
            r = g = b = a = 0.0
            for s, w in taps:
                o = s * 4
                r += row[o] * w
                g += row[o + 1] * w
                b += row[o + 2] * w
                a += row[o + 3] * w
            o = x * 4
            out[o], out[o + 1], out[o + 2], out[o + 3] = r, g, b, a
        wide.append(out)

    vertical = _taps(src_h, dst_h)
    tall = []
    for taps in vertical:
        out = bytearray(dst_w * 4)
        for i in range(dst_w * 4):
            value = 0.0
            for s, w in taps:
                value += wide[s][i] * w
            out[i] = 0 if value <= 0.0 else (255 if value >= 255.0 else int(value + 0.5))
        tall.append(out)
    return tall


def halve(rows, size):
    """Box-average one mip level down: size -> size // 2, premultiplied."""
    half = size // 2
    out = []
    for y in range(half):
        top, bottom = rows[2 * y], rows[2 * y + 1]
        row = bytearray(half * 4)
        for i in range(half * 4):
            o = (i >> 2) * 8 + (i & 3)
            row[i] = (top[o] + top[o + 4] + bottom[o] + bottom[o + 4] + 2) >> 2
        out.append(row)
    return out


# --------------------------------------------------------------------------
# The tile
# --------------------------------------------------------------------------

def _span(y, left, top, size, radius):
    """The [x0, x1) span of a rounded square on scanline `y`, or None."""
    if y < top or y >= top + size:
        return None
    half = size / 2.0
    dy = abs(y - (top + half))
    inset = half - radius
    if dy <= inset:
        return (left, left + size)
    over = dy - inset                   # inside a corner: the circle's chord
    if over >= radius:
        return None
    dx = math.sqrt(radius * radius - over * over)
    return (left + radius - dx, left + size - radius + dx)


def coverage_mask(size):
    """An 8-bit alpha mask of the rounded square on Apple's grid."""
    scale = size / float(CANVAS)
    body = BODY * scale
    radius = CORNER * scale
    left = top = (size - body) / 2.0

    mask = []
    for py in range(size):
        acc = [0.0] * size
        for s in range(SUBSAMPLES):
            span = _span(py + (s + 0.5) / SUBSAMPLES, left, top, body, radius)
            if span is None:
                continue
            x0, x1 = span
            first, last = max(0, int(x0)), min(size, int(math.ceil(x1)))
            for x in range(first, last):
                acc[x] += min(x1, x + 1.0) - max(x0, float(x))
        row = bytearray(size)
        for x in range(size):
            row[x] = min(255, int(acc[x] * 255.0 / SUBSAMPLES + 0.5))
        mask.append(row)
    return mask


def compose(art, size):
    """Scale the artwork into the body and cut it to the rounded square."""
    scale = size / float(CANVAS)
    body = int(round(BODY * scale))
    left = top = (size - body) // 2
    mask = coverage_mask(size)

    rows = []
    for y in range(size):
        row = bytearray(size * 4)       # transparent, premultiplied
        if top <= y < top + body:
            source = art[y - top]
            alpha = mask[y]
            for x in range(body):
                a = alpha[left + x]
                if a == 0:
                    continue
                src, dst = x * 4, (left + x) * 4
                if a == 255:
                    row[dst:dst + 4] = source[src:src + 4]
                else:
                    for c in range(4):
                        row[dst + c] = (source[src + c] * a + 127) // 255
        rows.append(row)
    return rows


def unpremultiply(row, size):
    """Premultiplied RGBA -> straight RGBA, which is what PNG stores."""
    out = bytearray(row)
    for x in range(size):
        alpha = out[x * 4 + 3]
        if alpha == 0:
            out[x * 4:x * 4 + 3] = b"\x00\x00\x00"
        elif alpha != 255:
            for c in range(3):
                i = x * 4 + c
                out[i] = min(255, (out[i] * 255 + alpha // 2) // alpha)
    return out


# --------------------------------------------------------------------------
# PNG out
# --------------------------------------------------------------------------

def write_png(path, rows, size):
    raw = bytearray()
    for row in rows:
        raw.append(0)                   # filter type 0 (None)
        raw.extend(unpremultiply(row, size))

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


# --------------------------------------------------------------------------

def check_grid(rows, size):
    """Fail loudly if the icon has drifted back to filling its canvas.

    The margin is the whole point of the grid, and it is invisible in a diff of
    ten binary files: without this, "the icon looks a bit big" is something a
    person has to notice months later in a Dock full of correctly sized icons.
    """
    assert rows[0][3] == 0, f"the canvas corner is not transparent ({rows[0][3]})"
    middle = rows[size // 2]
    assert middle[3] == 0, f"the icon touches the canvas edge ({middle[3]})"
    expected = round((CANVAS - BODY) / 2 * (size / CANVAS))
    first = next(x for x in range(size) if middle[x * 4 + 3] > 0)
    assert abs(first - expected) <= 1, (
        f"body starts at {first}px, expected about {expected}px"
    )
    assert rows[size // 2][(size // 2) * 4 + 3] == 255, "the artwork did not land"
    print(f"  grid ok: {first}px margin on a {size}px master")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("out_dir", nargs="?", default=DEFAULT_OUT,
                        help="appiconset to write into")
    parser.add_argument("-s", "--source", default=DEFAULT_SOURCE,
                        help="master artwork (square PNG)")
    args = parser.parse_args()

    print(f"Reading {os.path.relpath(args.source, ROOT)}…")
    width, height, art = read_png(args.source)
    if width != height:
        sys.exit(f"the artwork must be square (got {width}x{height})")
    body = int(round(BODY))
    if width < body:
        print(f"  warning: {width}px artwork is smaller than the {body}px body;"
              " the largest icon will be upscaled")

    print(f"  {width}px artwork -> {body}px body on a {CANVAS}px canvas")
    fitted = resize(art, width, height, body, body)
    levels = {CANVAS: compose(fitted, CANVAS)}
    check_grid(levels[CANVAS], CANVAS)

    # One mip chain, shared by every size in the ladder: halving costs a
    # quarter of the level above it, so the whole chain is barely more work
    # than the first step. Resampling each size straight from the artwork
    # would be ten full passes over a megapixel and change.
    wanted = sorted({pt * scale for pt, scale in LADDER}, reverse=True)
    size = CANVAS
    while size > min(wanted):
        levels[size // 2] = halve(levels[size], size)
        size //= 2

    os.makedirs(args.out_dir, exist_ok=True)
    for pt, scale in LADDER:
        px = pt * scale
        name = f"icon_{pt}x{pt}@{scale}x.png"
        write_png(os.path.join(args.out_dir, name), levels[px], px)
        print(f"  wrote {name} ({px}px)")

    print("Done.")


if __name__ == "__main__":
    main()
