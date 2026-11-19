#!/usr/bin/env python3
"""Liberty Hub COMMAND deck (+2, the top) in the same SHIP construction as the other decks: the station model's own
slice at this height (decks/outlines.json: a ring - its middle is filled here, a deck floor over the core, so the lifts
reach it and it reads as the owner's round Command district), the owner's district sheet rooms for Command (CIC in the
middle, the Bridge, Sensors Suite, Briefing Room, Comms Center, Strategy Room, Officers' Ready Room, Security Center),
walkways in his Veranthos style (a mech ring by the lifts, a pilot ring, the outer mech ring, the cross out to the
Bridge in the north and the Security Center in the south), library rooms along every walkway, the lifts in the same
four shafts. Writes eng/deck_upper2.json."""
import json, math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
TR = os.path.join(HERE, "..", "..")
ENG = os.path.join(HERE, "..", "eng")
sys.path.insert(0, TR)
import planlib
from planlib import *
from shapely.geometry import Polygon, box, Point, shape, mapping
from shapely import affinity
from shapely.ops import unary_union

C = 1650.0
_cmd = shape(json.load(open(os.path.join(HERE, "outlines.json")))["COMMAND"])
HULL = Polygon(_cmd.exterior).buffer(-12)   # (the ring's middle filled: a deck floor over the core)
MW, PW = 34.0, 20.0                    # mech / pilot walkway widths (px)
A_HUB, A_A, A_B, A_P = 128.0, 232.0, 420.0, 580.0   # apothems: the CIC, ring A (by the lifts), the pilot ring B, the outer ring P
LIB = json.load(open(os.path.join(TR, "shape_library.json")))["rooms"]

def octo(cx, cy, hw, hh, c):
    return Polygon([(cx - hw + c, cy - hh), (cx + hw - c, cy - hh), (cx + hw, cy - hh + c), (cx + hw, cy + hh - c),
                    (cx + hw - c, cy + hh), (cx - hw + c, cy + hh), (cx - hw, cy + hh - c), (cx - hw, cy - hh + c)])

R, HALLS, DOORS = {}, [], []
def node(x, y, w):
    g = box(x - w / 2, y - w / 2, x + w / 2, y + w / 2); HALLS.append(g); return g

def ring(a, w, breaks=None):
    """An octagon walkway (apothem a): straight sides and angled corners, a node square at every corner.
    breaks: {corner index: [points on that corner's diagonal]} - more node squares on it (an arm leaves there)."""
    s = a * math.tan(math.radians(22.5))
    V = [(C + s, C - a), (C + a, C - s), (C + a, C + s), (C + s, C + a), (C - s, C + a), (C - a, C + s), (C - a, C - s), (C - s, C - a)]
    for v in V: node(v[0], v[1], w)
    for i in range(0, 8, 2):            # the straight sides: V7-V0 (top), V1-V2 (right), V3-V4 (bottom), V5-V6 (left)
        p, q = V[(i - 1) % 8], V[i]
        HALLS.append(hall(p, q, w=w))
    for i in range(0, 8, 2):            # the angled corners: V0-V1, V2-V3, V4-V5, V6-V7
        p, q = V[i], V[i + 1]
        pts = [p] + sorted((breaks or {}).get(i, []), key=lambda t: math.hypot(t[0] - p[0], t[1] - p[1])) + [q]
        for t in pts[1:-1]: node(t[0], t[1], w)
        for u, v in zip(pts, pts[1:]):
            sx = 1 if v[0] > u[0] else -1
            sy = 1 if v[1] > u[1] else -1
            HALLS.append(dhall((u[0] + sx * w / 2, u[1] + sy * w / 2), (v[0] - sx * w / 2, v[1] - sy * w / 2), w=w, axis="x"))
    return V

