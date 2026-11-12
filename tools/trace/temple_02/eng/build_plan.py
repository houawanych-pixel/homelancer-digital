#!/usr/bin/env python3
"""Temple Marché level as a clean engineering plan (owner-approved method, 11 Nov 2026).
Walls are centre lines on the map's own measured wall lines, one thickness, doors as openings. The level is mirror
symmetric top/bottom about y = CY (owner: "mirror that map"), so the top band is drawn once and mirrored.
Hallways = centre line + fixed width (walls always parallel through bends). Output: plan.png, plan_on_map.jpg,
plan_walls.json (wall polygons, crop px). usage: python3 -I build_plan.py"""
import json, os
import cv2, numpy as np
from shapely.geometry import Point, LineString, Polygon, box, mapping
from shapely.ops import unary_union
from shapely import affinity

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "source_crop.png")
CX, CY = 557.0, 868.0          # hall centre; the level mirrors about y = CY and the stair halls about x = CX
T = 8.0                         # wall thickness

# ---- top band: wall centre lines measured from the map (Hough), doors = (start, end) along the wall
top = json.load(open(os.path.join(HERE, "top_band_walls.json")))
pieces = []
for k, (p1, p2, doors) in top["walls"].items():
    th = top.get("thick_walls", {}).get(k, T)
    (x1, y1), (x2, y2) = p1, p2
    if k in ("cor_l", "cor_r", "cor_il", "cor_ir"): y2 = 548.0       # the stair hallway takes over from here
    horiz = y1 == y2
    a0, a1 = (x1, x2) if horiz else (y1, y2)
    cuts = [a0] + [v for d in doors for v in d] + [a1]
    for i in range(0, len(cuts), 2):
        a, b = cuts[i], cuts[i + 1]
        ea = a - (T / 2 if i == 0 else 0); eb = b + (T / 2 if i == len(cuts) - 2 else 0)
        pieces.append(box(ea, y1 - th / 2, eb, y1 + th / 2) if horiz else box(x1 - th / 2, ea, x1 + th / 2, eb))
top_walls = unary_union(pieces)

# ---- middle: round hall (circle fit, flat west side), four stair hallways, room 1
R, X_FLAT, W, ANG = 250.0, 326.0, 68.0, 55.0
m0 = np.array([358.0, 569.5]); d = np.array([np.cos(np.radians(ANG)), np.sin(np.radians(ANG))])
bend = m0 + d * ((356.0 - m0[0]) / d[0])
end = bend + d * 200.0                      # runs on into the hall: the hallway opens into it (a door, no wall)
q = LineString([(356.0, 530.0), tuple(bend), tuple(end)])
halls = [affinity.scale(q, xfact=sx, yfact=sy, origin=(CX, CY)) for sx in (1, -1) for sy in (1, -1)]
hall = Point(CX, CY).buffer(R, 256).intersection(box(X_FLAT, 0, 3000, 3000))
corr = [h.buffer(W / 2, cap_style=2, join_style=2, mitre_limit=5).difference(box(0, 0, 3000, 540)).difference(box(0, 2 * CY - 540, 3000, 4000)) for h in halls]
room1 = Polygon([(886, 671), (962, 671), (1008, 767), (1008, 969), (962, 1065), (886, 1065), (838, 969), (838, 767)])
floor = unary_union([hall] + corr + [room1, box(CX + R - 20, 835, 848, 901), box(1000, 842, 1046, 894)])
mid_walls = floor.buffer(T / 2, join_style=2).difference(floor.buffer(-T / 2, join_style=2))   # centred on the floor edge
for o in [box(1040, 842, 1080, 894)] + [box(xc - W / 2 + T / 2, 0, xc + W / 2 - T / 2, 548) for xc in (356, 2 * CX - 356)] \
        + [box(xc - W / 2 + T / 2, 2 * CY - 548, xc + W / 2 - T / 2, 4000) for xc in (356, 2 * CX - 356)]:
    mid_walls = mid_walls.difference(o)

walls = unary_union([top_walls, affinity.scale(top_walls, yfact=-1, origin=(0, CY)), mid_walls])

# ---- draw
c = cv2.imread(SRC); S = 2
H, Wd = c.shape[:2]
mask = np.zeros((H * S, Wd * S), np.uint8)
for p in getattr(walls, "geoms", [walls]):
    cv2.fillPoly(mask, [np.array([(x * S, y * S) for x, y in p.exterior.coords], np.int32)], 255)
    for r in p.interiors: cv2.fillPoly(mask, [np.array([(x * S, y * S) for x, y in r.coords], np.int32)], 0)
cs, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
plan = np.zeros((H * S, Wd * S, 3), np.uint8); ov = cv2.resize((c * 0.55).astype(np.uint8), None, fx=S, fy=S)
for im in (plan, ov): cv2.drawContours(im, cs, -1, (255, 255, 255), 2, cv2.LINE_AA)
cv2.imwrite(os.path.join(HERE, "plan.png"), plan)
cv2.imwrite(os.path.join(HERE, "plan_on_map.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 90])
json.dump({"units": "crop px", "thickness": T, "mirror_y": CY, "walls": mapping(walls)}, open(os.path.join(HERE, "plan_walls.json"), "w"))
print("wall pieces:", len(getattr(walls, "geoms", [walls])))
