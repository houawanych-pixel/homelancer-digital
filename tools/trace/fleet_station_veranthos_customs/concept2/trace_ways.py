#!/usr/bin/env python3
"""Zoom-in trace of the owner's "Veranthos Customs - inner map, mech & pilot ways (concept)" (Nov 18 2026), drawn on
the Liberty Hub silhouette. At 4x: the station floor (inside the glowing hull line), the RED mech ways (the red arms and
lanes plus the lit main corridors) and the BLUE pilot rooms are read by colour, mirrored about the middle (the left half
is kept, the hub sits on x 553), and every outline is straightened (0 / 45 / 90 deg walls snapped, curves kept).
Output: trace_on_map.jpg (red / blue fills + white outlines on the dimmed map), trace_plan.png (the same on black),
trace.json (polygons in source px: floor, mech, pilot)."""
import json, math, os
import cv2, numpy as np
from shapely.geometry import Polygon, mapping
from shapely.ops import unary_union

HERE = os.path.dirname(os.path.abspath(__file__))
Z, AXS = 4, 553
src = cv2.imread(os.path.join(HERE, "source.png")); H0, W0 = src.shape[:2]
src[:95, :] = src[2:3, 2:3]; src[835:, :240] = src[2:3, 2:3]; src[960:, 850:] = src[2:3, 2:3]   # title, legend, scale bar
big = cv2.resize(src, None, fx=Z, fy=Z, interpolation=cv2.INTER_CUBIC)
a = cv2.GaussianBlur(big, (9, 9), 0).astype(int); b, g, r = a[..., 0], a[..., 1], a[..., 2]
red = ((r > b + 25) & (r > g + 15) & (r > 70)).astype(np.uint8)
walk = ((r > 150) & (g > 120) & (b > 100)).astype(np.uint8)
blue = ((b > r + 45) & (b > 70)).astype(np.uint8)
lit = (red | walk | blue)
# the floor: everything the hull line closes in (flood the outside, the glow and frame are the barrier)
bar = cv2.morphologyEx(lit, cv2.MORPH_CLOSE, np.ones((9 * Z, 9 * Z), np.uint8))
# cut the picture frame away first (it is a big rectangle of glow round everything)
bar[:, :20 * Z] = 0; bar[:, -20 * Z:] = 0; bar[:110 * Z, :] = 0; bar[-30 * Z:, :] = 0
ff = bar.copy(); mk = np.zeros((ff.shape[0] + 2, ff.shape[1] + 2), np.uint8); cv2.floodFill(ff, mk, (5, 5), 2)
floor = (ff != 2).astype(np.uint8)
n, lab, st, _ = cv2.connectedComponentsWithStats(floor); floor = (lab == 1 + np.argmax(st[1:, 4])).astype(np.uint8)
floor = cv2.erode(floor, np.ones((4 * Z, 4 * Z), np.uint8))           # off the hull glow
def smooth(m, s):   # rounds off pixel steps: blur and re-threshold
    return (cv2.GaussianBlur(m.astype(np.float32), (0, 0), s) > 0.5).astype(np.uint8)
# mirror-true: the left half kept and mirrored
def mirror(m):
    ax = AXS * Z; out = m.copy(); w = m.shape[1]
    for x in range(ax + 1, min(w, 2 * ax + 1)): out[:, x] = m[:, 2 * ax - x]
    return out
floor = mirror(floor)
mech = mirror(((red | walk) & floor).astype(np.uint8))
floor = smooth(floor, 2 * Z)
pilot = mirror((blue & floor & ~mech.astype(bool)).astype(np.uint8))
k = lambda s: cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (s, s))
mech = smooth(cv2.morphologyEx(cv2.morphologyEx(mech, cv2.MORPH_CLOSE, k(6 * Z)), cv2.MORPH_OPEN, k(4 * Z)), 2.5 * Z)
# only the mech network itself: label text inside rooms reads as lit corridor, so loose red bits are dropped
n_, l_, s_, _ = cv2.connectedComponentsWithStats(mech); mech = (l_ == 1 + np.argmax(s_[1:, 4])).astype(np.uint8)
pilot = smooth(cv2.morphologyEx(cv2.morphologyEx(pilot, cv2.MORPH_CLOSE, k(8 * Z)), cv2.MORPH_OPEN, k(5 * Z)), 2.5 * Z) & ~mech
# blue glow along the hull is the hull light, not a room: drop blue bits in the outer 12 px band
band = floor & ~cv2.erode(floor, k(24 * Z))
n_, l_, s_, _ = cv2.connectedComponentsWithStats(pilot)
for i_ in range(1, n_):
    m_ = l_ == i_
    if (band[m_] > 0).mean() > 0.25 or s_[i_, 4] < 150 * Z * Z: pilot[m_] = 0
