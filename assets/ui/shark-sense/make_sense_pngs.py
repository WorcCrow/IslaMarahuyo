"""Draws the Pating shark-sense indicator images (white + alpha, tinted in Roblox via ImageColor3).

sense_ring.png  512x512  thin soft circle (faint base ring)
sense_arc.png   512x512  ~36 degree glowing arc of the same circle, centred at 12 o'clock
sense_edge.png  128x512  vertical glow strip, bright at the left edge fading to clear
"""
import math
import os
import struct
import sys
import zlib

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)


def write_png(path, w, h, alpha_fn):
    rows = bytearray()
    for y in range(h):
        rows.append(0)  # filter: none
        for x in range(w):
            a = alpha_fn(x + 0.5, y + 0.5)
            a = 0 if a <= 0 else (255 if a >= 1 else int(a * 255 + 0.5))
            rows += bytes((255, 255, 255, a))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
    print("wrote", path, os.path.getsize(path), "bytes")


C = 256.0
R = 232.0  # ring radius; leaves room for the outer glow inside 512


def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def ring(x, y):
    d = math.hypot(x - C, y - C)
    core = math.exp(-((d - R) / 2.2) ** 2)
    glow = 0.35 * math.exp(-((d - R) / 9.0) ** 2)
    return core + glow


def arc(x, y):
    dx, dy = x - C, y - C
    d = math.hypot(dx, dy)
    # angle from 12 o'clock (image y grows downward, so "up" is -y)
    ang = abs(math.degrees(math.atan2(dx, -dy)))
    along = 1.0 - smoothstep(10.0, 20.0, ang)
    if along <= 0:
        return 0.0
    core = math.exp(-((d - R) / 4.5) ** 2)
    glow = 0.55 * math.exp(-((d - R) / 15.0) ** 2)
    return (core + glow) * along


def edge(x, y):
    across = max(0.0, 1.0 - x / 128.0) ** 2.2
    along = math.sin(math.pi * y / 512.0) ** 0.7
    return 0.95 * across * along


write_png(os.path.join(OUT, "sense_ring.png"), 512, 512, ring)
write_png(os.path.join(OUT, "sense_arc.png"), 512, 512, arc)
write_png(os.path.join(OUT, "sense_edge.png"), 128, 512, edge)
