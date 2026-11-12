#!/usr/bin/env python3
"""Round station (game minimap the owner sent): four wings around a central hub, joined by four spokes.
Measured on map_x4.jpg (EDSR x4) partly in polar form (cv2.warpPolar about the hub centre) so the rings read as straight lines.
One wing (the top-left quadrant, 180-270 deg, symmetric about 225 deg) is drawn in polar (angle, radius) and rotated to all four.
Spokes W, E, S end in an end room with a small round bulb; the N spoke stops at its cross room. Scale not set yet (DOOR 56 px)."""
import json, os, math
import cv2, numpy as np
from shapely.geometry import LineString, Point, Polygon, box, mapping
from shapely.ops import unary_union, substring
from shapely import affinity

HERE = os.path.dirname(os.path.abspath(__file__))
T, DOOR = 12.0, 56.0
C = (950.0, 963.0)
def P(a, r): return (C[0] + r * math.cos(math.radians(a)), C[1] + r * math.sin(math.radians(a)))   # image angles: 180 = W, 270 = N
def sector(a0, a1, r0, r1, n=48):
    return Polygon([P(a, r1) for a in np.linspace(a0, a1, n)] + [P(a, r0) for a in np.linspace(a1, a0, n)])
def wall_line(pts, doors=()):
    L = LineString(pts); cuts = [0.0]
    for d in doors: cuts += [d - DOOR / 2, d + DOOR / 2]
    cuts.append(L.length)
    return unary_union([substring(L, cuts[i], cuts[i + 1]).buffer(T / 2, cap_style=2) for i in range(0, len(cuts), 2) if cuts[i + 1] > cuts[i]])
def arc_wall(a0, a1, r, door_deg=()):     # door positions given as angles
    L = LineString([P(a, r) for a in np.linspace(a0, a1, 64)])
    ds = [L.project(Point(P(a, r))) for a in door_deg]
    return wall_line(list(L.coords), ds)
def radial_wall(a, r0, r1, door_r=()):
    return wall_line([P(a, r0), P(a, r1)], [d - r0 for d in door_r])
def ring_wall(r, door_deg, w=DOOR):
    g = Point(C).buffer(r + T / 2, 256).difference(Point(C).buffer(r - T / 2, 256))
    for a in door_deg: g = g.difference(LineString([P(a, r - 30), P(a, r + 30)]).buffer(w / 2, cap_style=2))
    return g
rot = lambda g, k: affinity.rotate(g, 90 * k, origin=C)

# ---- one wing (top-left quadrant), measured in polar
CAB = [192.5, 205.3, 218.2, 231.0, 243.8, 256.5]          # cabin dividers (deg)
chord = lambda a0, a1, r0, r1: Polygon([P(a0, r0), P(a0, r1), P(a1, r1), P(a1, r0)])
wing_floor = [sector(188, 262, 465, 600),                     # end rooms + inner hall + rooms A (one band)
              sector(192, 258, 600, 825),                     # ring corridor (islands sit inside it)
              ] + [Polygon([P(a0, 825), P(a0, 948), P(a1, 948), P(a1, 825)]) for a0, a1 in zip(CAB[:-1], CAB[1:])]   # five flat-faced cabins
wing_walls = [radial_wall(205, 465, 600, [492]), radial_wall(245, 465, 600, [492]),            # end rooms / inner hall
              arc_wall(205, 245, 520, [215, 235]),                                               # inner hall / rooms A
              radial_wall(207, 520, 600), radial_wall(223, 520, 600), radial_wall(227, 520, 600), radial_wall(243, 520, 600),
              arc_wall(188, 262, 600, [196.5, 215, 235, 253.5]),                                 # into the ring corridor
              arc_wall(192.5, 256.5, 825, [198.9, 211.6, 224.5, 237.4, 250.1])]                  # cabins
