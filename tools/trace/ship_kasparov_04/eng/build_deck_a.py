#!/usr/bin/env python3
"""Kasparov upper deck (deck A) as a clean engineering plan, measured on deck_a_x4.jpg (EDSR x4 px).
Same method as the Tianjin: floors from measured walls, walls = floor edge +/- T/2, inner walls as centre lines with
standard doors (DOOR clear), arcs as true circles. Built nose to stern, one section at a time."""
import json, os
import cv2, numpy as np
from shapely.geometry import LineString, Point, Polygon, box, mapping
from shapely.ops import unary_union, substring

HERE = os.path.dirname(os.path.abspath(__file__))
T, DOOR = 12.0, 56.0
def wall(p0, p1, doors=()):
    L = LineString([p0, p1]); cuts = [0.0]
    for d in doors: cuts += [d - DOOR / 2, d + DOOR / 2]
    cuts.append(L.length)
    return unary_union([substring(L, cuts[i], cuts[i + 1]).buffer(T / 2, cap_style=2) for i in range(0, len(cuts), 2) if cuts[i + 1] > cuts[i]])

# ---- section 1: nose (Flight Deck, Fore Passage top, side room, OPS)
flight = unary_union([Point(597, 312).buffer(172, 128).intersection(box(0, 0, 9999, 312)), box(425, 312, 770, 595)])
passage = box(510, 595, 685, 900)
side = box(392, 660, 510, 730)
ops = unary_union([box(685, 648, 790, 842), Point(790, 745).buffer(72, 96)])
s1_walls = [wall((510, 595), (685, 595), [87.5]),            # Flight Deck / Fore Passage
            wall((510, 660), (510, 730), [35]),               # side room off the passage
            wall((685, 648), (685, 842), [97])]               # OPS off the passage
floor = unary_union([flight, passage, side, ops])
walls = floor.buffer(T / 2, join_style=2).difference(floor.buffer(-T / 2, join_style=2))
walls = unary_union([walls, unary_union(s1_walls).intersection(floor.buffer(T / 2, join_style=2))])
walls = walls.difference(box(516, 890, 679, 910))            # the passage runs on aft (next section)

src = cv2.imread(os.path.join(HERE, "..", "deck_a_x4.jpg")); H, W = src.shape[:2]
mask = np.zeros((H, W), np.uint8)
for p in getattr(walls, "geoms", [walls]):
    m1 = np.zeros_like(mask); cv2.fillPoly(m1, [np.array(p.exterior.coords, np.int32)], 255)
    for r in p.interiors: cv2.fillPoly(m1, [np.array(r.coords, np.int32)], 0)
    mask |= m1
cs, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
plan = np.zeros_like(src); ov = (src * 0.5).astype(np.uint8)
for im in (plan, ov): cv2.drawContours(im, cs, -1, (255, 255, 255), 3, cv2.LINE_AA)
cv2.imwrite(os.path.join(HERE, "deck_a_plan.png"), plan)
cv2.imwrite(os.path.join(HERE, "deck_a_plan_on_map.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 88])
cv2.imwrite(os.path.join(HERE, "deck_a_s1_big.jpg"), cv2.resize(ov[100:920, 340:900], None, fx=1.5, fy=1.5, interpolation=cv2.INTER_CUBIC), [cv2.IMWRITE_JPEG_QUALITY, 90])
json.dump({"units": "deck_a x4 px", "thickness": T, "door": DOOR, "floor": mapping(floor), "walls": mapping(walls)}, open(os.path.join(HERE, "deck_a_plan.json"), "w"))
print("ok")
