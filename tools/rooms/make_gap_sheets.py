#!/usr/bin/env python3
"""Unity Station 360 canvas -> two "fill the gap" sheets for an AI image tool (ChatGPT, Photoshop Generative Fill).
Each sheet: the end of one view on the left, the start of the next view on the right, WHITE gap in the middle.
Nothing is overlapped or cut away: people cut by the picture edge stay as they are, for the AI to finish.
Sheet = 1536 x 1024 (ChatGPT's landscape size), so the AI does not reframe it.
  join A: front view right edge  -> back view left edge
  join B: back view right edge   -> front view left edge   (the loop point)
usage: make_gap_sheets.py canvas.png out_prefix [--gap 200]
Also writes out_prefix_gap.json (the numbers patch_gap.py needs)."""
import sys, json, numpy as np
from PIL import Image

args = sys.argv; src, pre = args[1], args[2]
GAP = int(args[args.index("--gap") + 1]) if "--gap" in args else 200
SW, SH = 1536, 1024
c = Image.open(src).convert("RGBA"); a = np.asarray(c)[..., 3] > 0; W = c.width
cols = a.any(0); edges = np.nonzero(np.diff(cols.astype(int)))[0] + 1
l_end, f_start, f_end, r_start = map(int, edges[:4])
rows = np.nonzero(a[:, f_start:f_end].any(1))[0]; y0, y1 = int(rows[0]), int(rows[-1]) + 1
H = y1 - y0
scale = SH / H
side = round((SW / scale - GAP) / 2)          # source px kept on each side of the gap
rgb = c.convert("RGB")
def piece(x0, x1): return rgb.crop((x0, y0, x1, y1))
joins = {"A": (piece(f_end - side, f_end), piece(r_start, r_start + side)),
         "B": (piece(l_end - side, l_end), piece(f_start, f_start + side))}
info = {"canvas": src, "rows": [y0, y1], "gap": GAP, "side": side, "scale": scale,
        "front": [f_start, f_end], "back_right_half": [0, l_end], "back_left_half": [r_start, W], "sheets": {}}
for k, (L, R) in joins.items():
    sheet = Image.new("RGB", (2 * side + GAP, H), (255, 255, 255))
    sheet.paste(L, (0, 0)); sheet.paste(R, (side + GAP, 0))
    sheet = sheet.resize((SW, SH), Image.LANCZOS)
    mask = Image.new("L", (SW, SH), 0)
    gx0, gx1 = round(side * SW / (2 * side + GAP)), round((side + GAP) * SW / (2 * side + GAP))
    mask.paste(255, (gx0, 0, gx1, SH))
    sheet.save(f"{pre}_join{k}_fill_me.png"); mask.save(f"{pre}_join{k}_mask.png")
    info["sheets"][k] = {"gap_px_in_sheet": [gx0, gx1]}
    print(f"{pre}_join{k}_fill_me.png", "gap x", gx0, "-", gx1)
json.dump(info, open(pre + "_gap.json", "w"), indent=1)
