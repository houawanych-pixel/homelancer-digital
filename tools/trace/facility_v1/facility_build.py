#!/usr/bin/env python3
"""Planet facility builder v1 (owner, Nov 20 2026: "ready to make planetary maps ... randomizer using the library,
mech rooms and smaller pilot rooms too, 3 to 4 key method"; "they're underground, so use the library conditions, use
doors, no overlaps, any overlap is a clean cut or merge, same three missions"; 3 floors).

An Armored Core style facility under a planet's base, in the SHIP construction (the station v2 method, the same deck
files, the same boarding engine). Underground there is no model silhouette: each floor is GROWN by a randomizer.

  core       the same four lift shafts as every station deck (station_build.LIFTS), ring A round them, the floor's
             hub room in the middle and the cross out of it (one elevator runs through all three floors)
  tunnels    a grid of junctions 36 m apart round the core; a random tree joins them (every junction reached), and a
             few extra links make loops (more than one way round); some junctions are left out, so every floor
             has its own ragged shape
  caverns    off some dead-end tunnels a natural cave: an irregular rock chamber (a mech room) with a flat face where
             its tunnel comes in
  entry      ENTRY LEVEL only: the SURFACE LIFT (you come down from the base: the entry) and the EXIT SHAFT (the way out)
             on dead ends far apart
  rooms      the owner's room library (room_library/kit.json) along every straight tunnel, both sides, each its own
             shape (nothing mirrored); back rooms behind them and doors between rooms that sit wall to wall - the
             station v2 code as it is: every room is the biggest clean box that fits clear of every tunnel, room and
             cave (an overlap is cut off clean), red mech rooms deep, blue pilot rooms smaller
  floors     ENTRY LEVEL (main, the objective in its Command Center), SUB-LEVEL 1 (lower), SUB-LEVEL 2 (lower2)

usage: python3 -I tools/trace/facility_v1/facility_build.py <fid> <difficulty 1-4>
       writes tools/trace/fleet_<fid>/ like station_build.py, then: python3 -I tools/trace/facility_v1/finish.py <fid> <d>"""
import json, math, os, random, sys, hashlib, tempfile, shutil
import cv2, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); TR = os.path.join(HERE, "..")
sys.path.insert(0, TR); sys.path.insert(0, os.path.join(TR, "station_v2"))
import planlib
from planlib import hall, Ship, run, DOOR
import station_build as SB
from station_build import C, NPX, MW, A_HUB, A_A, LIFTS, octo, cut_of, pick, MECH_WORDS, PILOT_WORDS
from shapely.geometry import Polygon, box, Point, shape, mapping, LineString
from shapely import affinity
from shapely.ops import unary_union

G = 360.0                                     # junction spacing (px; 10 px = 1 m): the cross ends at 360 like a station
FLOORS = [("lower2", "SUB-LEVEL 2", -2), ("lower", "SUB-LEVEL 1", -1), ("main", "ENTRY LEVEL", 0)]
ROLE = {"ENTRY LEVEL": dict(hub="Command Center", word="Operations"),
        "SUB-LEVEL 1": dict(hub="Pump Station", word="Works"),
        "SUB-LEVEL 2": dict(hub="Reactor Hall", word="Deep")}
SIZE = {1: 2, 2: 2, 3: 2, 4: 2, 5: 2}               # junctions out from the core (a bigger grid was too heavy: 650 rooms a floor)
KEEP = {1: 0.62, 2: 0.72, 3: 0.82, 4: 0.92, 5: 0.98}   # (5: the enemy factions' own facilities, the fullest)   # share of junctions kept: the harder, the more of the grid is dug out
LOOPS = 0.22                                  # extra links on top of the tree (other ways round)
CAVES = {1: 2, 2: 2, 3: 3, 4: 3, 5: 3}              # caverns per floor (where dead ends allow)

