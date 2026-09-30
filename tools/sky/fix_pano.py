#!/usr/bin/env python3
"""Make a nebula image into a seamless 360 sky panorama (equirectangular, 2:1).

  python3 fix_pano.py in.png out.jpg [--width 4096] [--seam 0.07] [--pole 0.14] [--preview views.jpg]

What it does:
  1. Left/right seam: cross-fades the right edge strip into the left edge (overlap
     tiling), after matching the low-frequency colour of the two edges, so the
     wrap point behind the player has no line.
  2. Poles (straight up/down): blurs rows sideways more and more toward the top and
     bottom (the rows are stretched there) and fades them to the row's average
     colour, so there is no pinch or swirl when looking up or down.
  3. Resizes to exactly width x width/2.
--preview renders forward, behind (the seam), up and down views to check it.
"""
import argparse
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter1d, gaussian_filter


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def fix_seam(a, frac):
    h, w, _ = a.shape
    b = max(8, int(w * frac))
    # 1) match low-frequency colour across the seam: offset ramps over a wide band
    edge = 6
    left = a[:, :edge].mean(1)
    right = a[:, -edge:].mean(1)
    d = gaussian_filter1d(right - left, sigma=h * 0.03, axis=0)  # (h,3)
    band = int(w * 0.25)
    ramp = 1 - smooth(np.arange(band) / band)
    a = a.copy()
    a[:, :band] += (d[:, None, :] * 0.5) * ramp[None, :, None]
    a[:, -band:] -= (d[:, None, :] * 0.5) * ramp[::-1][None, :, None]
    # 2) overlap tiling: fold the last b columns over the first b
    t = smooth(np.arange(b) / (b - 1))[None, :, None]
    out = a[:, : w - b].copy()
    out[:, :b] = a[:, w - b:] * (1 - t) + a[:, :b] * t
    return out


def fix_poles(a, frac):
    h, w, _ = a.shape
    band = max(4, int(h * frac))
    out = a.copy()
    for y in list(range(band)) + list(range(h - band, h)):
        lat = (0.5 - (y + 0.5) / h) * np.pi
        c = max(np.cos(lat), 1e-3)
        k = (y if y < band else h - 1 - y) / band  # 0 at pole, 1 at band edge
        row = a[y]
        sig = min(w / 4, 1.5 / c)  # uniform angular blur -> wider in pixels near poles
        # wrap-around blur
        pad = np.concatenate([row, row, row], 0)
        blurred = gaussian_filter1d(pad, sig, axis=0)[w:2 * w]
        mean = row.mean(0)
        s = smooth(k)
        m = smooth(np.clip(k * 3, 0, 1))  # last third near the pole goes to mean colour
        out[y] = row * s + blurred * (1 - s)
        out[y] = out[y] * m + mean * (1 - m)
    return out


def view(eq, yaw, pitch, fov=90, size=512):
    h, w, _ = eq.shape
    f = 0.5 * size / np.tan(np.radians(fov) / 2)
    xs, ys = np.meshgrid(np.arange(size) - size / 2 + 0.5, np.arange(size) - size / 2 + 0.5)
    d = np.stack([xs, -ys, np.full_like(xs, f)], -1)
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    p, yw = np.radians(pitch), np.radians(yaw)
    # pitch about x, then yaw about y
    y1 = d[..., 1] * np.cos(p) + d[..., 2] * np.sin(p)
    z1 = -d[..., 1] * np.sin(p) + d[..., 2] * np.cos(p)
    x2 = d[..., 0] * np.cos(yw) + z1 * np.sin(yw)
    z2 = -d[..., 0] * np.sin(yw) + z1 * np.cos(yw)
    lon = np.arctan2(x2, z2)
    lat = np.arcsin(np.clip(y1, -1, 1))
    u = ((lon / (2 * np.pi) + 0.5) * w) % w
    v = np.clip((0.5 - lat / np.pi) * h, 0, h - 1)
    # bilinear with wrap
    x0 = np.floor(u).astype(int); y0 = np.floor(v).astype(int)
    fx = (u - x0)[..., None]; fy = (v - y0)[..., None]
    x1 = (x0 + 1) % w; y1i = np.minimum(y0 + 1, h - 1); x0 %= w
    c = (eq[y0, x0] * (1 - fx) + eq[y0, x1] * fx) * (1 - fy) + (eq[y1i, x0] * (1 - fx) + eq[y1i, x1] * fx) * fy
    return c


def preview(eq, path, before=None):
    from PIL import ImageDraw
    views = [("forward", 0, 0), ("behind (seam)", 180, 0), ("straight up", 0, 89.9), ("straight down", 0, -89.9)]
    rows = [("after", eq)] + ([("before", before)] if before is not None else [])
    s = 400
    sheet = Image.new("RGB", (s * 4, (s + 24) * len(rows)), (20, 20, 20))
    dr = ImageDraw.Draw(sheet)
    for r, (name, src) in enumerate(rows):
        for i, (lab, yw, pt) in enumerate(views):
            im = np.clip(view(src, yw, pt, size=s), 0, 255).astype(np.uint8)
            sheet.paste(Image.fromarray(im), (i * s, r * (s + 24) + 24))
            dr.text((i * s + 6, r * (s + 24) + 6), f"{name}: {lab}", fill=(255, 255, 255))
    sheet.save(path, quality=88)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("dst")
    ap.add_argument("--width", type=int, default=4096)
    ap.add_argument("--seam", type=float, default=0.07)
    ap.add_argument("--pole", type=float, default=0.14)
    ap.add_argument("--preview")
    a = ap.parse_args()
    src = np.asarray(Image.open(a.src).convert("RGB")).astype(np.float32)
    out = fix_seam(src, a.seam)
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).resize((a.width, a.width // 2), Image.LANCZOS)
    out = fix_poles(np.asarray(img).astype(np.float32), a.pole)
    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(a.dst, quality=92)
    if a.preview:
        before = np.asarray(Image.open(a.src).convert("RGB").resize((a.width, a.width // 2), Image.LANCZOS)).astype(np.float32)
        preview(out, a.preview, before)
    print("wrote", a.dst, a.width, "x", a.width // 2)


if __name__ == "__main__":
    main()