for a in CAB[1:-1]: wing_walls.append(radial_wall(a, 825, 948))                                 # cabin dividers
islands = [chord(197, 213, 690, 775), chord(217, 233, 690, 775), chord(237, 253, 690, 775)]   # flat island rooms
for g in islands: wing_walls.append(g.exterior.buffer(T / 2))
for a0, a1 in ((197, 213), (217, 233), (237, 253)):        # island doors on the inner face
    m = (a0 + a1) / 2; wing_walls[-3 + [(197, 213), (217, 233), (237, 253)].index((a0, a1))] = chord(a0, a1, 690, 775).exterior.buffer(T / 2).difference(Point(P(m, 690 * math.cos(math.radians(8)))).buffer(DOOR / 2))
# doors from the end rooms into the spokes
wing_walls += [radial_wall(188, 465, 600, [532]), radial_wall(262, 465, 600, [532])]

# ---- spokes (measured on the W and N spokes): entry r 215-285, stair corridor 285-440, cross room 440-585, end room 585-685
def spoke(a, end_room=True):
    r1 = 685 if end_room else 593
    u = (math.cos(math.radians(a)), math.sin(math.radians(a))); v = (-u[1], u[0])
    def rect(r0, r1, h=70):
        return Polygon([(C[0] + r * u[0] + s * v[0], C[1] + r * u[1] + s * v[1]) for r, s in ((r0, -h), (r1, -h), (r1, h), (r0, h))])
    def across(r, door=True):
        p0 = (C[0] + r * u[0] - 70 * v[0], C[1] + r * u[1] - 70 * v[1]); p1 = (C[0] + r * u[0] + 70 * v[0], C[1] + r * u[1] + 70 * v[1])
        return wall_line([p0, p1], [70] if door else [])
    fl = [rect(200, r1)]; wl = [across(440), across(585)] if end_room else [across(440)]
    if end_room: fl.append(Point(C[0] + 712 * u[0], C[1] + 712 * u[1]).buffer(32, 64)); wl.append(across(685))
    return fl, wl
spokes = [spoke(180), spoke(0), spoke(90), spoke(270, end_room=False)]

hub = [Point(C).buffer(285, 256)]
hub_walls = [ring_wall(285, [0, 90, 180, 270], 130), ring_wall(215, [0, 90, 180, 270]), ring_wall(100, [45, 135, 225, 315])]

floor = unary_union([rot(g, k) for k in range(4) for g in wing_floor] + [g for f, _ in spokes for g in f] + hub)
inner = [rot(w, k) for k in range(4) for w in wing_walls] + [w for _, ws in spokes for w in ws] + hub_walls
walls = floor.buffer(T / 2, join_style=2).difference(floor.buffer(-T / 2, join_style=2))
walls = unary_union([walls, unary_union(inner).intersection(floor.buffer(T / 2, join_style=2))])
walls = unary_union([p for p in getattr(walls, "geoms", [walls]) if p.area > 400])

src = cv2.imread(os.path.join(HERE, "..", "map_x4.jpg")); H, W = src.shape[:2]
mask = np.zeros((H, W), np.uint8)
for p in getattr(walls, "geoms", [walls]):
    m1 = np.zeros_like(mask); cv2.fillPoly(m1, [np.array(p.exterior.coords, np.int32)], 255)
    for r in p.interiors: cv2.fillPoly(m1, [np.array(r.coords, np.int32)], 0)
    mask |= m1
cs, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
plan = np.zeros_like(src); ov = (src * 0.45).astype(np.uint8)
for im in (plan, ov): cv2.drawContours(im, cs, -1, (255, 255, 255), 3, cv2.LINE_AA)
cv2.imwrite(os.path.join(HERE, "plan.png"), plan)
cv2.imwrite(os.path.join(HERE, "plan_on_map.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 86])
json.dump({"units": "map_x4 px", "thickness": T, "door": DOOR, "centre": C, "floor": mapping(floor), "walls": mapping(walls)},
          open(os.path.join(HERE, "plan.json"), "w"))
print("ok")