pilot = mirror(pilot)

def snap(c):
    p = cv2.approxPolyDP(c, 2.5 * Z, True).reshape(-1, 2).astype(float); m = len(p)
    if m < 3: return p
    d = np.roll(p, -1, 0) - p; ang = np.degrees(np.arctan2(d[:, 1], d[:, 0]))
    turn = (np.roll(ang, -1) - ang + 180) % 360 - 180
    curve = (np.abs(turn) < 25) & (np.abs(np.roll(turn, 1)) < 25) & (np.sign(turn) == np.sign(np.roll(turn, 1))) & (np.abs(turn) > 2)
    sn = np.round(ang / 45.0) * 45.0
    straight = (~curve) & (np.abs((ang - sn + 180) % 360 - 180) < 14)
    mid = p + d / 2; u = np.stack([np.cos(np.radians(sn)), np.sin(np.radians(sn))], 1)
    out = []
    for i in range(m):
        e0, e1 = (i - 1) % m, i
        if straight[e0] and straight[e1]:
            A = np.array([u[e0], -u[e1]]).T
            if abs(np.linalg.det(A)) > 1e-6:
                t = np.linalg.solve(A, mid[e1] - mid[e0]); q = mid[e0] + t[0] * u[e0]
                if np.hypot(*(q - p[i])) < 5 * Z: out.append(q); continue
        if straight[e0]: out.append(mid[e0] + np.dot(p[i] - mid[e0], u[e0]) * u[e0]); continue
        if straight[e1]: out.append(mid[e1] + np.dot(p[i] - mid[e1], u[e1]) * u[e1]); continue
        out.append(p[i])
    return np.array(out)
def polys(m, min_area):
    cs, hi = cv2.findContours(m, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE); out = []
    for i, c in enumerate(cs):
        if hi[0][i][3] >= 0 or cv2.contourArea(c) < min_area: continue
        holes = [snap(cs[j]) for j in range(len(cs)) if hi[0][j][3] == i and cv2.contourArea(cs[j]) > min_area / 4]
        pg = Polygon(snap(c), [h for h in holes if len(h) >= 3]).buffer(0)
        if not pg.is_empty: out += [q for q in getattr(pg, "geoms", [pg]) if q.area > min_area / 2]
    return out
FL = polys(floor, 2000 * Z * Z); ME = polys(mech, 120 * Z * Z); PI = polys(pilot, 90 * Z * Z)
RED, BLUE = (60, 50, 215), (235, 130, 40)
def draw(base):
    img = base.copy(); fillr = img.copy()
    for pg, col in [(q, RED) for q in ME] + [(q, BLUE) for q in PI]:
        m1 = np.zeros(img.shape[:2], np.uint8); cv2.fillPoly(m1, [np.array(pg.exterior.coords, np.int32)], 1)
        for h in pg.interiors: cv2.fillPoly(m1, [np.array(h.coords, np.int32)], 0)
        fillr[m1 > 0] = col
    img = cv2.addWeighted(fillr, 0.55, img, 0.45, 0)
    for pg in FL + ME + PI:
        for ring in [pg.exterior] + list(pg.interiors):
            cv2.polylines(img, [np.array(ring.coords, np.int32)], True, (255, 255, 255), max(2, Z // 2), cv2.LINE_AA)
    return cv2.resize(img, None, fx=0.5, fy=0.5, interpolation=cv2.INTER_AREA)
dark = np.full_like(big, (40, 22, 8))
m0 = np.zeros(big.shape[:2], np.uint8)
for pg in FL: cv2.fillPoly(m0, [np.array(pg.exterior.coords, np.int32)], 1)
dark[m0 > 0] = (70, 45, 25)
cv2.imwrite(os.path.join(HERE, "trace_on_map.jpg"), draw((big * 0.5).astype(np.uint8)), [cv2.IMWRITE_JPEG_QUALITY, 88])
cv2.imwrite(os.path.join(HERE, "trace_plan.png"), draw(dark))
sc = 1.0 / Z
from shapely import affinity
J = {k_: [mapping(affinity.scale(q, sc, sc, origin=(0, 0))) for q in v] for k_, v in (("floor", FL), ("mech", ME), ("pilot", PI))}
J.update({"units": "source px (concept2/source.png)", "axis_x": AXS})
json.dump(J, open(os.path.join(HERE, "trace.json"), "w"))
print("floor", len(FL), "mech pieces", len(ME), "pilot rooms", len(PI))
