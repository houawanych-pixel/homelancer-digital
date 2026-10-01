"""Shared capital material maps (one set for the whole city kit, tiled in world space by assets/city/capital.gdshader).

capital_normal.png : tangent-space normal map, 512 px = one 8 m x 8 m tile (64 px per metre). Gives the LOOK of
                     panel seams, grooves, bolts, vents and small recesses without any extra polygons.
capital_mask.png   : R = grime / ambient occlusion (1 clean .. 0 dirty), G = seam lines (1 = seam),
                     B = window cells (lights in the glass material).
Everything wraps, so the tile repeats without seams. Deterministic (fixed seed).
Run:  python3 tools/city/make_capital_maps.py
"""
import numpy as np
from PIL import Image, ImageFilter
import os

N = 512
rng = np.random.default_rng(20261001)
out = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "city")

h = np.zeros((N, N), np.float32)      # height field, 0 = panel surface
seam = np.zeros((N, N), np.float32)

def rect(a, x0, y0, x1, y1, v, mode="set"):
    xs = np.arange(x0, x1) % N
    ys = np.arange(y0, y1) % N
    if mode == "set": a[np.ix_(ys, xs)] = v
    elif mode == "max": a[np.ix_(ys, xs)] = np.maximum(a[np.ix_(ys, xs)], v)
    elif mode == "add": a[np.ix_(ys, xs)] += v

# 1) big panels: split the tile into a grid of 4 columns x 4 rows (2 m), randomly merged into bigger plates
cols, rows = 4, 4
cw = N // cols
merged = []
used = np.zeros((rows, cols), bool)
for r in range(rows):
    for c in range(cols):
        if used[r, c]: continue
        w = 1 + int(rng.random() < 0.45 and c + 1 < cols and not used[r, c + 1])
        hh = 1 + int(rng.random() < 0.35 and r + 1 < rows)
        if hh == 2 and (used[r + 1, c] or (w == 2 and used[r + 1, c + 1])): hh = 1
        used[r:r + hh, c:c + w] = True
        merged.append((c * cw, r * cw, (c + w) * cw, (r + hh) * cw))

for (x0, y0, x1, y1) in merged:
    # seam groove 3 px around every plate (wraps)
    g = 3
    for (a, b, cc, d) in [(x0, y0, x1, y0 + g), (x0, y1 - g, x1, y1), (x0, y0, x0 + g, y1), (x1 - g, y0, x1, y1)]:
        rect(h, a, b, cc, d, -1.0)
        rect(seam, a, b, cc, d, 1.0)
    # slight plate tilt / raise so neighbouring plates catch light differently
    rect(h, x0 + g, y0 + g, x1 - g, y1 - g, rng.uniform(-0.15, 0.15), "add")
    # bolts in the corners
    for (bx, by) in [(x0 + 9, y0 + 9), (x1 - 10, y0 + 9), (x0 + 9, y1 - 10), (x1 - 10, y1 - 10)]:
        yy, xx = np.ogrid[-3:4, -3:4]
        disk = (xx * xx + yy * yy) <= 9
        ys = (np.arange(by - 3, by + 4) % N)[:, None]
        xs = (np.arange(bx - 3, bx + 4) % N)[None, :]
        h[ys, xs] = np.where(disk, h[ys, xs] + 0.7, h[ys, xs])
    kind = rng.random()
    pw, ph = x1 - x0, y1 - y0
    if kind < 0.3:      # vent: row of horizontal slots
        n = rng.integers(4, 8)
        vx0 = x0 + pw // 5
        vx1 = x1 - pw // 5
        for k in range(n):
            y = y0 + ph // 4 + k * 7
            rect(h, vx0, y, vx1, y + 3, -0.9)
    elif kind < 0.55:   # recessed access hatch
        rect(h, x0 + pw // 4, y0 + ph // 4, x1 - pw // 4, y1 - ph // 4, -0.5, "add")
        rect(seam, x0 + pw // 4, y0 + ph // 4, x1 - pw // 4, y0 + ph // 4 + 2, 0.6)
    elif kind < 0.7:    # raised armour strip
        rect(h, x0 + 12, y0 + ph // 2 - 6, x1 - 12, y0 + ph // 2 + 6, 0.6, "add")

# fine horizontal panel lines inside big plates (the "texture" of armour)
for k in range(0, N, 32):
    if rng.random() < 0.4: rect(h, 0, k, N, k + 1, -0.3, "add")

# 2) normal map from the (wrapping) height field
hb = np.array(Image.fromarray(((h - h.min()) / (h.max() - h.min()) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255.0
strength = 5.0
dx = (np.roll(hb, -1, 1) - np.roll(hb, 1, 1)) * strength
dy = (np.roll(hb, -1, 0) - np.roll(hb, 1, 0)) * strength
nz = np.ones_like(dx)
l = np.sqrt(dx * dx + dy * dy + nz * nz)
nrm = np.stack([-dx / l, dy / l, nz / l], -1)        # OpenGL convention (+Y up), as Godot expects
Image.fromarray(((nrm * 0.5 + 0.5) * 255).astype(np.uint8)).save(os.path.join(out, "capital_normal.png"))

# 3) mask: grime (low frequency noise + darker in seams), seams, window cells
def wrap_noise(scale, octaves=4):
    acc = np.zeros((N, N), np.float32)
    amp = 1.0
    for o in range(octaves):
        s = scale * (2 ** o)
        g = rng.random((s, s)).astype(np.float32)
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
        # make it wrap: tile 3x3 then crop the centre after resizing
        big = np.tile(g, (3, 3))
        img = Image.fromarray((big * 255).astype(np.uint8)).resize((N * 3, N * 3), Image.BICUBIC)
        acc += amp * (np.array(img, np.float32)[N:2 * N, N:2 * N] / 255.0)
        amp *= 0.5
    return acc / acc.max()
grime = 0.75 + 0.25 * wrap_noise(4)
seam_blur = np.array(Image.fromarray((seam * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)), np.float32) / 255.0
grime = np.clip(grime - seam_blur * 0.35, 0, 1)
win = np.zeros((N, N), np.float32)
for r in range(8):
    for c in range(8):
        if rng.random() < 0.55:
            rect(win, c * 64 + 6, r * 64 + 10, c * 64 + 58, r * 64 + 50, rng.uniform(0.5, 1.0))
mask = np.stack([grime, np.clip(seam, 0, 1), win], -1)
Image.fromarray((mask * 255).astype(np.uint8)).save(os.path.join(out, "capital_mask.png"))
print("wrote capital_normal.png, capital_mask.png")