def cavern(cx, cy, r, d, rng):
    """An irregular rock chamber round (cx, cy), radius about r, cut flat across its mouth (facing direction -d), so
    the tunnel meets a straight face that is also its box's edge."""
    pts = []
    n = 22
    rad = [r * rng.uniform(0.6, 1.3) for _ in range(n)]
    rad = [(rad[i - 1] + 3 * rad[i] + rad[(i + 1) % n]) / 5 for i in range(n)]   # (a little smoothed: a cave, not a star)
    for i in range(n):
        a = 2 * math.pi * i / n
        pts.append((cx + rad[i] * math.cos(a), cy + rad[i] * math.sin(a)))
    g = Polygon(pts).buffer(0)
    mouth = r * 0.72   # the flat face: a half-plane cut at the mouth
    if d[0] == 0:
        y = cy - d[1] * mouth
        g = g.intersection(box(cx - 3 * r, min(y, cy + d[1] * 3 * r), cx + 3 * r, max(y, cy + d[1] * 3 * r)))
    else:
        x = cx - d[0] * mouth
        g = g.intersection(box(min(x, cx + d[0] * 3 * r), cy - 3 * r, max(x, cx + d[0] * 3 * r), cy + 3 * r))
    return Polygon(g.exterior) if g.geom_type == "Polygon" else max(g.geoms, key=lambda q: q.area)

