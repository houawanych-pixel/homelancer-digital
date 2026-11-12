#!/usr/bin/env python3
"""v13.86 (owner, Nov 12 2026: "this is what I've been doing the whole time"): THE way to animate a 360 room in 3 clips.
The room picture is the owner's 16:9 sheet: FRONT view on top, BACK view below (each about 16 x 4.5), plus the painted
joins (art/rooms/.../joins/<name>_joins_filled.jpg). Three clips, no cutting, no stacking, no padding:

  1_front.png  the front view as is (1672 x ~464)
  2_back.png   the back view as is
  3_joins.png  the two painted patches only (the gap columns E..W-E of each joins row), side by side, 6 px white line

The patch edges are the painted gap's edges (plants, floor, walls), so nobody stands on a seam; the front/back clips
meet them at the views' own ends.

    python3 tools/rooms/loc_three.py <sheet.png> <joins_filled.jpg> <out_dir> <Name>"""
import os, sys
from PIL import Image
E = 560   # make_joins.py keeps 560 px of each view either side of the gap
sheet, joins, out, name = sys.argv[1:5]
im = Image.open(sheet).convert("RGB"); W, H = im.size; m = H // 2
top = im.crop((0, 0, W, m - 6)); bot = im.crop((0, m + 6, W, H)); h = min(top.height, bot.height)
top = top.crop((0, 0, W, h)); bot = bot.crop((0, 0, W, h))
j = Image.open(joins).convert("RGB").resize((W, H))
r1 = j.crop((E, 0, W - E, h)); r2 = j.crop((E, H - h, W - E, H))
jj = Image.new("RGB", (r1.width * 2 + 6, h), "white"); jj.paste(r1, (0, 0)); jj.paste(r2, (r1.width + 6, 0))
os.makedirs(out, exist_ok=True)
for img, tag in ((top, "1_front"), (bot, "2_back"), (jj, "3_joins")):
    img.save(os.path.join(out, "%s_%s.png" % (name, tag))); print(tag, img.size)
