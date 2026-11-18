#!/usr/bin/env python3
"""Alien: Isolation 'Station Maintenance' map (owner's screenshot, 17 Nov 2026): many separate floor pieces on a grid.
The map draws each floor as a thin cyan / green outline (dashed = under the floor). wall_trace.py expects one outline, so this
script reads the outline colour, closes the dashes, fills each closed piece, drops leader lines / text / icons, and straightens
every outline (approxPolyDP, then edges within 6 deg of 0/45/90 are snapped). Output: walls_trace.png (white on black),
walls_overlay.jpg (white on the dimmed map), pieces.json (crop px)."""
import json, math, os, sys
import cv2, numpy as np

CL = int(sys.argv[1]) if len(sys.argv) > 1 else 17
HERE = os.path.dirname(os.path.abspath(__file__))
Y0, Y1, X0, X1 = 142, 1660, 100, 1815          # inside the map frame
src = cv2.imread(os.path.join(HERE, "source.png"))[Y0:Y1, X0:X1]
a = src.astype(int); b, g, r = a[..., 0], a[..., 1], a[..., 2]
line = ((g > 60) & (g > r + 15) & (a.max(2) < 200)).astype(np.uint8) * 255
icons = (a.max(2) > 95).astype(np.uint8) * 255            # icons sitting on an outline (lifts, doors) are part of the barrier
icons = cv2.morphologyEx(icons, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
line = cv2.bitwise_or(line, icons)
# text labels ("UPPER DECK", terminal name, logo) are line-coloured too: blank their boxes
for (x0, y0, x1, y1) in [(770, 395, 945, 432), (550, 1045, 730, 1080), (705, 762, 980, 786), (1295, 1540, 1715, 1518 + 60)]:
    line[y0:y1, x0:x1] = 0
closed = cv2.morphologyEx(line, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_RECT, (CL, CL)))
# the Maintenance Office is drawn dashed and faint: close its box with a bigger kernel
x0, y0, x1, y1 = 1250, 305, 1345, 400
closed[y0:y1, x0:x1] |= cv2.morphologyEx(line[y0:y1, x0:x1], cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_RECT, (31, 31)))
# fill: everything not reachable from the border without crossing a line is floor
ff = closed.copy(); h, w = ff.shape; m = np.zeros((h + 2, w + 2), np.uint8)
cv2.floodFill(ff, m, (0, 0), 128)
floor = ((ff != 128)).astype(np.uint8) * 255
floor = cv2.morphologyEx(floor, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))   # drops leader lines
n, lab, st, _ = cv2.connectedComponentsWithStats(floor)
keep = np.zeros_like(floor)
for i in range(1, n):
    if st[i, cv2.CC_STAT_AREA] > 900: keep[lab == i] = 255
EPS = 2.5
def snap(poly):
    """snap edges that are nearly 0/45/90 deg so walls come out dead straight"""
    p = poly.reshape(-1, 2).astype(float); k = len(p)
    for _ in range(2):
        for i in range(k):
            j = (i + 1) % k; d = p[j] - p[i]; ang = math.degrees(math.atan2(d[1], d[0])) % 45
            if min(ang, 45 - ang) < 6 and np.hypot(*d) > 6:
                if abs(d[0]) > 2 * abs(d[1]): p[j, 1] = p[i, 1]           # horizontal
                elif abs(d[1]) > 2 * abs(d[0]): p[j, 0] = p[i, 0]         # vertical
    return p.astype(np.int32)
cs, hier = cv2.findContours(keep, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
plan = np.zeros_like(src); ov = (src * 0.45).astype(np.uint8); pieces = []
for i, c in enumerate(cs):
    hole = hier[0][i][3] >= 0
    if hole and cv2.contourArea(c) < 150: continue
    p = snap(cv2.approxPolyDP(c, EPS, True))
    for im in (plan, ov): cv2.polylines(im, [p], True, (255, 255, 255), 2, cv2.LINE_AA)
    pieces.append({"hole": bool(hole), "pts": p.tolist()})
cv2.imwrite(os.path.join(HERE, "walls_trace.png"), plan)
cv2.imwrite(os.path.join(HERE, "walls_overlay.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 88])
json.dump({"crop": [Y0, Y1, X0, X1], "units": "crop px", "pieces": pieces}, open(os.path.join(HERE, "pieces.json"), "w"))
print(len([q for q in pieces if not q["hole"]]), "pieces,", len([q for q in pieces if q["hole"]]), "holes")
