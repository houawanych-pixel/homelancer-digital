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
# ---- section 2: middle (mid room, spine, two pods, centre hall, two lower rooms, Infirmary, Machine Shop, round room)
passage = box(510, 595, 685, 945)
mid = Polygon([(470, 940), (722, 940), (738, 1145), (455, 1145)])
spine = box(572, 1145, 624, 1790)
podL, podR = box(425, 1195, 572, 1300), box(624, 1195, 770, 1300)
hall = Polygon([(445, 1350), (720, 1350), (760, 1390), (760, 1540), (405, 1540), (405, 1390)])
lowL, lowR = box(445, 1540, 572, 1715), box(624, 1540, 752, 1715)
infA, infB = box(215, 1005, 400, 1335), box(215, 1335, 400, 1780)
infLink = box(400, 1405, 405, 1460)
shop = Polygon([(805, 1040), (900, 1040), (960, 1120), (960, 1340), (805, 1340)])
shopLink = box(770, 1222, 805, 1278)
annex = Polygon([(830, 1360), (945, 1360), (960, 1470), (815, 1470)])
annexLinks = [box(860, 1340, 916, 1360), box(872, 1470, 928, 1580)]
roundRm = Point(900, 1660).buffer(125, 128)
roundLink = box(752, 1610, 800, 1666)
s2_walls = [wall((470, 940), (722, 940), [127]), wall((455, 1145), (738, 1145), [142]),      # passage / mid / spine
            wall((572, 1195), (572, 1300), [52.5]), wall((624, 1195), (624, 1300), [52.5]),   # pods off the spine
            wall((445, 1350), (720, 1350), [152]),                                            # spine into the hall
            wall((405, 1540), (572, 1540), [102]), wall((624, 1540), (760, 1540), [66]), wall((572, 1540), (572, 1715), []), wall((624, 1540), (624, 1715), []),
            wall((215, 1335), (400, 1335), [92.5]),                                           # Infirmary fore / aft
            wall((402, 1390), (402, 1540), [42]),                                             # Infirmary into the hall
            wall((770, 1222), (770, 1278), [28]), wall((805, 1222), (805, 1278), [28]),       # pod into the Machine Shop
            wall((805, 1340), (960, 1340), [83]), wall((815, 1470), (960, 1470), [85]),       # shop / annex / round room
            wall((752, 1610), (752, 1666), [28])]                                             # lower room into the round room
# ---- section 3: stern (Engine Room with the two engine bays)
spine3 = box(572, 1780, 624, 1890)
engine = box(470, 1890, 750, 2100)
bayL = box(245, 1880, 470, 2125).buffer(-20).buffer(20)
bayR = box(750, 1880, 975, 2125).buffer(-20).buffer(20)
s3_walls = [wall((470, 1890), (750, 1890), [128]),                                            # spine into the Engine Room
            wall((470, 1890), (470, 2100), [105]), wall((750, 1890), (750, 2100), [105])]     # Engine Room / engine bays
floor = unary_union([spine3, engine, bayL, bayR, flight, passage, side, ops, mid, spine, podL, podR, hall, lowL, lowR, infA, infB, infLink, shop, shopLink,
                     annex, roundRm, roundLink] + annexLinks)
walls = floor.buffer(T / 2, join_style=2).difference(floor.buffer(-T / 2, join_style=2))
walls = unary_union([walls, unary_union(s1_walls + s2_walls + s3_walls).intersection(floor.buffer(T / 2, join_style=2))])

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
cv2.imwrite(os.path.join(HERE, "deck_a_s2_big.jpg"), cv2.resize(ov[880:1820, 180:1060], None, fx=1.2, fy=1.2, interpolation=cv2.INTER_CUBIC), [cv2.IMWRITE_JPEG_QUALITY, 90])
cv2.imwrite(os.path.join(HERE, "deck_a_s3_big.jpg"), cv2.resize(ov[1700:2180, 180:1060], None, fx=1.4, fy=1.4, interpolation=cv2.INTER_CUBIC), [cv2.IMWRITE_JPEG_QUALITY, 90])
cv2.imwrite(os.path.join(HERE, "deck_a_s1_big.jpg"), cv2.resize(ov[100:920, 340:900], None, fx=1.5, fy=1.5, interpolation=cv2.INTER_CUBIC), [cv2.IMWRITE_JPEG_QUALITY, 90])
json.dump({"units": "deck_a x4 px", "thickness": T, "door": DOOR, "floor": mapping(floor), "walls": mapping(walls)}, open(os.path.join(HERE, "deck_a_plan.json"), "w"))
print("ok")
