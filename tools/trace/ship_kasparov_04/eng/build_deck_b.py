#!/usr/bin/env python3
"""Kasparov lower deck (deck B) as a clean engineering plan, measured on deck_b_x4.jpg (EDSR x4 px).
Mirror-symmetric about x = 681: the left half is measured and mirrored. Same wall/door rules as deck A."""
import json, os, math
import cv2, numpy as np
from shapely.geometry import LineString, Point, Polygon, box, mapping
from shapely.ops import unary_union, substring
from shapely import affinity

HERE = os.path.dirname(os.path.abspath(__file__))
T, DOOR, AX = 12.0, 56.0, 681.0
def wall(p0, p1, doors=()):
    L = LineString([p0, p1]); cuts = [0.0]
    for d in doors: cuts += [d - DOOR / 2, d + DOOR / 2]
    cuts.append(L.length)
    return unary_union([substring(L, cuts[i], cuts[i + 1]).buffer(T / 2, cap_style=2) for i in range(0, len(cuts), 2) if cuts[i + 1] > cuts[i]])
def ringwall(c, r, door_deg=()):
    ring = Point(c).buffer(r + T / 2, 256).difference(Point(c).buffer(r - T / 2, 256))
    for a in door_deg:   # image angles: 0 = east, 90 = down (aft)
        a = math.radians(a); d = Point(c[0] + r * math.cos(a), c[1] + r * math.sin(a))
        ring = ring.difference(d.buffer(DOOR / 2 / math.cos(0) , 64).union(
            LineString([c, (c[0] + (r + 40) * math.cos(a), c[1] + (r + 40) * math.sin(a))]).buffer(DOOR / 2, cap_style=2).intersection(d.buffer(30))))
    return ring
M = lambda g: affinity.scale(g, -1, 1, origin=(AX, 0))
def sym(gs): return gs + [M(g) for g in gs]

# ---- nose: bow room, second cabin, Passenger Quarters
bow = box(570, 145, 792, 285).buffer(-40, join_style=1).buffer(40, join_style=1).union(box(570, 200, 792, 285))
cabin = box(565, 285, 797, 432)
quarters = Polygon([(515, 432), (847, 432), (893, 690), (469, 690)])
# ---- mid: two rooms either side of the centre corridor, round Dining Area
roomL = box(452, 690, 645, 905)
corr = box(645, 690, 717, 1000)
DC, DR = (681, 1150), 185
dining = Point(DC).buffer(DR, 256)
# ---- Storage & Lockers: one curved wing each side, around the Dining Area
stor = Point(DC).buffer(480, 256).intersection(box(205, 1205, 620, 1600))
spine = box(620, 1300, 742, 1745)
# ---- aft: cross hall to Storage room / Cargo Bay, corridor to the Reactor
cross = Polygon([(620, 1700), (742, 1700), (787, 1745), (857, 1745), (857, 1880), (505, 1880), (505, 1745), (575, 1745)])
sroom = box(245, 1605, 505, 1995)
aft = box(625, 1880, 737, 1965)
reactor = box(553, 1965, 809, 2228)

inner = sym([wall((452, 905), (645, 905), []),
             wall((645, 690), (645, 905), [110]),                    # corridor into the side rooms
             wall((620, 1320), (620, 1605), [140]),                  # Storage & Lockers into the spine
             wall((505, 1745), (505, 1880), [67]),                   # cross hall into the Storage room / Cargo Bay
             ]) + [wall((565, 285), (797, 285), [116]), wall((515, 432), (847, 432), [166]),
                   wall((452, 690), (910, 690), [229]),              # quarters into the corridor
                   wall((625, 1965), (737, 1965), [56]),             # corridor into the Reactor
                   ringwall(DC, DR, [270, 90, 135, 45])]             # Dining Area: fore, aft, both Storage wings
floor = unary_union(sym([roomL, stor, sroom]) + [bow, cabin, quarters, corr, dining, spine, cross, aft, reactor])
walls = floor.buffer(T / 2, join_style=2).difference(floor.buffer(-T / 2, join_style=2))
walls = unary_union([walls, unary_union(inner).intersection(floor.buffer(T / 2, join_style=2))])
# keep the door gaps open where the ring meets the outline
for a in (270, 90, 135, 45):
    p = (DC[0] + DR * math.cos(math.radians(a)), DC[1] + DR * math.sin(math.radians(a)))
    walls = walls.difference(Point(p).buffer(DOOR / 2 - 1).intersection(floor.buffer(-0.1)))

src = cv2.imread(os.path.join(HERE, "..", "deck_b_x4.jpg")); H, W = src.shape[:2]
mask = np.zeros((H, W), np.uint8)
for p in getattr(walls, "geoms", [walls]):
    m1 = np.zeros_like(mask); cv2.fillPoly(m1, [np.array(p.exterior.coords, np.int32)], 255)
    for r in p.interiors: cv2.fillPoly(m1, [np.array(r.coords, np.int32)], 0)
    mask |= m1
cs, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
plan = np.zeros_like(src); ov = (src * 0.5).astype(np.uint8)
for im in (plan, ov): cv2.drawContours(im, cs, -1, (255, 255, 255), 3, cv2.LINE_AA)
cv2.imwrite(os.path.join(HERE, "deck_b_plan.png"), plan)
cv2.imwrite(os.path.join(HERE, "deck_b_plan_on_map.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 88])
json.dump({"units": "deck_b x4 px", "thickness": T, "door": DOOR, "mirror_x": AX, "floor": mapping(floor), "walls": mapping(walls)},
          open(os.path.join(HERE, "deck_b_plan.json"), "w"))
print("ok")
