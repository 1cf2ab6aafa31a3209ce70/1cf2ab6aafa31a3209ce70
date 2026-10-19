#!/usr/bin/env python3
"""Render an original geometric 1024-pixel app icon as an opaque PNG.

Standard library only. Each design is plain geometry in project colors, so
icons are reproducible from this script and need no image tools or assets.
"""
import argparse
import hashlib
import struct
from pathlib import Path
import zlib

SIZE = 1024


def png(pixels):
    """Opaque 8-bit RGB PNG; the App Store icon must have no alpha channel."""
    raw = b"".join(b"\x00" + bytes(row) for row in pixels)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def hex_color(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def canvas(background):
    return [bytearray(background * SIZE) for _ in range(SIZE)]


def fill(pixels, shape, color):
    """Paint a shape's pixels inside its bounding box, with 4x4 supersampled edges."""
    inside, (left, top, right, bottom) = shape
    for y in range(max(0, int(top)), min(SIZE, int(bottom) + 1)):
        row = pixels[y]
        for x in range(max(0, int(left)), min(SIZE, int(right) + 1)):
            hits = 0
            if inside(x + 0.5, y + 0.5):
                # Interior fast path: corners agree, so the pixel is fully covered.
                if all(inside(x + dx, y + dy) for dx in (0.05, 0.95) for dy in (0.05, 0.95)):
                    hits = 16
            if hits == 0:
                hits = sum(inside(x + (i + 0.5) / 4, y + (j + 0.5) / 4) for i in range(4) for j in range(4))
                if hits == 0:
                    continue
            alpha = hits / 16
            for channel in range(3):
                old = row[3 * x + channel]
                row[3 * x + channel] = round(old + (color[channel] - old) * alpha)


def rounded_square(cx, cy, half, radius):
    def inside(x, y):
        dx, dy = abs(x - cx) - (half - radius), abs(y - cy) - (half - radius)
        if dx <= 0 or dy <= 0:
            return abs(x - cx) <= half and abs(y - cy) <= half
        return dx * dx + dy * dy <= radius * radius
    return inside, (cx - half, cy - half, cx + half, cy + half)


def disc(cx, cy, radius):
    return (lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius,
            (cx - radius, cy - radius, cx + radius, cy + radius))


def ring(cx, cy, outer, inner):
    return (lambda x, y: inner * inner <= (x - cx) ** 2 + (y - cy) ** 2 <= outer * outer,
            (cx - outer, cy - outer, cx + outer, cy + outer))


def design_disc(background, foreground):
    """A centered disc inside a halo ring."""
    pixels = canvas(background)
    fill(pixels, ring(512, 512, 380, 352), foreground)
    fill(pixels, disc(512, 512, 200), foreground)
    return pixels


def design_blocks(background, colors):
    """A 3x3 board of rounded blocks; colors cycle through the palette."""
    pixels = canvas(background)
    step, half = 280, 118
    for row in range(3):
        for column in range(3):
            cx, cy = 512 + (column - 1) * step, 512 + (row - 1) * step
            fill(pixels, rounded_square(cx, cy, half, 36), colors[(row * 3 + column) % len(colors)])
    return pixels


def design_frames(seed):
    """Placeholder for a new title: nested frames in a hue derived from its ID."""
    digest = hashlib.sha256(seed.encode()).digest()
    hue = digest[0] / 255
    import colorsys
    def color(lightness, saturation):
        return tuple(round(c * 255) for c in colorsys.hls_to_rgb(hue, lightness, saturation))
    pixels = canvas(color(0.92, 0.35))
    fill(pixels, rounded_square(512, 512, 360, 96), color(0.45, 0.55))
    fill(pixels, rounded_square(512, 512, 250, 64), color(0.92, 0.35))
    fill(pixels, rounded_square(512, 512, 140, 36), color(0.45, 0.55))
    return pixels


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    designs = parser.add_mutually_exclusive_group(required=True)
    designs.add_argument("--disc", nargs=2, metavar=("BACKGROUND", "FOREGROUND"))
    designs.add_argument("--blocks", nargs="+", metavar="COLOR", help="Background, then block colors")
    designs.add_argument("--frames", metavar="TITLE_ID", help="Placeholder hue derived from a title ID")
    args = parser.parse_args()
    if args.disc:
        pixels = design_disc(hex_color(args.disc[0]), hex_color(args.disc[1]))
    elif args.blocks:
        pixels = design_blocks(hex_color(args.blocks[0]), [hex_color(c) for c in args.blocks[1:]])
    else:
        pixels = design_frames(args.frames)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(png(pixels))


if __name__ == "__main__":
    main()
