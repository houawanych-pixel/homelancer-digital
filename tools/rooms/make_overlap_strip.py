#!/usr/bin/env python3
"""Intro collage: front view (top half) and back view (bottom half) joined into one looping strip by OVERLAPPING
them: at each join the back view is laid over the front view for `overlap` pixels and faded in with a transparency
ramp, so one melts into the other (the owner's method, Oct 2). No mirroring, no colour changes.
The two halves can differ in height: the back is scaled by `scale`, and the top of the front is trimmed
(front_start) so the ground lines of the two meet; both end up the same height.
usage: make_overlap_strip.py in.png out.jpg front_start front_end back_start scale [--overlap 160] [--preview joins.png]
   intro collage (Oct 2): make_overlap_strip.py collage.png out.jpg 44 521 537 1.274"""
import sys
import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
f0, fe, bs, scale = int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), float(sys.argv[6])
N = int(sys.argv[sys.argv.index("--overlap") + 1]) if "--overlap" in sys.argv else 160
im = Image.open(src).convert("RGB"); W, H = im.size
f = np.asarray(im.crop((0, f0, W, fe))).astype(np.float32); fe -= f0
bim = im.crop((0, bs, W, H)); bim = bim.resize((round(W * scale), round((H - bs) * scale)), Image.LANCZOS)
b = np.asarray(bim).astype(np.float32)
b = b[:fe]
if b.shape[0] < fe: b = np.concatenate([b, np.repeat(b[-1:], fe - b.shape[0], 0)], 0)
ramp = (np.arange(N) / (N - 1.0))[None, :, None]
ramp = ramp * ramp * (3 - 2 * ramp)
mid = f[:, -N:] * (1 - ramp) + b[:, :N] * ramp            # front fades into back
wrap = b[:, -N:] * (1 - ramp) + f[:, :N] * ramp           # back fades into front (the loop point)
strip = np.concatenate([f[:, N:-N], mid, b[:, N:-N], wrap], 1)
out = np.clip(strip, 0, 255).astype(np.uint8)
Image.fromarray(out).save(dst, quality=88)
print(dst, out.shape[1], out.shape[0])
if "--preview" in sys.argv:
    j1 = f.shape[1] - 2 * N + N // 2; j2 = out.shape[1] - N // 2
    cut = [np.roll(out, 420 - c, axis=1)[:, :840] for c in (j1, j2)]
    Image.fromarray(np.concatenate([cut[0], np.zeros((8, 840, 3), np.uint8), cut[1]], 0)).save(sys.argv[sys.argv.index("--preview") + 1])
