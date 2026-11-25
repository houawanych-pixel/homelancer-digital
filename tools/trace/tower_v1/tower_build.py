#!/usr/bin/env python3
"""City tower builder v1 (owner, Nov 25 2026: "in my New Terra homeland there are cities ... 6 major towers, the
ground level, lots of floors, lots of elevators ... looking for someone in a certain room, a target ... once you get it,
you leave; you can leave differently, through any wall ... inside the buildings you're a pilot, it doesn't fit mechs or
spaceships"; answers: any mission can send you in, 8-10 floors).

A megatower's inside, floor by floor, in the SHIP construction (the facility v1 builder turned upward): the same deck
files, the same boarding engine.
  footprint  the tower's glass core as the hull of every floor (a rectangle with cut corners, from its style)
  core       the hub of each floor in the middle (lobby, sky lobby, offices, penthouse) with its ring and cross
  halls      a grid of junctions 36 m apart inside the footprint; a random tree joins them, a few loops; a tower is
             full (most junctions kept), but each floor drops its own few, so no two floors are alike
  lifts      like a real skyscraper: LOW (1-4), MID (4-7), HIGH (7-top) and an EXPRESS to the sky lobbies (1-4-7);
             the same shaft on every floor it serves; the floors 4 and 7 are the SKY LOBBIES where you change lifts
  rooms      the room library along every hall, back rooms, room-to-room doors (the facility code as it is)
  entry      GROUND FLOOR: the STREET LOBBY on the footprint's edge (the door in from the street)
  pilot only every room is a pilot room (no mech or ship fits inside a building)

usage: python3 -I tools/trace/tower_v1/tower_build.py <tid> <floors 8-10> <style cluster|slab|twin> [name]
       writes tools/trace/fleet_<tid>/ like the facility builder, then: python3 -I tools/trace/tower_v1/tower_finish.py <tid>"""
import json, math, os, random, sys, hashlib, tempfile, shutil
import cv2, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); TR = os.path.join(HERE, "..")
sys.path.insert(0, TR); sys.path.insert(0, os.path.join(TR, "station_v2")); sys.path.insert(0, os.path.join(TR, "facility_v1"))
import planlib
from planlib import hall, Ship, run, DOOR
import station_build as SB
from station_build import C, NPX, MW, PW, A_HUB, A_A, octo, cut_of, pick, MECH_WORDS, PILOT_WORDS
MW = PW + 6   # (owner: inside a building you're a pilot: the halls are pilot walkways, 2.6 m, not mech lanes)
from shapely.geometry import Polygon, box, Point, shape, mapping, LineString
from shapely import affinity
from shapely.ops import unary_union

G = 360.0                                     # junction spacing (px; 10 px = 1 m): the cross ends at 360 like a station
DECK_KEYS = ["main", "upper", "upper2", "upper3", "upper4", "upper5", "upper6", "upper7", "upper8", "upper9"]
HUBS = {0: "Grand Lobby", 3: "Sky Lobby", 6: "Sky Lobby", -1: "Penthouse"}
OTHER = ["Trading Floor", "Atrium", "Executive Suite", "Data Center", "Conference Hall", "Gallery", "Sky Garden", "Club Lounge"]
WORDS = ["Offices", "Residences", "Commerce", "Labs", "Suites", "Hotel", "Clinic", "Studios"]
SIZE = {0: 2}                                 # (junctions out from the core: per axis, from the footprint)
KEEP = 0.9                                    # a tower is full: most of the grid is built on every floor
LOOPS = 0.3
CAVES = {0: 0}

def floors(n):
    out = []
    for i in range(n):
        role = "GROUND FLOOR" if i == 0 else ("FLOOR %d" % (i + 1))
        out.append((DECK_KEYS[i], role, i))
    return out

def footprint(style, rng):
    """The tower's glass core (CityTowers.parts): cluster = about 1.2 R x 1.1 R, slab = 1.75 R x 0.75 R (R ~ 135 m),
    in px (10 px = 1 m), as a hull with cut corners."""
    R = 1350.0 * rng.uniform(0.92, 1.0)
    if style == "slab": w, h = R * 1.75, R * 0.8
    else: w, h = R * rng.uniform(1.12, 1.25), R * rng.uniform(1.0, 1.12)
    w, h = min(w, NPX - 300), min(h, NPX - 300)
    return octo(C, C, w / 2, h / 2, min(w, h) * 0.12)

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

