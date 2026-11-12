#!/usr/bin/env python3
"""Defender flight deck as a clean engineering plan, measured on flight_deck_x4.jpg (EDSR x4 of the 512 px minimap, 2048 px).
Same scale and rules as the lower deck (DOOR 96 px = 1.2 m, T 20)."""
import json, os, sys
import cv2, numpy as np
from shapely.geometry import LineString, Point, Polygon, box, mapping
from shapely.ops import unary_union, substring

HERE = os.path.dirname(os.path.abspath(__file__))
T, DOOR = 20.0, 96.0
def wall(p0, p1, doors=()):
    L = LineString([p0, p1]); cuts = [0.0]
cockpit = unary_union([box(871, 30, 1120, 433), box(830, 240, 1135, 433)])       # cockpit / bridge
roomL = box(413, 133, 727, 433)                                                    # port room
roomR = Polygon([(1160, 100), (1450, 93), (1580, 140), (1580, 433), (1160, 433)])  # starboard room (table)
smallL, smallR = box(567, 433, 760, 660), box(1220, 433, 1407, 660)               # small side rooms
hall = box(787, 433, 1207, 1100).buffer(-30, join_style=1).buffer(30, join_style=1).union(box(787, 433, 1207, 600))
link = box(900, 1090, 1075, 1360)                                                  # sloped passage to the round room
RC = (987, 1619)
rnd = Point(RC).buffer(300, 16)                                                    # round meditation / training room
alcL = box(585, 1515, 700, 1725).buffer(-25, join_style=2).buffer(25, join_style=1)
alcB = box(900, 1890, 1075, 2010)
trap = Polygon([(1345, 1395), (1635, 1458), (1635, 1800), (1345, 1855)])          # side room off the round room
trapLink = box(1270, 1572, 1345, 1668)
inner = [wall((871, 433), (1120, 433), [122]),                                     # cockpit into the hall
         wall((567, 433), (727, 433), [73]), wall((1220, 433), (1407, 433), [117]),   # side rooms into the big rooms
         wall((760, 505), (760, 660), [48]), wall((1220, 505), (1220, 660), [48]),    # side rooms into the hall
         wall((900, 1100), (1075, 1100), [87.5]),                                  # hall into the passage
         wall((900, 1322), (1075, 1322), [87.5]),                                  # passage into the round room
         wall((1345, 1572), (1345, 1668), [48])]                                   # round room into the side room
LABELS = [((995, 230), '4 Bridge'), ((995, 110), '5 Navi-|computer'), ((570, 280), '7 Living|Accommodations'), ((1370, 280), '6 Secondary|Conference'), ((663, 560), '10 Escape|Pod'), ((1313, 560), '9 Bunks'), ((997, 700), '8 Boarding|Ramp'), ((990, 1190), '11 To Lower|Deck'), ((987, 1560), '13 Main|Conference Room'), ((987, 1720), '14 Holoterminal'), ((640, 1800), '15 Port|Hatch'), ((1490, 1630), '16 Starboard|Hatch')]
floor = unary_union([cockpit, roomL, roomR, smallL, smallR, hall, link, rnd, alcL, alcB, trap, trapLink])
walls = floor.buffer(T / 2, join_style=2).difference(floor.buffer(-T / 2, join_style=2))
walls = unary_union([walls, unary_union(inner).intersection(floor.buffer(T / 2, join_style=2))])

src = cv2.imread(os.path.join(HERE, "..", "flight_deck_x4.jpg")); H, W = src.shape[:2]
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
cv2.imwrite(os.path.join(HERE, "flight_plan.png"), plan)
cv2.imwrite(os.path.join(HERE, "flight_plan_on_map.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 88])
json.dump({"units": "flight_deck_x4 px", "thickness": T, "door": DOOR, "floor": mapping(floor), "walls": mapping(walls)},
          open(os.path.join(HERE, "flight_plan.json"), "w"))
print("ok")
