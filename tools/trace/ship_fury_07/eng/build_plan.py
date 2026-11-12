#!/usr/bin/env python3
"""Fury-class Interceptor (one deck) as a clean engineering plan, measured on map_x4.jpg (EDSR x4 of the owner's labelled sheet).
Real size from the sheet: 47.8 m long, 41 m wide; its 10 ft scale bar = 120 px, so ~40 px/m: DOOR 48 px = 1.2 m, T 12.
Room numbers as on the sheet. Left/right engine rooms, hatches and med bay/fresher are mirrored about x 1035."""
import json, os, sys
import cv2, numpy as np
from shapely.geometry import LineString, Point, Polygon, box, mapping
from shapely.ops import unary_union, substring

HERE = os.path.dirname(os.path.abspath(__file__))
T, DOOR = 12.0, 48.0
AX = 1035.0
from shapely import affinity
M = lambda g: affinity.scale(g, -1, 1, origin=(AX, 0))
def wall(p0, p1, doors=()):
    L = LineString([p0, p1]); cuts = [0.0]
    for d in doors: cuts += [d - DOOR / 2, d + DOOR / 2]
    cuts.append(L.length)
    return unary_union([substring(L, cuts[i], cuts[i + 1]).buffer(T / 2, cap_style=2) for i in range(0, len(cuts), 2) if cuts[i + 1] > cuts[i]])

corr = box(330, 1313, 1740, 1434)                                                  # main cross corridor (measured 1313-1434)
r7 = box(238, 1313, 330, 1434); r9 = M(r7)                                         # 7 / 9 turret maintenance hatches
r2 = Polygon([(290, 1265), (290, 1110), (435, 860), (560, 860), (560, 1265)])      # 2 Cargo Hold
c2 = box(426, 1265, 497, 1313)                                                     # stepped connector Cargo -> corridor
r3 = Polygon([(610, 1050), (865, 1050), (865, 1150), (690, 1313), (610, 1313)])    # 3 Crew Quarters (shares the diagonal with the Lounge)
r1 = Polygon([(905, 1135), (905, 990), (985, 915), (1085, 915), (1165, 990), (1165, 1135)])   # 1 Bridge (chevron nose)
r8 = Polygon([(690, 1313), (865, 1150), (865, 1135), (1218, 1135), (1218, 1313)])  # 8 Lounge
lobby = Polygon([(1165, 1000), (1403, 1000), (1403, 1313), (1218, 1313), (1218, 1135), (1165, 1135)])   # passage bridge -> lockers -> corridor
r4 = Polygon([(1447, 941), (1522, 1016), (1447, 1091), (1372, 1016)])              # 4 Ship's Locker (45 deg)
r5 = Polygon([(1472, 840), (1672, 840), (1734, 1000), (1734, 1045), (1551, 1045), (1447, 941), (1472, 916)])   # 5 Captain's Quarters
r6 = Polygon([(1525, 1045), (1740, 1045), (1780, 1090), (1780, 1313), (1485, 1313), (1485, 1150), (1525, 1150)])  # 6 Secondary Quarters
r10 = Polygon([(297, 1484), (667, 1484), (667, 1612), (705, 1650), (705, 1745), (440, 1745), (297, 1690)]); r13 = M(r10)   # 10 / 13 engine rooms
c10 = box(426, 1434, 497, 1484); c13 = M(c10)                                      # stepped connectors corridor -> engine rooms
r11 = Polygon([(667, 1470), (880, 1470), (880, 1680), (735, 1680), (667, 1612)]); r12 = M(r11)   # 11 Medical Bay / 12 Fresher
c11 = box(760, 1434, 808, 1470); c12 = M(c11)
r14 = box(950, 1434, 1120, 1710)                                                   # 14 ventral entry ramp
r15 = box(1000, 1710, 1070, 1830)                                                  # 15 access to the aft escape pod
LABELS = [((1035, 1040), '1 Bridge'), ((425, 1200), '2 Cargo'), ((720, 1110), '3 Crew'), ((1447, 1026), '4'),
          ((1600, 930), '5 Captain'), ((1630, 1200), '6 Quarters'), ((284, 1380), '7'), ((1786, 1380), '9'),
          ((1035, 1240), '8 Lounge'), ((490, 1620), '10 Engine'), ((1580, 1620), '13 Engine'), ((790, 1570), '11 Med'),
          ((1280, 1570), '12 Fresher'), ((1035, 1560), '14 Ramp'), ((1035, 1780), '15')]
