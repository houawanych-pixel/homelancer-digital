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

corr = box(313, 1310, 1757, 1430)                                                  # main cross corridor
r7 = box(229, 1300, 313, 1440); r9 = M(r7)                                         # 7 / 9 turret maintenance hatches
r2 = Polygon([(290, 1310), (290, 1110), (435, 860), (560, 860), (560, 1310)])      # 2 Cargo Hold
r3 = Polygon([(600, 1025), (790, 1025), (790, 1180), (645, 1310), (600, 1310)])    # 3 Crew Quarters
r1 = unary_union([box(908, 915, 1162, 1120), box(985, 875, 1085, 915)])            # 1 Bridge
r8 = Polygon([(666, 1310), (908, 1120), (1162, 1120), (1290, 1190), (1290, 1310)]) # 8 Lounge
lobby = unary_union([box(1162, 1000, 1390, 1110), box(1300, 1110, 1390, 1310)])    # passage bridge -> lockers -> corridor
r4 = Polygon([(1440, 963), (1512, 1035), (1440, 1107), (1368, 1035)])              # 4 Ship's Locker
r5 = Polygon([(1460, 855), (1650, 855), (1700, 1000), (1700, 1060), (1537, 1060), (1440, 963)])   # 5 Captain's Quarters
r6 = box(1490, 1060, 1720, 1310)                                                   # 6 Secondary Quarters
r10 = Polygon([(295, 1430), (680, 1430), (680, 1745), (345, 1745), (295, 1695)]); r13 = M(r10)   # 10 / 13 engine rooms
r11 = Polygon([(690, 1430), (880, 1430), (880, 1673), (740, 1673), (690, 1623)]); r12 = M(r11)   # 11 Medical Bay / 12 Fresher
r14 = box(950, 1430, 1120, 1710)                                                   # 14 ventral entry ramp
r15 = box(1000, 1710, 1070, 1830)                                                  # 15 access to the aft escape pod
LABELS = [((1035, 1010), '1 Bridge'), ((425, 1200), '2 Cargo'), ((700, 1120), '3 Crew'), ((1440, 1045), '4'),
          ((1575, 930), '5 Captain'), ((1605, 1190), '6 Quarters'), ((271, 1380), '7'), ((1799, 1380), '9'),
          ((1035, 1230), '8 Lounge'), ((490, 1590), '10 Engine'), ((1580, 1590), '13 Engine'), ((785, 1550), '11 Med'),
          ((1285, 1550), '12 Fresher'), ((1035, 1560), '14 Ramp'), ((1035, 1780), '15')]
side = [wall((313, 1310), (313, 1430), [60]),                                      # corridor / hatch
        wall((290, 1310), (560, 1310), [170]),                                     # Cargo Hold
        wall((295, 1430), (680, 1430), [290]),                                     # engine room
        wall((690, 1430), (880, 1430), [95])]                                      # Medical Bay / Fresher
inner = side + [M(w) for w in side] + [
        wall((600, 1310), (645, 1310), [22.5]),                                      # Crew Quarters
        wall((666, 1310), (1290, 1310), [369]),                                    # Lounge into the corridor
        wall((908, 1120), (1162, 1120), [127]),                                    # Bridge into the Lounge
        wall((1162, 1000), (1162, 1120), [60]),                                    # Bridge into the passage
        wall((1300, 1310), (1390, 1310), [45]),                                    # passage into the corridor
        wall((1368, 1035), (1440, 1107), [51]),                                    # passage into the lockers (4)
        wall((1440, 963), (1512, 1035), [51]),                                     # lockers into the Captain's Quarters
        wall((1537, 1060), (1700, 1060), [81]),                                    # Captain / Secondary Quarters
        wall((1490, 1310), (1720, 1310), [115]),                                   # Secondary Quarters into the corridor
        wall((950, 1430), (1120, 1430), [85]),                                     # ramp room
        wall((1000, 1710), (1070, 1710), [35])]                                    # escape pod access
floor = unary_union([corr, r7, r9, r2, r3, r1, r8, lobby, r4, r5, r6, r10, r13, r11, r12, r14, r15])
walls = floor.buffer(T / 2, join_style=2).difference(floor.buffer(-T / 2, join_style=2))
walls = unary_union([walls, unary_union(inner).intersection(floor.buffer(T / 2, join_style=2))])

src = cv2.imread(os.path.join(HERE, "..", "map_x4.jpg")); H, W = src.shape[:2]
mask = np.zeros((H, W), np.uint8)
for p in getattr(walls, "geoms", [walls]):
    m1 = np.zeros_like(mask); cv2.fillPoly(m1, [np.array(p.exterior.coords, np.int32)], 255)
    for r in p.interiors: cv2.fillPoly(m1, [np.array(r.coords, np.int32)], 0)
    mask |= m1
cs, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
plan = np.zeros_like(src); ov = (src * 0.45).astype(np.uint8)
for im in (plan, ov): cv2.drawContours(im, cs, -1, (255, 255, 255), 3, cv2.LINE_AA)
for (x, y), t in LABELS:
    for im in (plan, ov):
        (w, h), _ = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)
        cv2.putText(im, t, (int(x - w / 2), int(y)), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (80, 220, 255), 2, cv2.LINE_AA)
cv2.imwrite(os.path.join(HERE, "plan.png"), plan[750:1950, 150:1950])
cv2.imwrite(os.path.join(HERE, "plan_on_map.jpg"), ov[750:1950, 150:1950], [cv2.IMWRITE_JPEG_QUALITY, 88])
json.dump({"units": "map_x4 px", "px_per_m": 40.0, "thickness": T, "door": DOOR, "mirror_x": AX, "floor": mapping(floor), "walls": mapping(walls)},
          open(os.path.join(HERE, "plan.json"), "w"))
print("ok")
