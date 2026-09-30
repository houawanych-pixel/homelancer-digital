#!/usr/bin/env python3
"""Turn a ground photo/texture into game-ready tiling terrain detail maps.

  python3 tools/terrain/make_ground.py in.png assets/terrain/<name>   [--size 1024]

Writes <name>_albedo.jpg (seamless in both directions) and <name>_normal.png (bump detail derived from the
picture's brightness: pebbles and cracks stand out). The terrain shader tiles these in world space and tints them
with each biome's colours, so one ground texture serves every biome.
"""
import argparse
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, sobel


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def fold(a, frac, axis):
    """Make the two edges along `axis` meet: cross-fade the last strip over the first (overlap tiling)."""
    n = a.shape[axis]
    b = max(8, int(n * frac))
    a = np.moveaxis(a, axis, 0)
    t = smooth(np.arange(b) / (b - 1)).reshape(-1, *([1] * (a.ndim - 1)))
    out = a[: n - b].copy()
    out[:b] = a[n - b:] * (1 - t) + a[:b] * t
    return np.moveaxis(out, 0, axis)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out_prefix")
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--strength", type=float, default=2.5)
    a = ap.parse_args()
    img = np.asarray(Image.open(a.src).convert("RGB")).astype(np.float32)
    img = fold(fold(img, 0.08, 1), 0.08, 0)
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).resize((a.size, a.size), Image.LANCZOS)
    im.save(a.out_prefix + "_albedo.jpg", quality=88)
    # height from brightness (wrap so the normal map tiles too), then a normal map
    h = np.asarray(im.convert("L")).astype(np.float32) / 255.0
    h = gaussian_filter(h, 1.2, mode="wrap") - gaussian_filter(h, 24, mode="wrap") * 0.7
    dx = sobel(h, axis=1, mode="wrap") * a.strength
    dy = sobel(h, axis=0, mode="wrap") * a.strength
    n = np.stack([-dx, -dy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(a.out_prefix + "_normal.png")
    avg = np.asarray(im).reshape(-1, 3).mean(0) / 255.0
    print("wrote", a.out_prefix, "average colour", np.round(avg, 3))


if __name__ == "__main__":
    main()
