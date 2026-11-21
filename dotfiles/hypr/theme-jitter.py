#!/usr/bin/env python3
"""Jitter a palette of hex colors by shifting saturation and lightness.

Usage:
    theme-jitter.py [--seed N] [--sat PP] [--light PP] [--count N] HEX [HEX ...]

Prints jittered colors one per line, in the same order as input.
With --count N, prints N palettes instead, one palette per line.
Default: saturation ±5 pp, lightness ±5 pp.
"""
import argparse
import colorsys
import os
import random
import sys


def parse_hex(s: str) -> tuple[float, float, float]:
    s = s.lstrip("#")
    if len(s) != 6:
        raise ValueError(f"bad hex: {s!r}")
    r = int(s[0:2], 16) / 255.0
    g = int(s[2:4], 16) / 255.0
    b = int(s[4:6], 16) / 255.0
    return r, g, b


def to_hex(r: float, g: float, b: float) -> str:
    r = max(0.0, min(1.0, r))
    g = max(0.0, min(1.0, g))
    b = max(0.0, min(1.0, b))
    return "#{:02x}{:02x}{:02x}".format(round(r * 255), round(g * 255), round(b * 255))


def jitter(hex_color: str, rng: random.Random, sat_pp: float, light_pp: float) -> str:
    r, g, b = parse_hex(hex_color)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    s = max(0.0, min(1.0, s + rng.uniform(-sat_pp, sat_pp) / 100.0))
    l = max(0.0, min(1.0, l + rng.uniform(-light_pp, light_pp) / 100.0))
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return to_hex(r, g, b)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--sat", type=float, default=5.0, help="max saturation shift in percentage points")
    ap.add_argument("--light", type=float, default=5.0, help="max lightness shift in percentage points")
    ap.add_argument("--count", type=int, default=None,
                    help="print COUNT palettes, one per line, colors space-separated")
    ap.add_argument("colors", nargs="+")
    args = ap.parse_args()

    seed = args.seed if args.seed is not None else int.from_bytes(os.urandom(8), "big")
    rng = random.Random(seed)

    if args.count is not None:
        for _ in range(args.count):
            print(" ".join(jitter(c, rng, args.sat, args.light) for c in args.colors))
        return 0

    for c in args.colors:
        print(jitter(c, rng, args.sat, args.light))
    return 0


if __name__ == "__main__":
    sys.exit(main())
