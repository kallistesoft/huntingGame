#!/usr/bin/env python3
"""Writes icon.png (512x512): a dark-green disc with an orange spearhead,
matching the UI palette. Pure standard library; see gen_notification_icon.py
for the PNG writer it reuses."""
import math
from pathlib import Path

import importlib.util

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("notif_icon", HERE / "gen_notification_icon.py")
notif_icon = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notif_icon)

SIZE = 512
OUT = HERE.parent / "icon.png"
BG = (27, 42, 33)       # Style.BG
ACCENT = (242, 165, 65)  # Style.ACCENT
SHAFT = (160, 112, 63)


def spear(x: float, y: float):
    """Returns the colour under a point of the spear, or None."""
    cx = SIZE / 2
    # Head: triangle from y=90 (apex) to y=300 (base), half-width 110.
    if 90 <= y <= 300:
        half = 110 * (y - 90) / 210
        if abs(x - cx) <= half:
            return ACCENT
    # Shaft from y=290 to y=440, width 44.
    if 290 <= y <= 440 and abs(x - cx) <= 22:
        return SHAFT
    return None


def pixel(px: int, py: int):
    """4x4 supersampled RGBA at one pixel."""
    r = g = b = a = 0.0
    for sy in range(4):
        for sx in range(4):
            x = px + (sx + 0.5) / 4
            y = py + (sy + 0.5) / 4
            d = math.hypot(x - SIZE / 2, y - SIZE / 2)
            if d > SIZE / 2 - 2:
                continue  # transparent outside the disc
            c = spear(x, y) or BG
            r += c[0]
            g += c[1]
            b += c[2]
            a += 255
    return (round(r / 16), round(g / 16), round(b / 16), round(a / 16))


def main() -> None:
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)
        for x in range(SIZE):
            rows += bytes(pixel(x, y))
    OUT.write_bytes(notif_icon.png(SIZE, SIZE, bytes(rows)))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