def shafts(fid, n, NX, NY):
    """Real skyscraper lifts: LOW 1-4, MID 4-7, HIGH 7-top, EXPRESS 1-4-7 (the sky lobbies), each in its own place
    round the hall grid, the same shaft on every floor it serves."""
    rng = random.Random(int(hashlib.md5(("%s|shafts" % fid).encode()).hexdigest(), 16) % (2 ** 31))
    K = DECK_KEYS
    plan = [("LIFT L", K[0:4]), ("LIFT M", K[3:7]), ("LIFT H", K[6:n]), ("LIFT X", [K[0], K[3], K[6]])]
    corners = [(1, 1), (-1, -1), (1, -1), (-1, 1)]; rng.shuffle(corners)   # (the four corners: room for all four shafts)
    rest = [(i, j) for i in range(-NX, NX + 1) for j in range(-NY, NY + 1) if max(abs(i), abs(j)) >= 1 and (i, j) not in corners]
    rng.shuffle(rest)
    cells = corners + rest
    out, used = [], []
    for label, decks in plan:
        for c in cells:
            if c in used or any(abs(c[0] - u[0]) + abs(c[1] - u[1]) < 2 for u in used) or (label != "LIFT X" and c == (0, NY)): continue
            dirs = [(dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if abs(c[0] + dx) <= NX and abs(c[1] + dy) <= NY and (c[0] + dx, c[1] + dy) != (0, 0)]
            if not dirs: continue
            used.append(c); out.append({"label": label, "decks": decks, "cell": c, "dir": rng.choice(dirs), "side": rng.choice((-1, 1))})
            break
    return out

def lift_box(c, du, side):
    """The lift car's room beside the tunnel leaving junction c in direction du, on the given side, and its door."""
    px, py = C + c[0] * G, C + c[1] * G
    a0, a1 = MW / 2 + 14, MW / 2 + 14 + 66
    if du[1] == 0:   # (an east-west tunnel: the lift sits north or south of it)
        x0, x1 = sorted((px + du[0] * a0, px + du[0] * a1))
        e = py + side * MW / 2
        y0, y1 = sorted((e, e + side * 70))
        return box(x0, y0, x1, y1), ((x0 + x1) / 2, e, "h")
    y0, y1 = sorted((py + du[1] * a0, py + du[1] * a1))
    e = px + side * MW / 2
    x0, x1 = sorted((e, e + side * 70))
    return box(x0, y0, x1, y1), (e, (y0 + y1) / 2, "v")

def build_floor(fid, d, role, here, src, entry_floor, dname="main", SH=(), HULLP=None, NXY=(2, 2), lvl=0, nfl=10):
    planlib.DIAG.clear()
    seed = int(hashlib.md5(("%s|%s" % (fid, role)).encode()).hexdigest(), 16) % (2 ** 31)
    rng = random.Random(seed)
    HULL = HULLP                                         # (the tower's footprint: every floor)
    hubname = HUBS.get(lvl, HUBS[-1] if lvl == nfl - 1 else OTHER[(lvl + int(hashlib.md5(fid.encode()).hexdigest(), 16)) % len(OTHER)])
    R, HALLS, DOORS, SEGS, NAMES = {}, [], [], [], {"hub": hubname, "word": WORDS[(lvl * 3 + len(fid)) % len(WORDS)]}
    NX, NY = NXY; N = max(NX, NY)
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
    cells = [(i, j) for i in range(-NX, NX + 1) for j in range(-NY, NY + 1) if max(abs(i), abs(j)) >= 1]
    must = {(0, -1), (0, 1), (1, 0), (-1, 0)} | ({(0, NY)} if entry_floor else set())
    kept = {c for c in cells if c in must or rng.random() < KEEP}
    mine = [sh for sh in SH if dname in sh["decks"]]
    for sh in mine: kept.add(sh["cell"])
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
    def join(c0):   # (a lift's junction joined to the tunnels the shortest way, if the tree missed it)
        if c0 in seen: return
        prev, todo = {c0: None}, [c0]
        while todo:
            c = todo.pop(0)
            if c in seen and c != c0:
                while prev[c] is not None:
                    p_ = prev[c]; seen.add(p_); edges.add(tuple(sorted((c, p_)))); c = p_
                return
            for q in nb(c):
                if q not in prev and abs(q[0]) <= NX and abs(q[1]) <= NY and q != (0, 0):
                    prev[q] = c; todo.append(q)
    for sh in mine:
        join(sh["cell"])
        q = (sh["cell"][0] + sh["dir"][0], sh["cell"][1] + sh["dir"][1])   # (the tunnel the lift stands beside)
        seen.add(q); edges.add(tuple(sorted((sh["cell"], q))))
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
    LIFTS_HERE = []
    for sh in mine:   # the lift cars (before anything else is placed: they must be the same on every floor they serve)
        lb, ld = lift_box(sh["cell"], sh["dir"], sh["side"])
        nm = "Lift %s" % sh["label"][-1]
        R[nm] = lb; DOORS.append((round(ld[0], 1), round(ld[1], 1), ld[2])); LIFTS_HERE.append(nm)
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
        special = [(a, "Street Lobby")]
    if entry_floor: special = [((0, NY), "Street Lobby")]
    for c, nm in special:
        u = (0, 1) if nm == "Street Lobby" else outward(c)
        if not u: continue
        hw = 62.0
        p = P(c); cx, cy = p[0] + u[0] * (G * 0.55 + hw), p[1] + u[1] * (G * 0.55 + hw)
        if nm == "Street Lobby":   # (on the footprint's south edge: the door in from the street)
            edge = HULL.bounds[3] - 8; cy = min(cy, edge - hw)
        e = (cx - u[0] * hw, cy - u[1] * hw)
        g = octo(cx, cy, hw, hw, hw * 0.3)
        if not HULL.contains(g) or any(box(*g.bounds).buffer(20).intersects(h) for h in HALLS) or any(box(*g.bounds).buffer(30).intersects(box(*q.bounds)) for q in R.values()): continue
        seg(p, e); R[nm] = g; DOORS.append((round(e[0], 1), round(e[1], 1), "h" if u[0] == 0 else "v")); PADS.append(nm); taken.append(c)
    n_cave = 0
    for c in ends:
        if True: continue
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
        else: kinds[k] = "pilot"   # (the hub and the street lobby)
    for k in list(kinds):
        if kinds[k] == "mech": kinds[k] = "pilot"   # (owner: inside a building you're a pilot: nothing is mech-sized)
    S = Ship(fid, here, src, C, R, HALLS, DOORS, start=(C, C + A_A), center_y=C)
    info = {"lifts": LIFTS_HERE, "junctions": len(kept), "links": len(edges), "pads": PADS, "caves": n_cave, "rooms": len(R), "kit_shapes": len(used), "back": n_back, "doors": n_link}
    return S, kinds, hubname, info

def silhouette(P):   # the floor's own outline: everything dug out, with a rim of rock
    g = unary_union([shape(v) for v in P["rooms"].values()] + [shape(h) for h in P["halls"]] + [shape(h) for h in P.get("diag", [])]).buffer(18, join_style=2)
    return g

def draw(path, P, kinds, title):
    im = np.zeros((NPX, NPX, 3), np.uint8); im[:] = (30, 22, 18)
    rock = silhouette(P)
    for q in getattr(rock, "geoms", [rock]): cv2.fillPoly(im, [np.array(q.exterior.coords, np.int32)], (60, 48, 40))
    for h in P["halls"] + P.get("diag", []):
        for q in getattr(shape(h), "geoms", [shape(h)]): cv2.fillPoly(im, [np.array(q.exterior.coords, np.int32)], (40, 200, 245))
    for k, gj in P["rooms"].items():
        g = shape(gj); col = {"mech": (40, 30, 150), "pilot": (200, 110, 30), "lift": (235, 235, 235)}[kinds[k]]
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
    fid, nfl, style = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    name = sys.argv[4] if len(sys.argv) > 4 else "Tower"
    root = os.path.join(TR, "fleet_" + fid); eng = os.path.join(root, "eng"); dk = os.path.join(root, "decks")
    for p in (root, eng, dk): os.makedirs(p, exist_ok=True)
    rng0 = random.Random(int(hashlib.md5(("%s|foot" % fid).encode()).hexdigest(), 16) % (2 ** 31))
    HULLP = footprint(style, rng0)
    x0, y0, x1, y1 = HULLP.bounds
    NXY = (max(1, int((((x1 - x0) / 2) - 200) // G)), max(1, int((((y1 - y0) / 2) - 200) // G)))
    src = np.zeros((NPX, NPX, 3), np.uint8); src[:] = (30, 22, 18)
    cv2.fillPoly(src, [np.array(HULLP.exterior.coords, np.int32)], (70, 55, 45)); cv2.polylines(src, [np.array(HULLP.exterior.coords, np.int32)], True, (200, 170, 120), 6, cv2.LINE_AA)
    cv2.imwrite(os.path.join(root, "source.jpg"), src, [cv2.IMWRITE_JPEG_QUALITY, 90])
    bad_all = {}
    FL = floors(nfl)
    SH = shafts(fid, nfl, *NXY); shaft_at = {}
    for dname, role, lvl in FL:
        tmp = tempfile.mkdtemp()
        S, kinds, hub, info = build_floor(fid, 1, role, tmp if dname != "main" else eng, os.path.join(root, "source.jpg"), dname == "main", dname, SH, HULLP, NXY, lvl, nfl)
        bad = run(S); bad_all[dname] = bad
        P = json.load(open(os.path.join(S.here, "plan.json")))
        draw(os.path.join(dk, "%s_plan.jpg" % dname), P, kinds, "%s  -  %s  (%s)" % (name.upper(), role, hub.upper()))
        if dname == "main":
            json.dump({"hull": mapping(HULLP), "centre": [C, C], "model": "", "meta": {"tower": True, "style": style, "floors": nfl}}, open(os.path.join(root, "hull.json"), "w"))
            entry = "Street Lobby" if "Street Lobby" in P["rooms"] else hub
            ov = {"entry": entry, "C": hub, "kinds": kinds}
            json.dump(ov, open(os.path.join(eng, "overrides.json"), "w"), indent=1)
            pt = lambda k: [int(shape(P["rooms"][k]).representative_point().x), int(shape(P["rooms"][k]).representative_point().y)]
            Gp = {"entry": {"room": entry, "at": pt(entry)}, "locks": [], "guards": [], "wreck": [], "patrols": [], "targets": {},
                  "lifts": [{"room": k, "at": pt(k)} for k in info["lifts"]], "room_guards": {k: 1 for k in kinds if kinds[k] != "lift"},
                  "note": "%s GROUND FLOOR (tower_v1/tower_build.py, %d floors, %s)" % (name, nfl, style)}
            json.dump(Gp, open(os.path.join(eng, "gameplay.json"), "w"), indent=1)
            json.dump(Gp, open(os.path.join(eng, "gameplay_v1.json"), "w"), indent=1)
        else:
            P["deck"] = dname; P["level"] = lvl; P["hull"] = mapping(HULLP)
            P["lifts"] = [list(shape(P["rooms"][k]).centroid.coords[0]) for k in info["lifts"] if k in P["rooms"]]
            P["kinds"] = kinds
            json.dump(P, open(os.path.join(eng, "deck_%s.json" % dname), "w"))
        shutil.rmtree(tmp, ignore_errors=True)
        for k in info["lifts"]:
            if k in P["rooms"]: shaft_at.setdefault(k, list(shape(P["rooms"][k]).centroid.coords[0]))
        print("%-7s %-12s %-16s junctions %d links %d rooms %d (back %d, room doors %d, kit shapes %d) lifts %s unreachable %s" % (
            dname, role, hub, info["junctions"], info["links"], info["rooms"], info["back"], info["doors"], info["kit_shapes"], info["lifts"], bad))
    json.dump([{"label": sh["label"], "decks": sh["decks"], "at": shaft_at.get("Lift %s" % sh["label"][-1])} for sh in SH], open(os.path.join(eng, "shafts.json"), "w"), indent=1)
    json.dump({"floors": nfl, "style": style, "names": {k: r for k, r, _ in FL}}, open(os.path.join(eng, "tower.json"), "w"), indent=1)
    sys.exit(1 if any(bad_all.values()) else 0)

if __name__ == "__main__":
    main()
