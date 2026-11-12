#!/usr/bin/env python3
"""Hex hub (hub_hex_01) as a clean engineering plan (method of temple_02/eng/build_plan.py, 11 Nov 2026).
Measured from the map (crop px, centre CX,CY): three concentric pointy-top hexagons (ring outer R_O, ring inner R_I,
centre R_C), six spokes of width SPOKE_W on the flat directions, six open courts between them, wings / rooms /
passages measured from the map's wall lines. Walls = floor edge +/- T/2; passages are one door wide (DOOR clear).
usage: python3 -I build_plan.py"""
import json, os
import cv2, numpy as np
from shapely.geometry import Polygon, LineString, box, mapping
from shapely.ops import unary_union
from shapely import affinity

HERE = os.path.dirname(os.path.abspath(__file__))
CX, CY = 591.0, 545.0
R_O, R_I, R_C = 328.0, 260.0, 150.0      # vertical scans at x=591: 217/873, 285/804, 395/694
SPOKE_W = 60.0                            # horizontal spokes between court edges y 515 / 575
T, DOOR = 8.0, 28.0

def hexagon(r):   # pointy top
    return Polygon([(CX + r * np.cos(np.radians(a)), CY + r * np.sin(np.radians(a))) for a in range(-90, 270, 60)])
spokes = unary_union([affinity.rotate(LineString([(CX, CY), (CX + 400, CY)]), a, origin=(CX, CY)).buffer(SPOKE_W / 2, cap_style=2)
                      for a in range(0, 360, 60)])
courts = hexagon(R_I).difference(hexagon(R_C)).difference(spokes)

def passage(x0, y0, x1, y1):   # a corridor one door wide (clear DOOR between walls), centred in the map's corridor
    if abs(x1 - x0) < abs(y1 - y0):
        xc = (x0 + x1) / 2; return box(xc - (DOOR + T) / 2, y0, xc + (DOOR + T) / 2, y1)
    yc = (y0 + y1) / 2; return box(x0, yc - (DOOR + T) / 2, x1, yc + (DOOR + T) / 2)

def room(x0, y0, x1, y1, bumps):
    return unary_union([box(x0, y0, x1, y1)] + [box(*b) for b in bumps])

parts = [
    hexagon(R_O),
    box(272, 380, 320, 710),                                          # west side of the ring, squared off
    Polygon([(347, 224), (508, 224), (520, 257), (378, 337)]),       # north-west wing
    Polygon([(673, 224), (834, 224), (834, 270), (805, 337), (662, 257)]),   # north-east wing
    Polygon([(673, 866), (834, 866), (834, 800), (805, 753), (662, 833)]),   # south-east wing
    box(876, 464, 912, 626),                                          # east bay
    passage(912, 526, 946, 564),                                      # east exit (open at its end)
    room(349, 18, 507, 175, [(338, 76, 349, 116), (407, 6, 447, 18)]),            # north-west room
    room(675, 18, 833, 175, [(665, 75, 675, 116), (833, 75, 844, 116), (734, 6, 774, 18)]),   # north-east room
    room(675, 914, 833, 1072, [(665, 973, 675, 1013), (833, 973, 844, 1013), (734, 1072, 774, 1084)]),  # south-east room
    room(145, 547, 221, 712, [(134, 606, 145, 646), (160, 540, 205, 547)]),       # west room
    passage(407, 170, 447, 229), passage(734, 170, 774, 229), passage(734, 861, 774, 919), passage(216, 606, 277, 647),
]
def into_ring(poly):   # wing corners that sit on the ring's edge are pushed 12 px into the ring along their own wall line
    pts = list(poly.exterior.coords)[:-1]; n = len(pts); out = []
    for i, p in enumerate(pts):
        if hexagon(R_O).exterior.distance(Polygon([p, (p[0] + .1, p[1]), (p[0], p[1] + .1)]).centroid) < 4:
            nb = pts[(i - 1) % n] if hexagon(R_O).exterior.distance(Polygon([pts[(i - 1) % n], (pts[(i - 1) % n][0] + .1, pts[(i - 1) % n][1]), (pts[(i - 1) % n][0], pts[(i - 1) % n][1] + .1)]).centroid) >= 4 else pts[(i + 1) % n]
            d = np.array(p) - np.array(nb); d /= np.linalg.norm(d); out.append(tuple(np.array(p) + d * 12))
        else: out.append(p)
    return Polygon(out)
floor = unary_union([into_ring(pp) if i in (2, 3, 4) else pp for i, pp in enumerate(parts)]).difference(courts)
walls = floor.buffer(T / 2, join_style=2).difference(floor.buffer(-T / 2, join_style=2))
walls = walls.difference(box(940, 526 - 20, 960, 564 + 20))      # the east exit stays open

c = cv2.imread(os.path.join(HERE, "..", "source_crop.png")); S = 2; H, Wd = c.shape[:2]
mask = np.zeros((H * S, Wd * S), np.uint8)
for p in getattr(walls, "geoms", [walls]):
    cv2.fillPoly(mask, [np.array([(x * S, y * S) for x, y in p.exterior.coords], np.int32)], 255)
    for r in p.interiors: cv2.fillPoly(mask, [np.array([(x * S, y * S) for x, y in r.coords], np.int32)], 0)
cs, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
plan = np.zeros((H * S, Wd * S, 3), np.uint8); ov = cv2.resize((c * 0.55).astype(np.uint8), None, fx=S, fy=S)
for im in (plan, ov): cv2.drawContours(im, cs, -1, (255, 255, 255), 2, cv2.LINE_AA)
cv2.imwrite(os.path.join(HERE, "plan.png"), plan)
cv2.imwrite(os.path.join(HERE, "plan_on_map.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 90])
json.dump({"units": "crop px", "centre": [CX, CY], "thickness": T, "door": DOOR, "walls": mapping(walls)}, open(os.path.join(HERE, "plan_walls.json"), "w"))
print("ok")
