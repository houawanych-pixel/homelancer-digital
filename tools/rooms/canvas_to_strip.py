#!/usr/bin/env python3
"""Unity Station 360 canvas (front view centred, back view split on the edges) -> one looping strip.
Joins use the Frogtown / Lantern Market method (location-sheet-panorama skill, approved Oct 18):
match the light, overlap the two edges, find the best cut line, multi-band blend. NO mirroring.
usage: canvas_to_strip.py canvas.png out.jpg [--overlap 240] [--joins joins.png] [--height 464]"""
import sys, numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, gaussian_filter1d

args = sys.argv
src, dst = args[1], args[2]
def opt(k, d): return type(d)(args[args.index(k) + 1]) if k in args else d
N, HH = opt("--overlap", 240), opt("--height", 464)

c = np.asarray(Image.open(src).convert("RGBA")); a = c[..., 3] > 0; W = c.shape[1]
cols = a.any(0)
def box(x0, x1):
    s = a[:, x0:x1]; xs = np.nonzero(s.any(0))[0]; ys = np.nonzero(s.any(1))[0]
    return x0 + xs[0], ys[0], x0 + xs[-1] + 1, ys[-1] + 1
# runs of filled columns: [back-right-half] gap [front] gap [back-left-half]
edges = np.nonzero(np.diff(cols.astype(int)))[0] + 1
l_end, f_start, f_end, r_start = edges[:4]
fb, bl, br = box(f_start, f_end), box(0, l_end), box(r_start, W)
img = Image.fromarray(c[..., :3])
def view(b):
    v = img.crop(b); return v.resize((round(v.width * HH / v.height), HH), Image.LANCZOS)
front = np.asarray(view(fb)).astype(np.float32)
back = np.concatenate([np.asarray(view(br)), np.asarray(view(bl))], 1).astype(np.float32)  # back view, whole again

RAMP, BAND = 360, 110
def match_light(left, right):
    l = gaussian_filter1d(left[:, -BAND:].mean(axis=1), 45, axis=0); r = gaussian_filter1d(right[:, :BAND].mean(axis=1), 45, axis=0)
    avg = (l + r) * 0.5
    gl = np.clip(avg / np.maximum(l, 8.0), 0.65, 1.5)[:, None, :]; gr = np.clip(avg / np.maximum(r, 8.0), 0.65, 1.5)[:, None, :]
    k = (np.arange(RAMP) / RAMP)[None, :, None] ** 2
    left = left.copy(); right = right.copy()
    left[:, -RAMP:] *= 1 + (gl - 1) * k; right[:, :RAMP] *= 1 + (gr - 1) * k[:, ::-1]
    return left, right
front, back = match_light(front, back); back, front = match_light(back, front)

def best_cut(p, q):
    cost = gaussian_filter(np.abs(p - q).sum(axis=2), 2.0); n = cost.shape[1]
    cost += (np.abs(np.arange(n) - n / 2) / (n / 2))[None, :] ** 2 * cost.mean() * 1.5
    acc = cost.copy()
    for y in range(1, acc.shape[0]):
        pr = acc[y - 1]; acc[y] += np.minimum(pr, np.minimum(np.r_[pr[0], pr[:-1]], np.r_[pr[1:], pr[-1]]))
    path = np.zeros(acc.shape[0], int); path[-1] = int(np.argmin(acc[-1]))
    for y in range(acc.shape[0] - 2, -1, -1):
        x = path[y + 1]; lo, hi = max(0, x - 1), min(n, x + 2); path[y] = lo + int(np.argmin(acc[y, lo:hi]))
    return path
def join(p, q):
    mask = (np.arange(p.shape[1])[None, :] < best_cut(p, q)[:, None]).astype(np.float32)
    res = np.zeros_like(p); pa, pb = p, q
    for s in (1.0, 2.5, 6.0, 14.0):
        ga, gb = gaussian_filter(pa, (s, s, 0)), gaussian_filter(pb, (s, s, 0)); m = gaussian_filter(mask, s * 1.2)[:, :, None]
        res += (pa - ga) * m + (pb - gb) * (1 - m); pa, pb = ga, gb
    m = gaussian_filter(mask, 26.0)[:, :, None]
    return res + pa * m + pb * (1 - m)

strip = np.concatenate([front[:, N:-N], join(front[:, -N:], back[:, :N]), back[:, N:-N], join(back[:, -N:], front[:, :N])], 1)
res = np.clip(strip, 0, 255).astype(np.uint8)
Image.fromarray(res).save(dst, quality=92)
j1 = front.shape[1] - 2 * N + N // 2; j2 = front.shape[1] - N + back.shape[1] - 2 * N + N // 2
print(dst, res.shape[1], "x", res.shape[0], "joins at", j1, j2)
if "--joins" in args:
    cut = [np.roll(res, 420 - j, axis=1)[:, :840] for j in (j1, j2)]
    Image.fromarray(np.concatenate([cut[0], np.zeros((8, 840, 3), np.uint8), cut[1]], 0)).save(opt("--joins", ""))
