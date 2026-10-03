#!/usr/bin/env python3
"""Turn a PORTRAIT (or any non-2:1) space picture into a 360 sky (equirectangular 2:1).
The picture is placed undistorted-ish as the feature in one direction of the sky (default 110 x 176 degrees, straight
ahead) and feathered into a dark background made from the picture's own colours (blurred, mirrored so it has no
seam), with extra stars sprinkled where the picture does not reach. Run tools/sky/fix_pano.py afterwards for the poles.
usage: portrait_to_pano.py in.jpg out.png [--width 2048] [--lon 110] [--lat 176] [--seed 1] [--bg auto]"""
import argparse
import numpy as np
from PIL import Image, ImageFilter

ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("dst")
ap.add_argument("--width", type=int, default=2048)
ap.add_argument("--lon", type=float, default=130.0)
ap.add_argument("--lat", type=float, default=176.0)
ap.add_argument("--seed", type=int, default=1)
ap.add_argument("--echo", type=float, default=0.55)
ap.add_argument("--bg", default="0.45", help="background brightness, or 'auto' = match the picture's own edges (no visible frame)")
a = ap.parse_args()
W = a.width; H = W // 2
src = Image.open(a.src).convert("RGB")
# background: the picture, very blurred and darkened, mirrored left-right so the wrap has no line
half = src.resize((W // 2, H), Image.LANCZOS).filter(ImageFilter.GaussianBlur(W / 14))
bg = Image.new("RGB", (W, H))
bg.paste(half.transpose(Image.FLIP_LEFT_RIGHT), (0, 0)); bg.paste(half, (W // 2, 0))
bg = bg.filter(ImageFilter.GaussianBlur(W / 40))
out = np.asarray(bg).astype(np.float32)
if a.bg == "auto":
    sa = np.asarray(src).astype(np.float32); r = max(4, int(min(sa.shape[:2]) * 0.06))
    ring = np.concatenate([sa[:r].reshape(-1, 3), sa[-r:].reshape(-1, 3), sa[:, :r].reshape(-1, 3), sa[:, -r:].reshape(-1, 3)])
    out *= float(np.clip(np.median(ring.mean(1)) / max(out.mean(), 1.0), 0.06, 0.45))
else:
    out *= float(a.bg)
# stars on the background (the picture brings its own)
rng = np.random.default_rng(a.seed)
n = int(W * H * 0.0011)
ys = np.arccos(rng.uniform(-1, 1, n)) / np.pi * H        # uniform on the sphere, not on the image
xs = rng.uniform(0, W, n)
b = rng.random(n) ** 3
col = np.stack([0.75 + b * 0.25, 0.8 + b * 0.2, np.ones(n)], 1) * (0.35 + b * 0.9)[:, None] * 255
stars = np.zeros_like(out)
yi = np.clip(ys.astype(int), 0, H - 1); xi = xs.astype(int) % W
stars[yi, xi] = col
big = b > 0.8
stars[yi[big], (xi[big] + 1) % W] = col[big] * 0.5
# the feature: the picture across `lon` x `lat` degrees, centred straight ahead (middle of the panorama)
fw = int(W * a.lon / 360.0); fh = int(H * a.lat / 180.0)
feat = np.asarray(src.resize((fw, fh), Image.LANCZOS)).astype(np.float32)
u = np.linspace(-1, 1, fw)[None, :]; v = np.linspace(-1, 1, fh)[:, None]
def edge(t, start): return np.clip((1 - np.abs(t)) / (1 - start), 0, 1)
al = edge(u, 0.55) * edge(v, 0.7)
al = (al * al * (3 - 2 * al))[:, :, None]
x0 = (W - fw) // 2; y0 = (H - fh) // 2
cov = np.zeros((H, W, 1), np.float32); cov[y0:y0 + fh, x0:x0 + fw] = al
# an echo behind the player: the same clouds turned upside down and mirrored, dimmer, so the sky is not empty there
if a.echo > 0:
    ef = feat[::-1, ::-1] * a.echo; ea = al[::-1, ::-1]
    lay = np.zeros_like(out); la = np.zeros((H, W, 1), np.float32)
    lay[y0:y0 + fh, x0:x0 + fw] = ef; la[y0:y0 + fh, x0:x0 + fw] = ea
    lay = np.roll(lay, W // 2, axis=1); la = np.roll(la, W // 2, axis=1)
    out = out + stars * (1 - np.maximum(cov, la))
    out = out * (1 - la) + lay * la
else:
    out = out + stars * (1 - cov)
out[y0:y0 + fh, x0:x0 + fw] = out[y0:y0 + fh, x0:x0 + fw] * (1 - al) + feat * al
Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(a.dst)
print(a.dst, W, H)
