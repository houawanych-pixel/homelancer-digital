#!/usr/bin/env python3
"""Step A of the Liberty Hub main deck (owner, Nov 18 2026: "colour-code the walkways correctly, separate the rooms,
and map that on top of the silhouette"): read the sheet's OWN walkway network and its room blocks.

 1. walkways = the sheet's pale blue-grey corridor pixels (concept/main_deck_sheet.png), logo / legend masked
 2. skeleton (the centre line of every walkway), short spurs pruned
 3. mirror-true: the left half (x < AX) is kept and mirrored onto the right (the sheet is hand-drawn, not even)
 4. room blocks = the spaces the centre lines close in; each block's outline straightened (0 / 45 / 90 deg walls,
    runs of small same-way turns kept as curves)
Writes sheet_cells.json (centre lines as a mask file + clean block polygons, sheet px) and sheet_cells.jpg (blocks on the
sheet, walkways blue)."""
import json, math, os
import cv2, numpy as np
from skimage.morphology import skeletonize
from shapely.geometry import Polygon, mapping

HERE = os.path.dirname(os.path.abspath(__file__))
SHEET = os.path.join(HERE, "..", "concept", "main_deck_sheet.png")
AX, CY = 512, 445
im = cv2.imread(SHEET); H, W = im.shape[:2]
a = cv2.GaussianBlur(im, (5, 5), 0).astype(int); b, g, r = a[..., 0], a[..., 1], a[..., 2]
w = ((b > 135) & (b > r + 25) & (g > 105) & (b - g < 70)).astype(np.uint8)
w[:110, :160] = 0; w[840:, :320] = 0
w = cv2.morphologyEx(w, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
w = cv2.morphologyEx(w, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
n, lab, st, _ = cv2.connectedComponentsWithStats(w)
big = 1 + np.argmax(st[1:, 4]); keep = lab == big
near = cv2.dilate(keep.astype(np.uint8), np.ones((25, 25), np.uint8)) > 0
for i in range(1, n):
    if i != big and st[i, 4] > 120 and near[lab == i].any(): keep |= lab == i
sk = skeletonize(keep).astype(np.uint8)
for _ in range(14):
    nb = cv2.filter2D(sk, -1, np.ones((3, 3)), borderType=0); sk[(sk > 0) & (nb <= 2)] = 0
# bridge gaps: join each end of a centre line to the nearest other line end within 45 px (the ring and halls are
# drawn broken by shop fronts, lights and labels)
def bridge(m, reach=45):
    m = m.copy()
    nb = cv2.filter2D(m, -1, np.ones((3, 3)), borderType=0); ends = np.argwhere((m > 0) & (nb == 2))
    nl, ll = cv2.connectedComponents(m)
    used = set(); pairs = []
    for i_, (y, x) in enumerate(ends):
        for j_, (y2, x2) in enumerate(ends):
            if j_ <= i_: continue
            d = math.hypot(y - y2, x - x2)
            if d < reach and (ll[y, x] != ll[y2, x2] or d > 12): pairs.append((d, i_, j_))
    for d, i_, j_ in sorted(pairs):
        if i_ in used or j_ in used: continue
        used |= {i_, j_}; cv2.line(m, tuple(int(v) for v in ends[i_][::-1]), tuple(int(v) for v in ends[j_][::-1]), 1, 1)
    return m
sk = bridge(sk)
# mirror-true: the left half, mirrored about AX
full = np.zeros_like(sk); full[:, :AX + 1] = sk[:, :AX + 1]
for x in range(AX + 1, min(W, 2 * AX + 1)): full[:, x] = sk[:, 2 * AX - x]
full[CY - 1:CY + 2, :] |= sk[CY - 1:CY + 2, :]          # (the cross, as drawn)
# the rings and the cross, measured on the sheet (radius bins where the walkway colour runs most of the way round:
# 74 atrium walkway, 118 shop-ring walkway, 160 inner ring; the cross on the axis and the middle row)
for rr in (74, 118, 160): cv2.circle(full, (AX, CY), rr, 1, 1)
cv2.line(full, (AX, CY - 380), (AX, CY + 420), 1, 1); cv2.line(full, (AX - 420, CY), (AX + 420, CY), 1, 1)
lines = cv2.dilate(full, np.ones((7, 7), np.uint8))     # close small gaps in the centre lines
cv2.imwrite(os.path.join(HERE, "sheet_walk_centre.png"), lines * 255)

def snap(c):
    p = cv2.approxPolyDP(c, 3.0, True).reshape(-1, 2).astype(float); m = len(p)
    if m < 3: return p
    d = np.roll(p, -1, 0) - p; ang = np.degrees(np.arctan2(d[:, 1], d[:, 0]))
    turn = (np.roll(ang, -1) - ang + 180) % 360 - 180
    curve = (np.abs(turn) < 25) & (np.abs(np.roll(turn, 1)) < 25) & (np.sign(turn) == np.sign(np.roll(turn, 1))) & (np.abs(turn) > 2)
    sn = np.round(ang / 45.0) * 45.0
    straight = (~curve) & (np.abs((ang - sn + 180) % 360 - 180) < 15)
    mid = p + d / 2; u = np.stack([np.cos(np.radians(sn)), np.sin(np.radians(sn))], 1)
    out = []
    for k in range(m):
        e0, e1 = (k - 1) % m, k
        if straight[e0] and straight[e1]:
            A = np.array([u[e0], -u[e1]]).T
            if abs(np.linalg.det(A)) > 1e-6:
                t = np.linalg.solve(A, mid[e1] - mid[e0]); q = mid[e0] + t[0] * u[e0]
                if np.hypot(*(q - p[k])) < 12: out.append(q); continue
        if straight[e0]: out.append(mid[e0] + np.dot(p[k] - mid[e0], u[e0]) * u[e0]); continue
        if straight[e1]: out.append(mid[e1] + np.dot(p[k] - mid[e1], u[e1]) * u[e1]); continue
        out.append(p[k])
    return np.array(out)

free = (lines == 0).astype(np.uint8)
n, lab, st, _ = cv2.connectedComponentsWithStats(free, connectivity=4)
cells = []
for i in range(1, n):
    x, y, ww, hh, ar = st[i]
    if ar < 250 or x == 0 or y == 0 or x + ww >= W or y + hh >= H: continue   # the outside and specks
    cs, _ = cv2.findContours((lab == i).astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    pg = Polygon(snap(max(cs, key=cv2.contourArea))).buffer(0)
    if pg.is_empty: continue
    if pg.geom_type != "Polygon": pg = max(pg.geoms, key=lambda q: q.area)
    cells.append(pg)
ov = (im * 0.55).astype(np.uint8)
ov[lines > 0] = (255, 150, 30)
for pg in cells:
    cv2.polylines(ov, [np.array(pg.exterior.coords, np.int32)], True, (255, 255, 255), 2, cv2.LINE_AA)
cv2.imwrite(os.path.join(HERE, "sheet_cells.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 90])
json.dump({"axis": AX, "centre": [AX, CY], "units": "sheet px", "cells": [mapping(c) for c in cells]}, open(os.path.join(HERE, "sheet_cells.json"), "w"))
print(len(cells), "room blocks")
