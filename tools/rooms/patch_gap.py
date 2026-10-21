#!/usr/bin/env python3
"""Patch AI-filled gap sheets (from make_gap_sheets.py) back in -> one looping 360 strip.
strip = front | filled gap A | back view | filled gap B   (B wraps round to the front)
The original pixels are kept; only the gap comes from the AI picture, eased in over FEATHER px each side so the
AI's slight colour drift doesn't show as a line.
usage: patch_gap.py prefix_gap.json filledA.png filledB.png out.jpg [--feather 24]"""
import sys, json, numpy as np
from PIL import Image

args = sys.argv
info = json.load(open(args[1])); fa, fb, dst = args[2], args[3], args[4]
F = int(args[args.index("--feather") + 1]) if "--feather" in args else 24
y0, y1 = info["rows"]; G, S = info["gap"], info["side"]; H = y1 - y0
rgb = Image.open(info["canvas"]).convert("RGB")
def crop(x0, x1): return np.asarray(rgb.crop((x0, y0, x1, y1))).astype(np.float32)
front = crop(*info["front"])
back = np.concatenate([crop(*info["back_left_half"]), crop(*info["back_right_half"])], 1)
def fill(path, left, right):
    g = np.asarray(Image.open(path).convert("RGB").resize((2 * S + G, H), Image.LANCZOS)).astype(np.float32)
    gap = g[:, S - F:S + G + F].copy()
    ramp = (np.arange(F) / F)[None, :, None]
    gap[:, :F] = left[:, -F:] * (1 - ramp) + gap[:, :F] * ramp          # ease out of the left view
    gap[:, -F:] = gap[:, -F:] * (1 - ramp) + right[:, :F] * ramp        # ease into the right view
    return gap
A = fill(fa, front, back); B = fill(fb, back, front)
strip = np.concatenate([front[:, :-F], A, back[:, F:-F], B[:, :-F]], 1)
strip = np.concatenate([strip[:, F:] if False else strip], 1)
# B's last F columns blend into the front's first F columns: put that blend at the very start of the strip
strip[:, :F] = B[:, -F:]
out = Image.fromarray(np.clip(strip, 0, 255).astype(np.uint8))
out.save(dst, quality=92); print(dst, out.size)
