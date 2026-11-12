#!/usr/bin/env python3
"""Carrick Station, Republic Fleet main floor (SWTOR; identified from the owner's in-game screenshots, 12 Nov 2026): four wings around a central hub, joined by four spokes.
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

# ---- one wing (top-left quadrant), measured zoomed in on the polar unwrap (0.05 deg x 0.5 px), symmetric about 225 deg
M = lambda a: 450 - a                                        # mirror an angle about 225
chord = lambda a0, a1, r0, r1: Polygon([P(a0, r0), P(a0, r1), P(a1, r1), P(a1, r0)])
TEETH = [(194.5, 204.5), (206.8, 217.3), (219.6, 230.4), (M(217.3), M(206.8)), (M(204.5), M(194.5))]   # cabins stick out as gear teeth, ~2.3 deg notches between
ISL = [(201.3, 213.4), (217.2, 232.8), (M(213.4), M(201.3))]  # island rooms in the ring corridor
AR = [(207.2, 223.8), (M(223.8), M(207.2))]                  # rooms A off the inner hall
wing_floor = [sector(187, 263, 465, 600),                     # end rooms + inner hall + rooms A
              sector(193.5, M(193.5), 600, 700),              # ring corridor, inner part
              sector(197.4, M(197.4), 700, 773),              # island row (islands sit inside it)
              sector(191, M(191), 773, 848)]                  # ring corridor, outer part
wing_floor += [chord(a0, a1, 846, 955) for a0, a1 in TEETH]                            # five flat-faced cabin teeth
wing_walls = [radial_wall(204.3, 465, 600, [495]), radial_wall(M(204.3), 465, 600, [495]),   # end rooms / inner hall
              radial_wall(187, 465, 600, [532]), radial_wall(263, 465, 600, [532]),          # end rooms / spokes
              arc_wall(187, 263, 600, [196, 215.5, 234.5, 254])]                             # into the ring corridor
for a0, a1 in AR:
    wing_walls += [arc_wall(a0, a1, 523, [(a0 + a1) / 2]), radial_wall(a0, 523, 600), radial_wall(a1, 523, 600)]   # door from the inner hall
for a0, a1 in ISL:
    m = (a0 + a1) / 2; g = chord(a0, a1, 700, 773)
    wing_walls.append(g.exterior.buffer(T / 2).difference(Point(P(m, 700 * math.cos(math.radians((a1 - a0) / 2)))).buffer(DOOR / 2)))
wing_walls.append(arc_wall(191, M(191), 848, [(x + y) / 2 for x, y in TEETH]))       # cabin doors

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

hub = [Point(C).buffer(290, 256).difference(unary_union([rot(sector(217.5, 232.5, 262, 320), k) for k in range(4)]))]   # hub with four notches (gear look)
hub_walls = [ring_wall(290, [0, 90, 180, 270], 130), ring_wall(215, [0, 90, 180, 270]), ring_wall(100, [45, 135, 225, 315])]

# names and level changes from the in-game shots (yellow, not walls)
def stair(a):
    u = (math.cos(math.radians(a)), math.sin(math.radians(a))); v = (-u[1], u[0])
    return Polygon([(C[0] + r * u[0] + s * v[0], C[1] + r * u[1] + s * v[1]) for r, s in ((295, -60), (430, -60), (430, 60), (295, 60))])
FEATURES = [(stair(a), 'stairs') for a in (0, 90, 180, 270)] + [(Point(C).buffer(100, 128), 'cantina + VIP lifts')] + \
           [(Point(P(a, 712)).buffer(34, 64), 'lift') for a in (0, 90, 180)]
LABELS = [(P(225, 700), 'CREW SKILLS'), (P(315, 700), 'GTN market'), (P(45, 700), 'SUPPLIES'), (P(135, 700), 'SW wing'),
          (P(180, 790), 'Tython / Ord Mantell'), (P(0, 790), 'missions'), (P(90, 790), 'Coruscant'), (P(270, 640), 'Cartel Bazaar'),
          (P(250, 180), 'hub concourse')]
floor = unary_union([rot(g, k) for k in range(4) for g in wing_floor] + [g for f, _ in spokes for g in f] + hub)
inner = [rot(w, k) for k in range(4) for w in wing_walls] + [w for _, ws in spokes for w in ws] + hub_walls
floor = floor.buffer(3, join_style=2).buffer(-3, join_style=2)   # close hairline gaps where arcs of different pieces meet (they made false walls)
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
for g, n in FEATURES:
    for im in (plan, ov): cv2.polylines(im, [np.array(g.exterior.coords, np.int32)], True, (60, 210, 255), 3, cv2.LINE_AA)
for (x, y), t in LABELS + [((g.centroid.x, g.centroid.y + 5), n) for g, n in FEATURES if n == 'stairs']:
    for im in (plan, ov):
        (w, h), _ = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)
        cv2.putText(im, t, (int(x - w / 2), int(y)), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (60, 210, 255), 2, cv2.LINE_AA)
cv2.imwrite(os.path.join(HERE, "plan.png"), plan)
cv2.imwrite(os.path.join(HERE, "plan_on_map.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 86])
json.dump({"name": "Carrick Station main floor", "features": [{"name": n, "shape": mapping(g)} for g, n in FEATURES], "units": "map_x4 px", "thickness": T, "door": DOOR, "centre": C, "floor": mapping(floor), "walls": mapping(walls)},
          open(os.path.join(HERE, "plan.json"), "w"))
print("ok")
