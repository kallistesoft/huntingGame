#!/usr/bin/env python3
"""Writes the Android notification small icon: a white arrowhead on a
transparent background (status-bar icons must be white + alpha).

Output: assets/NotificationSchedulerPlugin/android/drawable/ic_default_notification.png
The NotificationScheduler export plugin copies that folder into
android/build/res at export time. Pure standard library, no Pillow."""
import struct
import zlib
from pathlib import Path

SIZE = 96
OUT = Path(__file__).resolve().parent.parent / "assets/NotificationSchedulerPlugin/android/drawable/ic_default_notification.png"


def inside(x: float, y: float) -> bool:
    """A spearhead: a triangle pointing up with a short shaft below."""
    cx = SIZE / 2
    # Head: apex at y=10, base at y=58, half-width 26.
    if 10 <= y <= 58:
        half = 26 * (y - 10) / 48
        if abs(x - cx) <= half:
            return True
    # Shaft: from y=56 to y=88, width 10.
    if 56 <= y <= 88 and abs(x - cx) <= 5:
        return True
    return False


def coverage(px: int, py: int) -> float:
    """4x4 supersampling for soft edges."""
    hits = 0
    for sy in range(4):
        for sx in range(4):
            if inside(px + (sx + 0.5) / 4, py + (sy + 0.5) / 4):
                hits += 1
    return hits / 16


def png(width: int, height: int, rows: bytes) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # 8-bit RGBA
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")


def main() -> None:
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # filter: none
        for x in range(SIZE):
            a = round(255 * coverage(x, y))
            rows += bytes((255, 255, 255, a))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(png(SIZE, SIZE, bytes(rows)))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