def build_floor(fid, d, role, here, src, entry_floor):
    planlib.DIAG.clear()
    seed = int(hashlib.md5(("%s|%s" % (fid, role)).encode()).hexdigest(), 16) % (2 ** 31)
    rng = random.Random(seed)
    HULL = box(120, 120, NPX - 120, NPX - 120)          # (underground: the rock is everywhere; the canvas is the limit)
    R, HALLS, DOORS, SEGS, NAMES = {}, [], [], [], ROLE[role]
    N = SIZE[d]
    def node(x, y, w=MW):
        g = box(x - w / 2, y - w / 2, x + w / 2, y + w / 2); HALLS.append(g); return g
    def seg(a, b):
        HALLS.append(hall(a, b, w=MW))
        SEGS.append((min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1]), MW))
    P = lambda ij: (C + ij[0] * G, C + ij[1] * G)
    # ---- the core: ring A round the lifts, the hub, the cross out to the first junctions
    V = [(C + A_A - cut_of(A_A, A_A), C - A_A), (C + A_A, C - A_A + cut_of(A_A, A_A)), (C + A_A, C + A_A - cut_of(A_A, A_A)), (C + A_A - cut_of(A_A, A_A), C + A_A),
         (C - A_A + cut_of(A_A, A_A), C + A_A), (C - A_A, C + A_A - cut_of(A_A, A_A)), (C - A_A, C - A_A + cut_of(A_A, A_A)), (C - A_A + cut_of(A_A, A_A), C - A_A)]
    for v in V: node(*v)
    for i in range(8):
        a, b = V[i], V[(i + 1) % 8]
        if abs(a[0] - b[0]) < 1 or abs(a[1] - b[1]) < 1: seg(a, b)
        else: HALLS.append(planlib.dhall(a, b, w=MW))
    hubname = NAMES["hub"]
    R[hubname] = octo(C, C, A_HUB, A_HUB, A_HUB * 0.414)
    # ---- the junction grid and its random tree (+ loops)
    cells = [(i, j) for i in range(-N, N + 1) for j in range(-N, N + 1) if max(abs(i), abs(j)) >= 1]
    must = {(0, -1), (0, 1), (1, 0), (-1, 0)}
    kept = {c for c in cells if c in must or rng.random() < KEEP[d]}
    nb = lambda c: [(c[0] + 1, c[1]), (c[0] - 1, c[1]), (c[0], c[1] + 1), (c[0], c[1] - 1)]
    edges, seen = set(), set(must)
    front = list(must)
    while front:   # a random tree from the cross outward (every kept junction it can reach)
        c = front.pop(rng.randrange(len(front)))
        opts = [q for q in nb(c) if q in kept and q not in seen and max(abs(q[0]), abs(q[1])) >= 1]
        rng.shuffle(opts)
        for q in opts[:rng.choice((1, 2, 2, 3))]:
            seen.add(q); edges.add(tuple(sorted((c, q)))); front.append(q)
        if opts[rng.choice((1, 2, 2, 3)):] : front.append(c)   # (it can branch again later)
    kept = seen
    for c in sorted(kept):   # loops
        for q in nb(c):
            e = tuple(sorted((c, q)))
            if q in kept and e not in edges and rng.random() < LOOPS: edges.add(e)
    for dx, dy in ((0, -1), (0, 1), (1, 0), (-1, 0)):
        a = (C + dx * A_HUB, C + dy * A_HUB); b = P((dx, dy))
        seg(a, b); DOORS.append((a[0], a[1], "h" if dx == 0 else "v"))
    deg = {c: 0 for c in kept}
    for a, b in edges:
        deg[a] += 1; deg[b] += 1
    for c in kept: node(*P(c))
    for a, b in sorted(edges): seg(P(a), P(b))
    # ---- dead ends (out at the edge): the entry and the way out, then caverns
    ends = sorted([c for c in kept if deg[c] + (1 if c in must else 0) == 1 and max(abs(c[0]), abs(c[1])) >= 2], key=lambda c: -(abs(c[0]) + abs(c[1])))
    rng.shuffle(ends)
    def outward(c):
        free = [q for q in nb(c) if q not in kept and max(abs(q[0]), abs(q[1])) > max(abs(c[0]), abs(c[1]))]
        if not free: free = [q for q in nb(c) if q not in kept and q not in must and max(abs(q[0]), abs(q[1])) >= 1]
        if not free: return None
        q = free[0]
        return (q[0] - c[0], q[1] - c[1])
    taken, PADS = [], []
    special = []
    if entry_floor:
        if len(ends) < 2:   # (always two far dead ends on the entry level: grow two spurs out of the edge)
            ends = sorted([c for c in kept if max(abs(c[0]), abs(c[1])) == N], key=lambda c: rng.random())
        ends = [c for c in ends if outward(c)] or ends
        a = ends[0]
        far = [c for c in kept if c != a and outward(c) and max(abs(c[0]), abs(c[1])) >= 2]   # (the way out: always, on the far side)
        b = max(far, key=lambda c: abs(c[0] - a[0]) + abs(c[1] - a[1]), default=None)
        special = [(a, "Surface Lift"), (b, "Exit Shaft")] if b else [(a, "Surface Lift")]
    for c, nm in special:
        u = outward(c)
        if not u: continue
        hw = 62.0
        p = P(c); cx, cy = p[0] + u[0] * (G * 0.55 + hw), p[1] + u[1] * (G * 0.55 + hw)
        e = (cx - u[0] * hw, cy - u[1] * hw)
        g = octo(cx, cy, hw, hw, hw * 0.3)
        if not HULL.contains(g) or any(box(*g.bounds).buffer(20).intersects(h) for h in HALLS): continue
        seg(p, e); R[nm] = g; DOORS.append((round(e[0], 1), round(e[1], 1), "h" if u[0] == 0 else "v")); PADS.append(nm); taken.append(c)
    n_cave = 0
    for c in ends:
        if n_cave >= CAVES[d] or c in taken: continue
        u = outward(c)
        if not u: continue
        r = rng.uniform(95, 140)
        p = P(c); cx, cy = p[0] + u[0] * (G * 0.45 + r * 0.72), p[1] + u[1] * (G * 0.45 + r * 0.72)
        g = cavern(cx, cy, r, u, rng)
        e = (cx - u[0] * r * 0.72, cy - u[1] * r * 0.72)
        bx = box(*g.bounds)
        if not HULL.contains(bx) or any(bx.buffer(20).intersects(h) for h in HALLS): continue
        if any(bx.buffer(40).intersects(box(*q.bounds)) for q in R.values()): continue
        n_cave += 1
        nm = "Cavern %d" % n_cave
        seg(p, e); R[nm] = g; DOORS.append((round(e[0], 1), round(e[1], 1), "h" if u[0] == 0 else "v")); taken.append(c)
    for nm, (bx_, d_) in LIFTS.items(): R[nm] = box(*bx_); DOORS.append(d_)
    # ---- the small rooms: the station v2 placement (library shapes along every straight tunnel, back rooms, room to
    # room doors), both sides, nothing mirrored
    occ = list(HALLS) + [box(*b.bounds).buffer(4) for b in R.values()] + [box(*q.bounds).buffer(3) for q in planlib.DIAG]
    def blocked(g):
        if not HULL.contains(g): return True
        gg = g.buffer(-2)
        return any(gg.intersects(o) for o in occ if o.bounds[0] <= gg.bounds[2] and o.bounds[2] >= gg.bounds[0] and o.bounds[1] <= gg.bounds[3] and o.bounds[3] >= gg.bounds[1])
    def sector(x, y):
        a = math.degrees(math.atan2(-(y - C), x - C)) % 360
        return NAMES["word"] + (" North" if 45 <= a < 135 else " South" if 225 <= a < 315 else " East" if x > C else " West")
    n_room, KIND, used = {}, {}, {}
    BXS, OCC_I, DOOR_AT = {}, {}, {}
    def place(bx, door, mech, sd, shape_=None):
        x0, y0, x1, y1 = bx.bounds; cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        dw = DOOR + 12
        def shaped(g0):
            g = g0
            for dd in range(10, 200, 8):
                strip = (box(door[0] - dw / 2, door[1] - dd, door[0] + dw / 2, door[1] + dd) if door[2] == "h" else box(door[0] - dd, door[1] - dw / 2, door[0] + dd, door[1] + dw / 2)).intersection(bx)
                g = unary_union([g0, strip]).intersection(bx).buffer(0)
                if g.geom_type == "Polygon" and strip.intersection(g0).area > dw * 12: break
            g = g.buffer(-5, join_style=2).buffer(5, join_style=2).intersection(bx).buffer(0)
            if g.geom_type != "Polygon": g = max(g.geoms, key=lambda q: q.area)
            return Polygon(g.exterior)
        for i_ in range(12):
            g0, kid = pick(x1 - x0, y1 - y0, sd + i_ * 7919, mech) if i_ < 11 else (box(-(x1 - x0) / 2, -(y1 - y0) / 2, (x1 - x0) / 2, (y1 - y0) / 2), None)
            g = shaped(affinity.translate(g0, cx, cy))
            if g.centroid.within(g.buffer(-16)) and g.representative_point().within(g.buffer(-12)) and g.area > 0.5 * bx.area: break
        sec = sector(cx, cy); words = MECH_WORDS if mech else PILOT_WORDS; wd = words[sd % len(words)]
        n_room[(sec, wd)] = n_room.get((sec, wd), 0) + 1
        nm = "%s %s %d" % (sec, wd, n_room[(sec, wd)])
        R[nm] = g; KIND[nm] = "mech" if mech else "pilot"; occ.append(bx.buffer(4)); DOORS.append((round(door[0], 1), round(door[1], 1), door[2]))
        BXS[nm] = bx; OCC_I[nm] = len(occ) - 1; DOOR_AT[nm] = door
        if kid: used[kid] = used.get(kid, 0) + 1
        return nm
    def rnd(*k):
        return int(hashlib.md5(("%s|%s|" % (fid, role) + "|".join(str(x) for x in k)).encode()).hexdigest(), 16)
    for si, (x0, y0, x1, y1, w) in enumerate(SEGS):
        horiz = abs(y1 - y0) < 1
        if not horiz and abs(x1 - x0) > 1: continue
        for side in (-1, 1):
            u0, u1 = (min(x0, x1), max(x0, x1)) if horiz else (min(y0, y1), max(y0, y1))
            u = u0 + 8; k = 0
            while u < u1:
                mid = ((u + 30) - C, (y0 if horiz else x0) - C)
                deep = max(abs(mid[0]), abs(mid[1])) > A_A + 120
                sizes = [(88, 96), (62, 70), (50, 58)] if deep and rnd(si, side, k, "m") % 100 < 55 else [(62, 70), (50, 58)]
                done = False
                for depth, length in sizes:
                    if u + length > u1 - 4: continue
                    if horiz:
                        e = y0 + side * w / 2; bx = box(u, min(e, e + side * depth), u + length, max(e, e + side * depth)); door = (u + length / 2, e, "h")
                    else:
                        e = x0 + side * w / 2; bx = box(min(e, e + side * depth), u, max(e, e + side * depth), u + length); door = (e, u + length / 2, "v")
                    if blocked(bx): continue
                    place(bx, door, depth >= 88, rnd(si, side, k) % 9973)
                    u += length + 8; k += 1; done = True; break
                if not done: u += 10
    def clear_of(g, skip):
        if not HULL.contains(g): return False
        gg = g.buffer(-2); b = gg.bounds
        for i, o in enumerate(occ):
            if i in skip: continue
            ob = o.bounds
            if ob[0] <= b[2] and ob[2] >= b[0] and ob[1] <= b[3] and ob[3] >= b[1] and gg.intersects(o): return False
        return True
    def strip_in(nm, door):
        bx = BXS[nm]; g0 = R[nm]; dw = DOOR + 12
        for dd in range(10, 200, 8):
            st = (box(door[0] - dw / 2, door[1] - dd, door[0] + dw / 2, door[1] + dd) if door[2] == "h" else box(door[0] - dd, door[1] - dw / 2, door[0] + dd, door[1] + dw / 2)).intersection(bx)
            g = unary_union([g0, st]).intersection(bx).buffer(0)
            if g.geom_type == "Polygon" and st.intersection(g0).area > dw * 12: break
        if g.geom_type != "Polygon": g = max(g.geoms, key=lambda q: q.area)
        R[nm] = Polygon(g.exterior)
    queue = [(k, 0) for k in sorted(KIND, key=lambda k_: rnd(k_, "order"))]
    n_back = 0
    while queue:
        nm, lvl = queue.pop(0)
        if rnd(nm, "go") % 100 >= (92, 70, 45, 25)[lvl]: continue
        want = 2 if lvl == 0 and rnd(nm, "two") % 100 < 55 else 1
        x0, y0, x1, y1 = BXS[nm].bounds; dr = DOOR_AT[nm]
        dside = ("N" if abs(dr[1] - y0) < 1 else "S") if dr[2] == "h" else ("W" if abs(dr[0] - x0) < 1 else "E")
        sides = sorted([q for q in "NSEW" if q != dside], key=lambda q: rnd(nm, q) % 97)
        mechp = KIND[nm] == "mech"
        for sd in sides:
            if want <= 0: break
            made = None
            L = (x1 - x0) if sd in "NS" else (y1 - y0)
            for depth in ([88, 70, 62, 50] if mechp else [62, 50, 44]):
                for shrink, shift in ((0.0, 0), (0.2, 0), (0.2, -1), (0.2, 1), (0.4, 0), (0.4, -1), (0.4, 1)):
                    a_, b_ = ((x0, x1) if sd in "NS" else (y0, y1))
                    a_, b_ = a_ + L * shrink / 2 + shift * L * shrink / 2, b_ - L * shrink / 2 + shift * L * shrink / 2
                    if b_ - a_ < DOOR + 24: continue
                    nb_ = {"N": box(a_, y0 - depth, b_, y0), "S": box(a_, y1, b_, y1 + depth), "W": box(x0 - depth, a_, x0, b_), "E": box(x1, a_, x1 + depth, b_)}[sd]
                    if not clear_of(nb_, {OCC_I[nm]}): continue
                    door = ((a_ + b_) / 2, y0 if sd == "N" else y1, "h") if sd in "NS" else (x0 if sd == "W" else x1, (a_ + b_) / 2, "v")
                    made = (nb_, door, depth); break
                if made: break
            if not made: continue
            nb_, door, depth = made
            k1 = place(nb_, door, mechp and depth >= 70, rnd(nm, sd, "shape") % 9973)
            strip_in(nm, door)
            n_back += 1; want -= 1
            if lvl < 3: queue.append((k1, lvl + 1))
    n_link = 0
    ks = list(KIND)
    for i1, ka in enumerate(ks):
        for kb in ks[i1 + 1:]:
            A, B = BXS[ka].bounds, BXS[kb].bounds
            door = None
            for (e1, e2, hz) in ((A[3], B[1], True), (A[1], B[3], True), (A[2], B[0], False), (A[0], B[2], False)):
                gap = abs(e2 - e1)
                if gap > 14 or (gap > 0.5 and ((e2 < e1) if (e1 in (A[3], A[2])) else (e2 > e1))): continue
                lo, hi = (max(A[0], B[0]), min(A[2], B[2])) if hz else (max(A[1], B[1]), min(A[3], B[3]))
                if hi - lo >= DOOR + 28: door = ((lo + hi) / 2, e2, "h") if hz else (e2, (lo + hi) / 2, "v"); span = (e1, e2, hz); break
            if not door or rnd(ka, kb, "door") % 100 >= 50: continue
            if any(abs(dd[0] - door[0]) < DOOR + 8 and abs(dd[1] - door[1]) < DOOR + 8 for dd in DOORS): continue
            e1, e2, hz = span
            if abs(e2 - e1) > 0.5:
                dw = DOOR + 12
                con = box(door[0] - dw / 2, min(e1, e2), door[0] + dw / 2, max(e1, e2)) if hz else box(min(e1, e2), door[1] - dw / 2, max(e1, e2), door[1] + dw / 2)
                nbx = box(*unary_union([BXS[ka], con]).bounds)
                if not clear_of(nbx, {OCC_I[ka], OCC_I[kb]}): continue
                R[ka] = Polygon(unary_union([R[ka], con.buffer(0.01)]).buffer(0).exterior) if unary_union([R[ka], con]).geom_type == "Polygon" else R[ka]
                BXS[ka] = nbx; occ[OCC_I[ka]] = nbx.buffer(4)
            strip_in(ka, door); strip_in(kb, door)
            if R[ka].distance(Point(door[0], door[1])) > 1.5 or R[kb].distance(Point(door[0], door[1])) > 1.5: continue
            DOORS.append((round(door[0], 1), round(door[1], 1), door[2])); n_link += 1
    kinds = {}
    for k in R:
        if k.startswith("Lift"): kinds[k] = "lift"
        elif k in KIND: kinds[k] = KIND[k]
        else: kinds[k] = "mech"   # (the hub, the caverns, the surface lift and the exit shaft)
    S = Ship(fid, here, src, C, R, HALLS, DOORS, start=(C, C + A_A), center_y=C)
    info = {"junctions": len(kept), "links": len(edges), "pads": PADS, "caves": n_cave, "rooms": len(R), "kit_shapes": len(used), "back": n_back, "doors": n_link}
    return S, kinds, hubname, info

