#!/usr/bin/env python3
"""Defender lower deck as a clean engineering plan, measured on lower_deck_x4.jpg (EDSR x4 of the 512 px minimap, 2048 px).
Floors are the measured inner wall faces; walls = floor edge +/- T/2; inner walls as centre lines with standard doors.
Scale: 0.63 x the flight deck minimap (measured against the labelled sheet: hall widths and the wings vs the round room)."""
import json, os, sys
import cv2, numpy as np
from shapely.geometry import LineString, Polygon, box, mapping
from shapely.ops import unary_union, substring

HERE = os.path.dirname(os.path.abspath(__file__))
T, DOOR = 32.0, 152.0   # this minimap is zoomed ~1.6x vs the flight deck one (0.63 scale), so 152 px here = 96 px there = 1.2 m
def wall(p0, p1, doors=()):
    L = LineString([p0, p1]); cuts = [0.0]
    for d in doors: cuts += [d - DOOR / 2, d + DOOR / 2]
    cuts.append(L.length)
    return unary_union([substring(L, cuts[i], cuts[i + 1]).buffer(T / 2, cap_style=2) for i in range(0, len(cuts), 2) if cuts[i + 1] > cuts[i]])

ramp = box(1240, 60, 1370, 494)                                   # stairs up to the flight deck (11 on the labelled sheet)
hall = box(1071, 494, 1382, 1076)                                 # 17 Central Access Chamber
passL, passR = box(908, 790, 1071, 935), box(1382, 790, 1560, 935)   # stepped side passages
wingL = Polygon([(47, 641), (318, 565), (565, 535), (908, 535), (908, 1171), (565, 1171), (318, 1135), (47, 1088)])   # 19 Cargo Hold
wingR = Polygon([(1560, 565), (2012, 659), (2012, 1065), (1560, 1153)])                                               # 18 Medical Bay
stairs = box(1071, 1076, 1250, 1268)                              # stairs down to the engine room
engine = unary_union([box(668, 1268, 1410, 1480),
                      Polygon([(815, 1480), (1250, 1480), (1145, 1565), (1145, 1770), (1120, 1790), (1120, 1990),
                               (950, 1990), (950, 1790), (925, 1770), (925, 1565)])])
inner = [wall((1240, 494), (1370, 494), [65]),                    # stairs into the hall
         wall((1071, 790), (1071, 935), [72.5]), wall((908, 790), (908, 935), [72.5]),     # hall / port passage / cargo hold
         wall((1382, 790), (1382, 935), [72.5]), wall((1560, 790), (1560, 935), [72.5]),   # hall / starboard passage / hold
         wall((1071, 1076), (1250, 1076), [89.5]), wall((1071, 1268), (1250, 1268), [89.5])]   # hall / stairs / engine room
LABELS = [((1305, 300), '11 Stairs up'), ((1226, 700), '17 Central|Access'), ((480, 850), '19 Cargo Hold'), ((1780, 860), '18 Medical Bay'), ((1160, 1180), 'stairs'), ((1035, 1380), '21 Engine Room')]
floor = unary_union([ramp, hall, passL, passR, wingL, wingR, stairs, engine])
walls = floor.buffer(T / 2, join_style=2).difference(floor.buffer(-T / 2, join_style=2))
walls = unary_union([walls, unary_union(inner).intersection(floor.buffer(T / 2, join_style=2))])

src = cv2.imread(os.path.join(HERE, "..", "lower_deck_x4.jpg")); H, W = src.shape[:2]
mask = np.zeros((H, W), np.uint8)
for p in getattr(walls, "geoms", [walls]):
    m1 = np.zeros_like(mask); cv2.fillPoly(m1, [np.array(p.exterior.coords, np.int32)], 255)
    for r in p.interiors: cv2.fillPoly(m1, [np.array(r.coords, np.int32)], 0)
    mask |= m1
cs, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
plan = np.zeros_like(src); ov = (src * 0.5).astype(np.uint8)
for im in (plan, ov): cv2.drawContours(im, cs, -1, (255, 255, 255), 4, cv2.LINE_AA)
for (x, y), t in LABELS:   # room names from the owner's labelled Defender sheet (numbers as on that sheet)
    for k, line in enumerate(t.split("|")):
        for im in (plan, ov):
            (w, h), _ = cv2.getTextSize(line, cv2.FONT_HERSHEY_SIMPLEX, 1.1, 2)
            cv2.putText(im, line, (int(x - w / 2), int(y + k * 40)), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (80, 220, 255), 2, cv2.LINE_AA)
cv2.imwrite(os.path.join(HERE, "lower_plan.png"), plan)
cv2.imwrite(os.path.join(HERE, "lower_plan_on_map.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 88])
json.dump({"units": "lower_deck_x4 px", "thickness": T, "door": DOOR, "floor": mapping(floor), "walls": mapping(walls)},
          open(os.path.join(HERE, "lower_plan.json"), "w"))
print("ok")
