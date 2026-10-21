#!/usr/bin/env python3
"""Strip (front|bridge|back|bridge, 360 deg wide) -> 2:1 equirectangular. The painted band sits on the horizon
untouched; above and below, the ceiling and floor are continued by stretching the edge rows outward and softening
them toward the pole (nothing new is painted: no people, signs or props are added)."""
import sys, numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
src, dst = sys.argv[1], sys.argv[2]
a = np.asarray(Image.open(src).convert('RGB')).astype(np.float32)
H, W = a.shape[:2]
OH = W // 2
pad_top = (OH - H) // 2
pad_bot = OH - H - pad_top
def cap(edge_rows, n, flip):
    # edge_rows: rows nearest the pad, ordered from the band edge outward (mirror)
    e = edge_rows
    out = np.zeros((n, W, 3), np.float32)
    m = e.shape[0]
    pole = gaussian_filter(e.mean(axis=0), (60, 0))   # each column's average colour, softened sideways
    pole = np.repeat(pole.mean(axis=0, keepdims=True), W, axis=0) * 0.35 + pole * 0.65
    for i in range(n):
        k = i / max(1, n - 1)
        src_row = min(m - 1, int((k ** 0.7) * (m - 1)))
        row = e[src_row]
        s = 4 + 70 * k
        row = gaussian_filter(row, (s, 0))
        t = min(1.0, k * 2.0) ** 1.2
        out[i] = row * (1 - t) + pole * t
        out[i] *= 1.0 - 0.55 * k      # darker toward the pole
    return out[::-1] if flip else out
top = cap(a[:120][::-1], pad_top, True)        # mirrored ceiling, stretched up
bot = cap(a[-120:], pad_bot, False)            # mirrored floor, stretched down
img = np.concatenate([top, a, bot], axis=0)
# soften the two seams a little (the band itself is kept as painted)
for y0 in (pad_top, pad_top + H):
    seg = img[y0 - 10:y0 + 10]
    img[y0 - 10:y0 + 10] = gaussian_filter(seg, (3, 0, 0)) * 0.5 + seg * 0.5
# the pano wraps left-right: shift so the FRONT view's middle is at the image centre (forward = centre)
img = np.roll(img, W // 2 - 836, axis=1)
Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(dst, optimize=True)
print(dst, img.shape[1], img.shape[0])
