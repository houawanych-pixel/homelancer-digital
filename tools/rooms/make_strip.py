#!/usr/bin/env python3
"""Station room panorama: one 16:9 picture with the FRONT view on the top half and the BACK view on the bottom half
becomes one long strip [front | bridge | back | bridge] that the game scrolls around forever (scripts/rooms.gd).

The two views are separate paintings, so their edges never line up. Each join gets a BRIDGE, built the way a retoucher
would: 1) match the lighting of the two sides; 2) continue each side past its edge by MIRRORING it (a mirror image
always lines up with what it mirrors); 3) where the two mirrored continuations overlap, cut along the path where they
differ least and blend across it (fine detail blends over a few pixels, broad colour over a wide band).

usage: make_strip.py in.png out.jpg [top0 top1 bot0 bot1] [--preview joins.png]
       make_strip.py in.png out.jpg --single [--preview joins.png]     (one view, wraps onto itself)"""
import sys
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, gaussian_filter1d

HH = 464        # height of the strip
BRIDGE = 160    # width of each bridge (the game knows this number: Rooms.BRIDGE)
RAMP, BAND = 360, 110

def match_light(left, right):
    """Ease the colour of both sides toward their shared average, row by row, over RAMP px."""
    l = gaussian_filter1d(left[:, -BAND:].mean(axis=1), 45, axis=0); r = gaussian_filter1d(right[:, :BAND].mean(axis=1), 45, axis=0)
    avg = (l + r) * 0.5
    gl = np.clip(avg / np.maximum(l, 8.0), 0.65, 1.5)[:, None, :]; gr = np.clip(avg / np.maximum(r, 8.0), 0.65, 1.5)[:, None, :]
    k = (np.arange(RAMP) / RAMP)[None, :, None] ** 2
    left = left.copy(); right = right.copy()
    left[:, -RAMP:] *= 1 + (gl - 1) * k
    right[:, :RAMP] *= 1 + (gr - 1) * k[:, ::-1]
    return left, right

def best_cut(a, b):
    """Top-to-bottom path through the overlap where a and b differ least (dynamic programming)."""
    cost = gaussian_filter(np.abs(a - b).sum(axis=2), 2.0)
    n = cost.shape[1]
    cost += (np.abs(np.arange(n) - n / 2) / (n / 2))[None, :] ** 2 * cost.mean() * 1.5   # prefer the middle
    acc = cost.copy(); H = cost.shape[0]
    for y in range(1, H):
        p = acc[y - 1]
        acc[y] += np.minimum(p, np.minimum(np.r_[p[0], p[:-1]], np.r_[p[1:], p[-1]]))
    path = np.zeros(H, int); path[-1] = int(np.argmin(acc[-1]))
    for y in range(H - 2, -1, -1):
        x = path[y + 1]; lo = max(0, x - 1); hi = min(n, x + 2)
        path[y] = lo + int(np.argmin(acc[y, lo:hi]))
    return path

def bridge(left, right):
    """The piece that goes between `left` and `right`."""
    a = left[:, ::-1][:, :BRIDGE]            # left, continued by its mirror image
    b = right[:, :BRIDGE][:, ::-1]           # right, continued (backwards) by its mirror image
    path = best_cut(a, b)
    mask = (np.arange(BRIDGE)[None, :] < path[:, None]).astype(np.float32)   # 1 = take a
    out = np.zeros_like(a); pa, pb = a, b
    for s in (1.0, 2.5, 6.0, 14.0):          # blend fine detail narrowly, broad colour widely
        ga = gaussian_filter(pa, (s, s, 0)); gb = gaussian_filter(pb, (s, s, 0))
        m = gaussian_filter(mask, s * 1.2)[:, :, None]
        out += (pa - ga) * m + (pb - gb) * (1 - m)
        pa, pb = ga, gb
    m = gaussian_filter(mask, 26.0)[:, :, None]
    return out + pa * m + pb * (1 - m)

src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB"); W, H = im.size
if "--single" in sys.argv:
    # ONE view (no front/back split): keep its full size and bridge its right edge back to its left edge
    HH = H
    one = np.asarray(im).astype(np.float32)
    a2, b2 = match_light(one, one)            # right edge eased toward the left edge's light, and the reverse
    one[:, -RAMP:] = a2[:, -RAMP:]; one[:, :RAMP] = b2[:, :RAMP]
    strip = np.concatenate([one, bridge(one, one)], axis=1)
    joins = (W + BRIDGE // 2,)
else:
    if len(sys.argv) >= 7 and sys.argv[3].isdigit(): t0, t1, b0, b1 = [int(v) for v in sys.argv[3:7]]
    else: t0, t1, b0, b1 = 0, H // 2 - 6, H // 2 + 6, H
    front = np.asarray(im.crop((0, t0, W, t1)).resize((W, HH), Image.LANCZOS)).astype(np.float32)
    back = np.asarray(im.crop((0, b0, W, b1)).resize((W, HH), Image.LANCZOS)).astype(np.float32)
    front, back = match_light(front, back)       # the join in the middle
    back, front = match_light(back, front)       # the join at the wrap
    strip = np.concatenate([front, bridge(front, back), back, bridge(back, front)], axis=1)
    joins = (W + BRIDGE // 2, 2 * W + BRIDGE + BRIDGE // 2)
out = np.clip(strip, 0, 255).astype(np.uint8)
Image.fromarray(out).save(dst, quality=88)
print(dst, out.shape[1], out.shape[0])
if "--preview" in sys.argv:   # the two joins, cut out, to check by eye
    cut = [np.roll(out, 420 - c, axis=1)[:, :840] for c in joins]
    cut.append(cut[0])
    Image.fromarray(np.concatenate([cut[0], np.zeros((8, 840, 3), np.uint8), cut[1]], 0)).save(sys.argv[sys.argv.index("--preview") + 1])