# ---- the hub and the rings
R["CIC (Combat Information Center)"] = octo(C, C, A_HUB, A_HUB, A_HUB * 0.414)
ring(A_A, MW); ring(A_B, PW); ring(A_P, MW)
# the cross: from the hub out through every ring to the promenade (and N / S on up the top and bottom spikes)
for dx, dy in ((0, -1), (0, 1), (1, 0), (-1, 0)):
    a0, a1 = A_HUB, (A_B if dx == 0 else A_P)   # (N / S: the cross stops at ring B - the Bridge and the Security Center sit across it)
    HALLS.append(hall((C + dx * a0, C + dy * a0), (C + dx * a1, C + dy * a1), w=MW))
    DOORS.append((C + dx * a0, C + dy * a0, "h" if dx == 0 else "v"))
LANES = []
sA_ = A_A * math.tan(math.radians(22.5))
for sx in (-1, 1):
    for sy in (-1, 1):
        LANES += [(C + sx * sA_, C + sy * A_A, C + sx * sA_, C + sy * A_B, PW), (C + sx * A_A, C + sy * sA_, C + sx * A_B, C + sy * sA_, PW)]
for x0_, y0_, x1_, y1_, w_ in LANES: HALLS.append(hall((x0_, y0_), (x1_, y1_), w=w_))
GATES = []
# ---- the Bridge (north) and the Security Center (south): big rooms across the cross, between ring B and the outer ring,
# a door onto each
NS_SEGS = []
sP_ = A_P * math.tan(math.radians(22.5))
for sy, nm in ((-1, "Bridge"), (1, "Security Center")):
    y0_, y1_ = sorted([C + sy * (A_B + PW / 2), C + sy * (A_P - MW / 2)])
    R[nm] = octo(C, (y0_ + y1_) / 2, 95, (y1_ - y0_) / 2, 22)
    DOORS.append((C, C + sy * (A_B + PW / 2), "h")); DOORS.append((C, C + sy * (A_P - MW / 2), "h"))
# ---- the district sheet's big hangar rooms, in the band between ring B and the outer ring, either side of the cross
BIG = {(0, -1): ("Sensors Suite", "Briefing Room"), (0, 1): ("Officers' Ready Room", "Admiral's Office"), (1, 0): ("Strategy Room", "War Room"),
       (-1, 0): ("Comms Center", "Fleet Operations")}
sB = A_B * math.tan(math.radians(22.5)); sP = A_P * math.tan(math.radians(22.5))
for (dx, dy), (n1, n2) in BIG.items():
    for k, nm in ((-1, n1), (1, n2)):
        lo, hi = (95 + 12 if dx == 0 else MW / 2 + 8), sP - 28   # from the cross (N / S: from the Bridge / Security Center) to clear of the outer ring's corner
        d0, d1 = A_B + PW / 2 + 8, A_P - MW / 2           # the band between the pilot ring and the outer ring
        if dx == 0:
            xs = sorted([C + k * lo, C + k * hi]); ys = sorted([C + dy * d0, C + dy * d1])
            g = box(xs[0], ys[0], xs[1], ys[1]); door = ((xs[0] + xs[1]) / 2, C + dy * d1, "h")   # (on the outer ring)
        else:
            ys = sorted([C + k * lo, C + k * hi]); xs = sorted([C + dx * d0, C + dx * d1])
            g = box(xs[0], ys[0], xs[1], ys[1]); door = (C + dx * d1, (ys[0] + ys[1]) / 2, "v")
        R[nm] = octo((xs[0] + xs[1]) / 2, (ys[0] + ys[1]) / 2, (xs[1] - xs[0]) / 2, (ys[1] - ys[0]) / 2, 14)
        DOORS.append((round(door[0], 1), round(door[1], 1), door[2]))
# ---- the lifts: the main deck's shafts (same boxes, same doors on the cross)
LIFTS = {"Lift (north)": ((1667, 1332, 1729, 1402), (1667.0, 1367.0, "v")), "Lift (south)": ((1667, 1976, 1729, 2046), (1667.0, 2011.0, "v")),
         "Lift (East)": ((1898, 1571, 1968, 1633), (1933.0, 1633.0, "h")), "Lift (West)": ((1332, 1571, 1402, 1633), (1367.0, 1633.0, "h"))}
for nm, (bx_, d_) in LIFTS.items(): R[nm] = box(*bx_); DOORS.append(d_)

