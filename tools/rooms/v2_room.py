"""Rooms V2: stitch a filled join image into the 360 strip, then cut it into 6 overlapping 16:9 pieces (1920x1080)
for the video generator. Piece i covers strip x = round(i*W/6) .. +round(H*16/9), wrapping at the end.
usage: python3 tools/rooms/v2_room.py <faction> <room>"""
import os, subprocess, sys
from PIL import Image
import numpy as np
f, room = sys.argv[1], sys.argv[2]
base = f"art/rooms_v2/{f}"
tmp = f"/tmp/v2_{f}_{room}_360.png"
env = dict(os.environ, STITCH_SEAM="1")
r = subprocess.run([sys.executable, "tools/rooms/stitch_filled.py", f"{base}/{room}.png", f"{base}/joins/v2_{f}_{room}_joins_filled.png", tmp], env=env, capture_output=True, text=True)
print(r.stdout.strip().split("\n")[-1], r.stderr.strip()[-300:])
im = Image.open(tmp).convert("RGB")
a = np.asarray(im)
W, H = im.size
white = [y for y in range(H) if (a[y].min(1) > 235).mean() > 0.2]   # the white divider leftovers at top/bottom
top = max([y + 1 for y in white if y < H // 4], default=0)
bot = min([y for y in white if y > H * 3 // 4], default=H)
im = im.crop((0, top, W, bot)); W, H = im.size
os.makedirs(f"{base}/pano", exist_ok=True); os.makedirs(f"{base}/pieces", exist_ok=True)
im.save(f"{base}/pano/{room}_360.png")
pw = round(H * 16 / 9)
for i in range(6):
    x0 = round(i * W / 6)
    if x0 + pw <= W: t = im.crop((x0, 0, x0 + pw, H))
    else:
        t = Image.new("RGB", (pw, H)); t.paste(im.crop((x0, 0, W, H)), (0, 0)); t.paste(im.crop((0, 0, x0 + pw - W, H)), (W - x0, 0))
    t.resize((1920, 1080), Image.LANCZOS).save(f"{base}/pieces/v2_{f}_{room}_piece{i + 1}.png")
print(room, W, H, "piece w", pw)
