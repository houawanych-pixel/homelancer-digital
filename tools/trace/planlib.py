#!/usr/bin/env python3
"""Shared engineering-plan code for every fleet ship (proven on the Imperium Troop Transport, owner-approved
12 Nov 2026). A ship's eng/build_plan.py only holds its measurements (rooms R, hallways HALLS, doors DOORS) and
calls planlib.run(...). One wall thickness T, one door width DOOR, hallways = centre line + width."""
import json, os
import cv2, numpy as np
from shapely import affinity
from shapely.geometry import LineString, Point, Polygon, box, mapping
from shapely.ops import unary_union

PX_PER_M = 10.0
T, DOOR, CW = 4.0, 16.0, 20.0

def hall(*pts, w=CW):
    return LineString(pts).buffer(w / 2, cap_style=2, join_style=2)
def ellipse(cx, cy, rx, ry):
    return affinity.scale(Point(cx, cy).buffer(1.0, 64), rx, ry)
def circle(cx, cy, r):
    return Point(cx, cy).buffer(r, 64)
def mirror(ax):
    return lambda g: affinity.scale(g, -1, 1, origin=(ax, 0))

class Ship:
    def __init__(self, sid, here, src, ax, R, HALLS, DOORS, start, proposed=(), center_y=None):
        self.sid, self.here, self.src, self.AX = sid, here, src, ax
        self.R, self.HALLS, self.DOORS, self.START = R, HALLS, DOORS, start
        self.PROPOSED_DOORS = list(proposed)
        im = cv2.imread(src); self.H, self.W = im.shape[:2]
        self.center_y = center_y if center_y is not None else self.H / 2.0

def door_box(x, y, o, depth):
    return box(x - DOOR / 2, y - depth, x + DOOR / 2, y + depth) if o == "h" else box(x - depth, y - DOOR / 2, x + depth, y + DOOR / 2)

def build(S):
    floor = unary_union(list(S.R.values()) + S.HALLS + [door_box(x, y, o, T * 2.6) for x, y, o in S.DOORS]).buffer(0.5).buffer(-0.5)
    # every room outline is a wall; then cut one standard door at each door point
    # every room outline is a wall; the hallways are one network (their union), so halls meet with no wall between
    halls = unary_union(S.HALLS)
    rings = [g.exterior.buffer(T / 2, join_style=2) for g in S.R.values()]
    for p in getattr(halls, "geoms", [halls]):
        rings.append(p.exterior.buffer(T / 2, join_style=2))
        rings += [r.buffer(T / 2, join_style=2) for r in p.interiors]
    walls = unary_union(rings)
    cut = [door_box(x, y, o, T * 2.6) for x, y, o in S.DOORS]
    walls = walls.difference(unary_union(cut))
    walls = walls.intersection(floor.buffer(T / 2, join_style=2))
    walls = unary_union([p for p in getattr(walls, "geoms", [walls]) if p.area > 8])
    return floor, walls

def raster(g, shape):
    """fill a (multi)polygon with its holes cut out"""
    out = np.zeros(shape, np.uint8)
    for p in getattr(g, "geoms", [g]):
        m1 = np.zeros(shape, np.uint8)
        cv2.fillPoly(m1, [np.array(p.exterior.coords, np.int32)], 1)
        for r in p.interiors: cv2.fillPoly(m1, [np.array(r.coords, np.int32)], 0)
        out |= m1
    return out

def reach(S, floor, walls, start):
    """flood fill on a 1 px grid: every room centre must be reachable from start"""
    W, H = S.W, S.H
    m = np.zeros((H, W), np.uint8)
    m[raster(floor, (H, W)) > 0] = 1
    m[raster(walls, (H, W)) > 0] = 0
    n, lab = cv2.connectedComponents(m, connectivity=4)
    s = lab[int(start[1]), int(start[0])]
    out = {}
    for k, g in S.R.items():
        c = g.representative_point()
        out[k] = bool(lab[int(c.y), int(c.x)] == s and s != 0)
    return out

def draw(S, floor, walls, path_png, path_jpg):
    src = cv2.imread(S.src)
    plan = np.zeros_like(src); ov = (src * 0.4).astype(np.uint8)
    for p in getattr(walls, "geoms", [walls]):
        pts = np.array(p.exterior.coords, np.int32)
        for im in (plan, ov): cv2.fillPoly(im, [pts], (255, 255, 255))
        for r in p.interiors:
            for im, base in ((plan, None), (ov, src)):
                mk = np.zeros(im.shape[:2], np.uint8); cv2.fillPoly(mk, [np.array(r.coords, np.int32)], 1)
                im[mk > 0] = 0 if base is None else (base[mk > 0] * 0.4).astype(np.uint8)
    for x, y in S.PROPOSED_DOORS:
        for im in (plan, ov): cv2.circle(im, (int(x), int(y)), 14, (0, 200, 255), 2, cv2.LINE_AA)
    for k, g in S.R.items():
        c = g.representative_point(); t = k.upper()
        (w, h), _ = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, 0.32, 1)
        cv2.putText(plan, t, (int(c.x - w / 2), int(c.y + h / 2)), cv2.FONT_HERSHEY_SIMPLEX, 0.32, (255, 220, 120), 1, cv2.LINE_AA)
    cv2.imwrite(path_png, plan); cv2.imwrite(path_jpg, ov, [cv2.IMWRITE_JPEG_QUALITY, 88])


def run(S):
    floor, walls = build(S)
    rc = reach(S, floor, walls, S.START)
    bad = [k for k, v in rc.items() if not v]
    print(S.sid, "rooms", len(S.R), "doors", len(S.DOORS), "unreachable:", bad)
    draw(S, floor, walls, os.path.join(S.here, "plan.png"), os.path.join(S.here, "plan_on_map.jpg"))
    json.dump({"ship": S.sid, "units": "source px", "px_per_m": PX_PER_M, "thickness": T, "door": DOOR, "mirror_x": S.AX,
               "start": S.START, "rooms": {k: mapping(g) for k, g in S.R.items()}, "halls": [mapping(h) for h in S.HALLS],
               "center_y": S.center_y, "doors": S.DOORS, "proposed_doors": S.PROPOSED_DOORS, "floor": mapping(floor), "walls": mapping(walls)},
              open(os.path.join(S.here, "plan.json"), "w"))
    return bad