def silhouette(P):   # the floor's own outline: everything dug out, with a rim of rock
    g = unary_union([shape(v) for v in P["rooms"].values()] + [shape(h) for h in P["halls"]] + [shape(h) for h in P.get("diag", [])]).buffer(18, join_style=2)
    return g

def draw(path, P, kinds, title):
    im = np.zeros((NPX, NPX, 3), np.uint8); im[:] = (30, 22, 18)
    rock = silhouette(P)
    for q in getattr(rock, "geoms", [rock]): cv2.fillPoly(im, [np.array(q.exterior.coords, np.int32)], (60, 48, 40))
    for h in P["halls"] + P.get("diag", []):
        for q in getattr(shape(h), "geoms", [shape(h)]): cv2.fillPoly(im, [np.array(q.exterior.coords, np.int32)], (60, 50, 215))
    for k, gj in P["rooms"].items():
        g = shape(gj); col = {"mech": (40, 30, 150), "pilot": (200, 110, 30), "lift": (0, 210, 240)}[kinds[k]]
        cv2.fillPoly(im, [np.array(g.exterior.coords, np.int32)], col)
    im[planlib.raster(shape(P["walls"]), (NPX, NPX)) > 0] = (255, 255, 255)
    for q in getattr(rock, "geoms", [rock]): cv2.polylines(im, [np.array(q.exterior.coords, np.int32)], True, (120, 170, 200), 4, cv2.LINE_AA)
    for k, gj in P["rooms"].items():
        if not k.split()[-1].isdigit() or k.startswith(("Cavern", "Lift")):
            c = shape(gj).representative_point(); t = k.upper()
            (tw, th), _ = cv2.getTextSize(t, 0, 0.75, 2)
            cv2.putText(im, t, (int(c.x - tw / 2), int(c.y + th / 2)), 0, 0.75, (255, 255, 255), 2, cv2.LINE_AA)
    cv2.putText(im, title, (40, 90), 0, 2.2, (255, 255, 255), 5, cv2.LINE_AA)
    x0, y0, x1, y1 = [int(v) for v in rock.bounds]
    im = im[max(0, y0 - 130):y1 + 60, max(0, x0 - 60):x1 + 60]
    cv2.imwrite(path, im, [cv2.IMWRITE_JPEG_QUALITY, 85])

