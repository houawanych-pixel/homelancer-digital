#!/usr/bin/env python3
"""Darth Malgus's space station, Command Deck (SWTOR flashpoint "The False Emperor"; identified from the owner's in-game screenshots) as a clean engineering plan, measured on map_x4.jpg (EDSR x4, crop x 100-660 of the source).
Centre of the hub and of both fan wings: C = (1545, 1490). Top and bottom halves mirror about y 1490 (fans, middle block, airlocks);
the north and south spines differ and are measured separately. Scale not set yet (DOOR 60 px)."""
import json, os, math
import cv2, numpy as np
from shapely.geometry import LineString, Point, Polygon, box, mapping
from shapely.ops import unary_union, substring
from shapely import affinity

HERE = os.path.dirname(os.path.abspath(__file__))
T, DOOR = 16.0, 60.0
C = (1545.0, 1490.0)
MY = lambda g: affinity.scale(g, 1, -1, origin=(0, C[1]))
def wall(p0, p1, doors=()):
    L = LineString([p0, p1]); cuts = [0.0]
    for d in doors: cuts += [d - DOOR / 2, d + DOOR / 2]
    cuts.append(L.length)
    return unary_union([substring(L, cuts[i], cuts[i + 1]).buffer(T / 2, cap_style=2) for i in range(0, len(cuts), 2) if cuts[i + 1] > cuts[i]])
def ring(r, door_deg, w=DOOR):
    g = Point(C).buffer(r + T / 2, 256).difference(Point(C).buffer(r - T / 2, 256))
    for a in door_deg:
        a = math.radians(a); u = (math.cos(a), math.sin(a))
        cut = LineString([(C[0] + (r - 40) * u[0], C[1] + (r - 40) * u[1]), (C[0] + (r + 40) * u[0], C[1] + (r + 40) * u[1])]).buffer(w / 2, cap_style=2)
        g = g.difference(cut)
    return g
def radial(a_deg, r0, r1, doors=()):
    a = math.radians(a_deg); u = (math.cos(a), math.sin(a))
    return wall((C[0] + r0 * u[0], C[1] + r0 * u[1]), (C[0] + r1 * u[0], C[1] + r1 * u[1]), doors)

# ---- fan wings (top measured, bottom mirrored): annulus sector R 735-1468 cut by x 1310 and y 1255
fanT = Point(C).buffer(1468, 512).intersection(box(0, 0, 1310, 1255)).difference(Point(C).buffer(735, 512))
mid = box(330, 1395, 880, 1585)                      # middle block between the fans
stN = box(605, 1240, 839, 1395)                      # stairs up into the top fan
brW = box(880, 1440, 975, 1540); airW = box(975, 1369, 1125, 1611)   # bridge and west airlock
airE = affinity.scale(airW, -1, 1, origin=(C[0], 0))
hub = Point(C).buffer(430, 256)                     # hub hall; the centre circle is a railing, not a wall
# ---- north spine
oct1 = Point(1546, 94).buffer(52, 2); roomA = box(1431, 144, 1656, 262)
hallN = unary_union([box(1460, 262, 1640, 775), box(1310, 550, 1656, 775)])
oct2 = unary_union([Point(1546, 840).buffer(56, 2), box(1518, 770, 1574, 800)]); roomC = box(1431, 875, 1656, 1080)
# ---- south spine
stS = box(1437, 1900, 1650, 2177)
hallS = unary_union([box(1310, 2177, 1650, 2400), box(1437, 2400, 1650, 2697)])

half = [wall((330, 1395), (880, 1395), [392]), wall((605, 1255), (839, 1255), [117]),   # middle block / stairs / top fan
        wall((880, 1440), (880, 1540), [50]), wall((975, 1440), (975, 1540), [50]),       # middle block / bridge / airlock
        ]   # the radial lines in the wings are the raised stage and its steps (see FEATURES), not walls
inner = half + [MY(w) for w in half] + [
        wall((2115, 1440), (2115, 1540), [50]),
        ring(430, [270, 90, 180, 0]), ring(330, [270, 90, 180, 0], 130),                   # hub: outer and gallery walls
        wall((1431, 144), (1656, 144), [115]), wall((1431, 262), (1656, 262), [115]),     # north spine rooms
        wall((1310, 550), (1310, 775), [112]), wall((1460, 775), (1640, 775), [86]), wall((1431, 875), (1656, 875), [115]),
        wall((1437, 2177), (1650, 2177), [108]), wall((1310, 2177), (1310, 2400), [111])]  # south spine
def sector(a0, a1, r0, r1):
    pts = [(C[0] + r * math.cos(math.radians(a)), C[1] + r * math.sin(math.radians(a))) for r, rng in ((r1, np.linspace(a0, a1, 24)), (r0, np.linspace(a1, a0, 24))) for a in rng]
    return Polygon(pts)
stage = sector(220, 229, 735, 1200)
# level changes from the in-game screenshots: yellow lines, not walls
FEATURES = [(stage, 'raised stage + steps'), (MY(stage), 'raised stage + steps'),
            (box(1460, 262, 1640, 550), 'big stairs'), (stN, 'stairs'), (MY(stN), 'stairs'),
            (box(1477, 1046, 1608, 1270), 'stairs'), (MY(box(1477, 1046, 1608, 1270)), 'stairs'),
            (Point(C).buffer(108, 128), 'centre ring (railing)'), (stS, 'stairs')]
floor = unary_union([fanT, MY(fanT), mid, stN, MY(stN), brW, airW, airE, hub, oct1, roomA, hallN, oct2, roomC, stS, hallS])
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
for im in (plan, ov): cv2.drawContours(im, cs, -1, (255, 255, 255), 4, cv2.LINE_AA)
for g, name in FEATURES:
    pts = np.array(g.exterior.coords, np.int32)
    c = g.centroid
    for im in (plan, ov):
        cv2.polylines(im, [pts], True, (60, 210, 255), 3, cv2.LINE_AA)
        (w, h), _ = cv2.getTextSize(name, cv2.FONT_HERSHEY_SIMPLEX, 1.0, 2)
        cv2.putText(im, name, (int(c.x - w / 2), int(c.y)), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (60, 210, 255), 2, cv2.LINE_AA)
cv2.imwrite(os.path.join(HERE, "plan.png"), plan)
cv2.imwrite(os.path.join(HERE, "plan_on_map.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 85])
json.dump({"features": [{"name": n, "shape": mapping(g)} for g, n in FEATURES], "units": "map_x4 px", "thickness": T, "door": DOOR, "centre": C, "floor": mapping(floor), "walls": mapping(walls)},
          open(os.path.join(HERE, "plan.json"), "w"))
print("ok")
