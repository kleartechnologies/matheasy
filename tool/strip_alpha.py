#!/usr/bin/env python3
"""Convert the raw-RGBA iOS icons emitted by generate_app_icons.dart into
alpha-free RGB PNGs (App Store Connect rejects icons with an alpha channel).

The Concept C iOS tile is fully opaque, so dropping the alpha channel is exact —
no compositing needed. Uses only the Python standard library (zlib/struct), so
there is no dependency on Pillow / ImageMagick.

Run:  python3 tool/strip_alpha.py
"""
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / ".dart_tool" / "icon_rgba"


def _chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def write_rgb_png(path: Path, rgba: bytes, size: int) -> None:
    # Build filtered scanlines: filter byte 0 + RGB triples (drop alpha).
    rows = bytearray()
    stride = size * 4
    for y in range(size):
        rows.append(0)  # filter: None
        row = rgba[y * stride : (y + 1) * stride]
        rows.extend(b"".join(bytes(row[x : x + 3]) for x in range(0, stride, 4)))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)  # RGB, 8-bit
    png = (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(bytes(rows), 9))
        + _chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def main() -> None:
    manifest = (RAW_DIR / "manifest.txt").read_text().strip().splitlines()
    for line in manifest:
        raw_name, size_s, out_rel = line.split(" ", 2)
        size = int(size_s)
        rgba = (RAW_DIR / raw_name).read_bytes()
        expected = size * size * 4
        if len(rgba) != expected:
            raise SystemExit(f"{raw_name}: got {len(rgba)} bytes, want {expected}")
        out = ROOT / out_rel
        write_rgb_png(out, rgba, size)
        print(f"  wrote {out_rel} ({out.stat().st_size} bytes, RGB no-alpha)")


if __name__ == "__main__":
    main()