side = [wall((330, 1313), (330, 1434), [60.5]),                                    # corridor / hatch
        wall((426, 1265), (497, 1265), [35.5]), wall((426, 1484), (497, 1484), [35.5]),   # Cargo / engine room connectors
        wall((760, 1470), (808, 1470), [24])]                                      # Medical Bay / Fresher
inner = side + [M(w) for w in side] + [
        wall((610, 1313), (690, 1313), [40]),                                      # Crew Quarters into the corridor
        wall((690, 1313), (865, 1150), []),                                        # Crew Quarters / Lounge (shared diagonal)
        wall((690, 1313), (1218, 1313), [345]),                                    # Lounge into the corridor
        wall((905, 1135), (1165, 1135), [130]),                                    # Bridge into the Lounge
        wall((1165, 1000), (1165, 1135), [67]),                                    # Bridge into the passage
        wall((1218, 1313), (1403, 1313), [92]),                                    # passage into the corridor
        wall((1218, 1135), (1218, 1313), [89]),                                    # Lounge / passage
        wall((1372, 1016), (1447, 1091), [53]),                                    # passage into the lockers (4)
        wall((1447, 941), (1522, 1016), [53]),                                     # lockers into the Captain's Quarters
        wall((1525, 1045), (1734, 1045), [110]),                                   # Captain / Secondary Quarters
        wall((1485, 1313), (1780, 1313), [147]),                                   # Secondary Quarters into the corridor
        wall((950, 1434), (1120, 1434), [85]),                                     # ramp room
        wall((1000, 1710), (1070, 1710), [35])]                                    # escape pod access
floor = unary_union([corr, r7, r9, r2, c2, r3, r1, r8, lobby, r4, r5, r6, r10, r13, c10, c13, r11, r12, c11, c12, r14, r15])
walls = floor.buffer(T / 2, join_style=2).difference(floor.buffer(-T / 2, join_style=2))
walls = unary_union([walls, unary_union(inner).intersection(floor.buffer(T / 2, join_style=2))])
walls = unary_union([p for p in getattr(walls, 'geoms', [walls]) if p.area > 600])   # drop slivers

src = cv2.imread(os.path.join(HERE, "..", "map_x4.jpg")); H, W = src.shape[:2]
mask = np.zeros((H, W), np.uint8)
for p in getattr(walls, "geoms", [walls]):
    m1 = np.zeros_like(mask); cv2.fillPoly(m1, [np.array(p.exterior.coords, np.int32)], 255)
    for r in p.interiors: cv2.fillPoly(m1, [np.array(r.coords, np.int32)], 0)
    mask |= m1
cs, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
plan = np.zeros_like(src); ov = (src * 0.45).astype(np.uint8)
for im in (plan, ov): cv2.drawContours(im, cs, -1, (255, 255, 255), 3, cv2.LINE_AA)
HULL = np.array(json.load(open(os.path.join(HERE, "hull_outline.json")))["outline"], np.int32)   # exterior, light red
for im in (plan, ov): cv2.polylines(im, [HULL], True, (110, 110, 255), 4, cv2.LINE_AA)
for (x, y), t in LABELS:
    for im in (plan, ov):
        (w, h), _ = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)
        cv2.putText(im, t, (int(x - w / 2), int(y)), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (80, 220, 255), 2, cv2.LINE_AA)
cv2.imwrite(os.path.join(HERE, "plan.png"), plan[0:2080, 150:1950])
cv2.imwrite(os.path.join(HERE, "plan_on_map.jpg"), ov[0:2080, 150:1950], [cv2.IMWRITE_JPEG_QUALITY, 88])
json.dump({"units": "map_x4 px", "px_per_m": 40.0, "thickness": T, "door": DOOR, "mirror_x": AX, "floor": mapping(floor), "walls": mapping(walls)},
          open(os.path.join(HERE, "plan.json"), "w"))
print("ok")
