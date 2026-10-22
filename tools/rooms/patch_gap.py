#!/usr/bin/env python3
"""Patch AI-filled gap sheets (from make_gap_sheets.py) back in -> one looping 360 strip.
strip = front | filled gap A | back view | filled gap B   (B wraps round to the front)
Original pixels are kept for both views; only the gap comes from the AI picture.
Grok/ChatGPT leave a pale fade a few px wide at each edge of the white area, so `--trim` sheet px are dropped from
each edge of the gap and the clean middle is stretched back to the full gap width (about 6 %, not visible).
The seam is then softened over a narrow band so there is no hard line.
usage: patch_gap.py prefix_gap.json filledA.png filledB.png out.jpg [--trim 16]  (use --trim 2 when the white edge lines were already cleaned by hand) [--soft 5] [--match 40] [--joins joins.png]"""
import sys, json, numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

args = sys.argv
def opt(k, d): return type(d)(args[args.index(k) + 1]) if k in args else d
info = json.load(open(args[1])); fa, fb, dst = args[2], args[3], args[4]
T, SOFT = opt("--trim", 16), opt("--soft", 5)
y0, y1 = info["rows"]; G = info["gap"]; H = y1 - y0
rgb = Image.open(info["canvas"]).convert("RGB")
def crop(x0, x1): return np.asarray(rgb.crop((x0, y0, x1, y1))).astype(np.float32)
front = crop(*info["front"])
back = np.concatenate([crop(*info["back_left_half"]), crop(*info["back_right_half"])], 1)
def gap_of(path, key):
    gx0, gx1 = info["sheets"][key]["gap_px_in_sheet"]
    g = Image.open(path).convert("RGB").resize((1536, 1024), Image.LANCZOS)
    return np.asarray(g.crop((gx0 + T, 0, gx1 - T, 1024)).resize((G, H), Image.LANCZOS)).astype(np.float32)
MATCH = opt("--match", 40)      # source px of the gap, at each edge, whose colour is pulled to the original edge
def match_edges(gap, left, right):
    """Remove tint / haze bands at the gap edges: per row, pull the gap's broad colour at each edge to the
    original view's colour next to it, fading out over MATCH px. Detail is untouched (low frequency only)."""
    B_ = 6
    def broad(a): return gaussian_filter(a.mean(axis=1), (12, 0))
    dl = broad(left[:, -B_:]) - broad(gap[:, :B_]); dr = broad(right[:, :B_]) - broad(gap[:, -B_:])
    t = np.arange(G) / max(G - 1, 1)
    wl = np.clip(1 - np.arange(G) / MATCH, 0, 1) ** 2; wr = np.clip(1 - np.arange(G)[::-1] / MATCH, 0, 1) ** 2
    return gap + dl[:, None, :] * wl[None, :, None] + dr[:, None, :] * wr[None, :, None]
A, B = gap_of(fa, "A"), gap_of(fb, "B")
A = match_edges(A, front, back); B = match_edges(B, back, front)
strip = np.concatenate([front, A, back, B], 1)
seams = [front.shape[1], front.shape[1] + G, front.shape[1] + G + back.shape[1], 0]
for s in seams:     # soften each seam over +-SOFT*2 px
    r = np.roll(strip, 3 * SOFT - s, axis=1)[:, :6 * SOFT]
    bl = gaussian_filter(r, (0.6, SOFT * 0.6, 0))
    w = np.exp(-((np.arange(6 * SOFT) - 3 * SOFT) / SOFT) ** 2)[None, :, None]
    idx = (np.arange(6 * SOFT) + s - 3 * SOFT) % strip.shape[1]
    strip[:, idx] = r * (1 - w) + bl * w
out = np.clip(strip, 0, 255).astype(np.uint8)
Image.fromarray(out).save(dst, quality=92); print(dst, out.shape[1], "x", out.shape[0], "gaps at", seams[0], seams[2])
if "--joins" in args:
    cut = [np.roll(out, 420 - (s + G // 2), axis=1)[:, :840] for s in (seams[0], seams[2])]
    Image.fromarray(np.concatenate([cut[0], np.zeros((8, 840, 3), np.uint8), cut[1]], 0)).save(opt("--joins", ""))
