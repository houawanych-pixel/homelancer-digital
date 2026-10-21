#!/usr/bin/env python3
"""Owner's room sheet (front view on top, back view below) -> a 2:1 360 canvas for PhotoCraft to finish.
The FRONT view sits in the middle (straight ahead), the BACK view is split across the left and right edges (behind
you; the edges wrap round to meet). Nothing is painted: the gaps at the two joins, the ceiling and the floor are left
TRANSPARENT, and a separate mask (white = fill this) is saved for PhotoCraft's inpaint / outpaint.
usage: prep_photocraft.py sheet.png out_prefix [top0 top1 bot0 bot1]"""
import sys, numpy as np
from PIL import Image
a = Image.open(sys.argv[1]).convert('RGB'); W0, H0 = a.size
pre = sys.argv[2]
if len(sys.argv) >= 7: t0, t1, b0, b1 = map(int, sys.argv[3:7])
else:
    mid = H0 // 2; t0, t1, b0, b1 = 0, mid - 6, mid + 6, H0
front = a.crop((0, t0, W0, t1)); back = a.crop((0, b0, W0, b1))
GAP = 160                              # left open at each join for PhotoCraft to blend
CW = 2 * W0 + 2 * GAP; CH = CW // 2    # 2:1
canvas = Image.new('RGBA', (CW, CH), (0, 0, 0, 0))
cy = CH // 2
fx = GAP + W0 // 2                     # front centred: x from GAP+W0/2 .. ; centre of canvas = CW/2
fx = CW // 2 - W0 // 2
canvas.paste(front, (fx, cy - front.height // 2))
# the back view: its middle is straight behind you = the left/right edge of the canvas; split it in two halves
bh = back.width // 2
canvas.paste(back.crop((bh, 0, back.width, back.height)), (0, cy - back.height // 2))            # back's right half on the left edge
canvas.paste(back.crop((0, 0, bh, back.height)), (CW - bh, cy - back.height // 2))              # back's left half on the right edge
canvas.save(pre + '_canvas.png')
alpha = np.asarray(canvas)[:, :, 3]
Image.fromarray(np.where(alpha > 0, 0, 255).astype(np.uint8)).save(pre + '_mask.png')
print(pre, CW, CH, 'front', front.size, 'back', back.size)