# ---- the rooms: rows along every ring's straight sides, library shapes fitted to their slots
def pick(tags, w, h, seed):
    ar = w / h
    cand = [r for r in LIB if r["tag"] in tags and r["w_m"] > 0 and r["h_m"] > 0]
    ok = []
    for r in cand:
        for rot in (0, 90):
            rw, rh = (r["w_m"], r["h_m"]) if rot == 0 else (r["h_m"], r["w_m"])
            k = (rw / rh) / ar
            if 1 / 1.4 <= k <= 1.4: ok.append((r, rot))
    if not ok: return box(-w / 2, -h / 2, w / 2, h / 2)
    r, rot = ok[seed % len(ok)]
    g = Polygon(r["poly"]).buffer(0)
    if rot: g = affinity.rotate(g, 90, origin=(0, 0))
    x0, y0, x1, y1 = g.bounds
    g = affinity.translate(g, -(x0 + x1) / 2, -(y0 + y1) / 2)
    return affinity.scale(g, w / (x1 - x0), h / (y1 - y0), origin=(0, 0)).simplify(0.4)

PILOT_TAGS = ["cabin", "office", "quarters", "closet", "vestibule", "mess", "lounge", "medbay", "command"]
MECH_TAGS = ["cargo", "engine", "machine", "weapons", "wing", "junction"]
def sector(x, y):
    a = math.degrees(math.atan2(-(y - C), x - C)) % 360
    if 45 <= a < 135: return "Command North"
    if 225 <= a < 315: return "Command South"
    return "Command East" if x > C else "Command West"
TAGWORD = {"cabin": "Cabin", "office": "Office", "quarters": "Quarters", "closet": "Store", "vestibule": "Lobby", "mess": "Canteen",
           "lounge": "Lounge", "medbay": "Clinic", "command": "Control", "cargo": "Cargo Bay", "engine": "Plant", "machine": "Machine Shop",
           "weapons": "Armoury", "wing": "Loading Bay", "junction": "Bay"}
taken = []
def blocked(g):
    occ = unary_union(HALLS + [b.buffer(4) for b in list(R.values()) + taken] + [box(*d.bounds).buffer(3) for d in planlib.DIAG])
    return g.buffer(-2).intersects(occ) or not HULL.contains(g)
# every straight walkway (ring sides, the cross, the links) is lined with rooms on both sides wherever the floor is
# free: the rooms of the right half are laid, then mirrored (mirror-true)
SEGS = []   # (x0, y0, x1, y1, width, mech side?)  axis-aligned walkway centre lines
for a, w in ((A_A, MW), (A_B, PW), (A_P, MW)):
    s_ = a * math.tan(math.radians(22.5))
    SEGS += [(C - s_, C - a, C + s_, C - a, w), (C - s_, C + a, C + s_, C + a, w), (C - a, C - s_, C - a, C + s_, w), (C + a, C - s_, C + a, C + s_, w)]
SEGS += [(C, C - A_B, C, C - A_HUB, MW), (C, C + A_HUB, C, C + A_B, MW), (C - A_P, C, C - A_HUB, C, MW), (C + A_HUB, C, C + A_P, C, MW)]
SEGS += LANES + NS_SEGS
n_room = {}
def place(bx, door, mech, seed):
    x0, y0, x1, y1 = bx.bounds; cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    sec = sector(cx, cy)
    tags = MECH_TAGS if mech else PILOT_TAGS
    tag = tags[seed % len(tags)]
    g = affinity.translate(pick([tag], x1 - x0, y1 - y0, seed), cx, cy)
    dw = DOOR + 12
    g0 = g
    for dd in range(10, 200, 8):   # a doorway strip from the door in, as deep as it takes to reach the room's shape
        strip = (box(door[0] - dw / 2, door[1] - dd, door[0] + dw / 2, door[1] + dd) if door[2] == "h" else box(door[0] - dd, door[1] - dw / 2, door[0] + dd, door[1] + dw / 2)).intersection(bx)
        g = unary_union([g0, strip]).intersection(bx).buffer(0)
        if g.geom_type == "Polygon" and strip.intersection(g0).area > dw * 12: break
    if g.geom_type != "Polygon": g = max(g.geoms, key=lambda q: q.area)
    n_room[(sec, tag)] = n_room.get((sec, tag), 0) + 1
    nm = "%s %s %d" % (sec, TAGWORD[tag], n_room[(sec, tag)])
    R[nm] = g; taken.append(bx); DOORS.append((round(door[0], 1), round(door[1], 1), door[2]))
    return nm