def main():
    fid, d = sys.argv[1], int(sys.argv[2])
    name = sys.argv[3] if len(sys.argv) > 3 else "Facility"
    root = os.path.join(TR, "fleet_" + fid); eng = os.path.join(root, "eng"); dk = os.path.join(root, "decks")
    for p in (root, eng, dk): os.makedirs(p, exist_ok=True)
    src = np.zeros((NPX, NPX, 3), np.uint8); src[:] = (30, 22, 18)
    cv2.imwrite(os.path.join(root, "source.jpg"), src, [cv2.IMWRITE_JPEG_QUALITY, 90])
    bad_all = {}
    for dname, role, lvl in FLOORS:
        tmp = tempfile.mkdtemp()
        S, kinds, hub, info = build_floor(fid, d, role, tmp if dname != "main" else eng, os.path.join(root, "source.jpg"), dname == "main")
        bad = run(S); bad_all[dname] = bad
        P = json.load(open(os.path.join(S.here, "plan.json")))
        draw(os.path.join(dk, "%s_plan.jpg" % dname), P, kinds, "%s  -  %s" % (name.upper(), role))
        rock = silhouette(P)
        if dname == "main":
            # the map picture behind the entry level: its rock outline
            im = np.zeros((NPX, NPX, 3), np.uint8); im[:] = (30, 22, 18)
            for q in getattr(rock, "geoms", [rock]):
                cv2.fillPoly(im, [np.array(q.exterior.coords, np.int32)], (70, 55, 45)); cv2.polylines(im, [np.array(q.exterior.coords, np.int32)], True, (150, 120, 90), 6, cv2.LINE_AA)
            cv2.imwrite(os.path.join(root, "source.jpg"), im, [cv2.IMWRITE_JPEG_QUALITY, 90])
            json.dump({"hull": mapping(rock), "centre": [C, C], "model": "", "meta": {"facility": True, "difficulty": d}}, open(os.path.join(root, "hull.json"), "w"))
            entry = "Surface Lift" if "Surface Lift" in P["rooms"] else hub
            ov = {"entry": entry, "C": hub, "kinds": kinds}
            if "Exit Shaft" in P["rooms"]: ov["exit"] = "Exit Shaft"   # (the way out: fleet_formula keeps it)
            json.dump(ov, open(os.path.join(eng, "overrides.json"), "w"), indent=1)
            pt = lambda k: [int(shape(P["rooms"][k]).representative_point().x), int(shape(P["rooms"][k]).representative_point().y)]
            Gp = {"entry": {"room": entry, "at": pt(entry)}, "locks": [], "guards": [], "wreck": [], "patrols": [], "targets": {},
                  "lifts": [{"room": k, "at": pt(k)} for k in LIFTS], "room_guards": {k: (2 if kinds[k] == "mech" else 0) for k in kinds if kinds[k] != "lift"},
                  "note": "%s ENTRY LEVEL (facility_v1/facility_build.py, difficulty %d)" % (name, d)}
            json.dump(Gp, open(os.path.join(eng, "gameplay.json"), "w"), indent=1)
            json.dump(Gp, open(os.path.join(eng, "gameplay_v1.json"), "w"), indent=1)
        else:
            P["deck"] = dname; P["level"] = lvl; P["hull"] = mapping(rock if rock.geom_type == "Polygon" else rock.convex_hull)
            P["lifts"] = [[(b[0] + b[2]) / 2, (b[1] + b[3]) / 2] for b, _ in LIFTS.values()]
            P["kinds"] = kinds
            json.dump(P, open(os.path.join(eng, "deck_%s.json" % dname), "w"))
        shutil.rmtree(tmp, ignore_errors=True)
        print("%-7s %-12s junctions %d links %d pads %s caves %d rooms %d (back %d, room doors %d, kit shapes %d) unreachable %s" % (
            dname, role, info["junctions"], info["links"], info["pads"], info["caves"], info["rooms"], info["back"], info["doors"], info["kit_shapes"], bad))
    sys.exit(1 if any(bad_all.values()) else 0)

if __name__ == "__main__":
    main()
