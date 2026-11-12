#!/usr/bin/env python3
"""UPP Tianjin command tower (upper deck, "Pressured Sealed CIC") as a clean engineering plan.
Measured on part_upper_deck_x4.png (EDSR x4 of the sheet inset). Mirror symmetric about y = CY except the aft tab
with the ladder down to the main deck (owner: the tower sits on the raised stern block of the exterior).
Walls = floor edge +/- T/2; interior walls as centre lines with standard doors (DOOR clear)."""
import json, os
import cv2, numpy as np
from shapely.geometry import Point, LineString, box, mapping
from shapely.ops import unary_union

HERE = os.path.dirname(os.path.abspath(__file__))
CY, T, DOOR = 440.0, 12.0, 60.0
R = 230.0                                   # the rounded bow of the CIC
cic = unary_union([box(475, 130, 1100 - R, 750), box(475, 130 + R, 1100, 750 - R),
                   Point(1100 - R, 130 + R).buffer(R, 128), Point(1100 - R, 750 - R).buffer(R, 128)])
cic = cic.intersection(box(475, 130, 1100, 750))
aft = unary_union([box(60, 235, 215, 645), box(215, 380, 330, 505), box(255, 235, 320, 380), box(255, 505, 320, 650),
                   box(330, 365, 475, 515)])
ladder = unary_union([box(80, 640, 200, 735), box(105, 735, 165, 772)])     # asym: ladder down to the main deck
floor = unary_union([cic, aft, ladder])
walls = floor.buffer(T / 2, join_style=2).difference(floor.buffer(-T / 2, join_style=2))

def wall(p0, p1, doors=()):
    """an interior wall on the centre line p0-p1 with standard doors centred at the given distances along it"""
    L = LineString([p0, p1]); n = L.length; cuts = [0.0]
    for d in doors: cuts += [d - DOOR / 2, d + DOOR / 2]
    cuts.append(n)
    from shapely.ops import substring
    return unary_union([substring(L, cuts[i], cuts[i + 1]).buffer(T / 2, cap_style=2) for i in range(0, len(cuts), 2)])
inner = [
    wall((710, 130), (710, 750), doors=[310]),                       # bridge bulkhead, door on the centre line
    wall((475, 385), (710, 385), doors=[60]), wall((475, 500), (710, 500), doors=[60]),   # side rooms off the hall
    wall((215, 380), (215, 505), doors=[62.5]),                      # aft hall to the spine
    wall((330, 365), (330, 515), doors=[75]), wall((475, 365), (475, 515), doors=[75]),   # connector doors
    wall((80, 640), (200, 640), doors=[60]),                         # ladder room
]
walls = unary_union([walls] + inner)

S = 1
src = cv2.imread(os.path.join(HERE, "..", "part_upper_deck_x4.png")); H, W = src.shape[:2]
mask = np.zeros((H, W), np.uint8)
for p in getattr(walls, "geoms", [walls]):
    m1 = np.zeros_like(mask)
    cv2.fillPoly(m1, [np.array(p.exterior.coords, np.int32)], 255)
    for r in p.interiors: cv2.fillPoly(m1, [np.array(r.coords, np.int32)], 0)
    mask |= m1
cs, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
plan = np.zeros_like(src); ov = (src * 0.5).astype(np.uint8)
for im in (plan, ov): cv2.drawContours(im, cs, -1, (255, 255, 255), 2, cv2.LINE_AA)
cv2.imwrite(os.path.join(HERE, "tower_plan.png"), plan)
cv2.imwrite(os.path.join(HERE, "tower_plan_on_map.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 90])
json.dump({"units": "x4 inset px", "mirror_y": CY, "thickness": T, "door": DOOR, "floor": mapping(floor), "walls": mapping(walls)},
          open(os.path.join(HERE, "tower_plan.json"), "w"))
print("ok")