def mirror_box(b):
    x0, y0, x1, y1 = b.bounds; return box(2 * C - x1, y0, 2 * C - x0, y1)
for si, (x0, y0, x1, y1, w) in enumerate(SEGS):
    horiz = abs(y1 - y0) < 1
    for side in (-1, 1):
        # a room's depth: mech rooms beyond ring C (the cargo / mech districts), pilot rooms inside
        u0, u1 = (min(x0, x1), max(x0, x1)) if horiz else (min(y0, y1), max(y0, y1))
        u = u0 + 8
        k = 0
        while True:
            mid = ((u + 30) - C, (y0 if horiz else x0) - C)
            rr = max(abs(mid[0]), abs(mid[1]))
            mech = False   # (the habitat: people's rooms)
            done = False
            for depth, length in ([(88, 96), (62, 70), (50, 58)] if mech else [(62, 70), (50, 58)]):   # (the biggest that fits)
                if u + length > u1 - 4: continue
                if horiz:
                    e = y0 + side * w / 2
                    bx = box(u, min(e, e + side * depth), u + length, max(e, e + side * depth)); door = (u + length / 2, e, "h")
                else:
                    e = x0 + side * w / 2
                    bx = box(min(e, e + side * depth), u, max(e, e + side * depth), u + length); door = (e, u + length / 2, "v")
                cx = (bx.bounds[0] + bx.bounds[2]) / 2
                if cx >= C + 2 and not blocked(bx):
                    mb = mirror_box(bx)
                    if not blocked(mb) or abs(cx - C) < 2:
                        seed = abs(hash((si, side, k))) % 997
                        place(bx, door, mech and depth >= 88, seed)
                        if not bx.equals(mb) and not blocked(mb):
                            md = (2 * C - door[0], door[1], door[2])
                            g0 = R[list(R)[-1]]
                            place(mb, md, mech and depth >= 88, seed)
                            R[list(R)[-1]] = affinity.scale(g0, -1, 1, origin=(C, C))
                        u += length + 8; k += 1; done = True; break
            if done: continue
            if u + 58 > u1 - 4: break
            u += 10

START = (C - A_B, C)
S = Ship("station_liberty_v2", HERE, os.path.join(HERE, "..", "source.jpg"), C, R, HALLS, DOORS, start=START, center_y=C)
if __name__ == "__main__":
    import tempfile, shutil
    tmp = tempfile.mkdtemp(); S.here = tmp
    bad = run(S)
    P = json.load(open(os.path.join(tmp, "plan.json")))
    P["deck"] = "upper2"; P["level"] = 2; P["hull"] = mapping(shape(json.load(open(os.path.join(HERE, "outlines.json")))["COMMAND"]))
    P["lifts"] = [[(b[0] + b[2]) / 2, (b[1] + b[3]) / 2] for b, _ in LIFTS.values()]
    MECHW = ("CIC", "Bridge", "Security Center")
    P["kinds"] = {k: ("lift" if k.startswith("Lift") else "mech" if k.startswith(MECHW) or any(k.endswith(" " + TAGWORD[t] + " " + k.split()[-1]) for t in MECH_TAGS) else "pilot") for k in R}
    json.dump(P, open(os.path.join(ENG, "deck_upper2.json"), "w"))
    shutil.copy(os.path.join(tmp, "plan_on_map.jpg"), os.path.join(HERE, "command_plan_on_map.jpg"))
    print("COMMAND rooms", len(R), "angled pieces", len(planlib.DIAG), "unreachable", bad)
    sys.exit(1 if bad else 0)
