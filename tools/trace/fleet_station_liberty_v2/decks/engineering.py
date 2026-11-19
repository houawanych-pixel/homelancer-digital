#!/usr/bin/env python3
"""Liberty Hub ENGINEERING deck (-1) in the same SHIP construction as the main and hangar decks: the station model's
own slice at this height (decks/outlines.json), the owner's district sheet rooms for Engineering (Reactor Core in the
middle, Engine Control, Power Routing, Maintenance North / South, Repair Shops A / B, Coolant Plants A / B,
Fabrication A / B), walkways in his Veranthos style (three octagon rings with angled corners, the cross, side lanes,
straight lanes down the E / W arms and angled lanes up the four diagonal arms), library rooms along every walkway, the
four lifts in the main deck's shafts. Writes eng/deck_lower.json (+ decks/engineering_plan_on_map.jpg)."""
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
HULL = shape(json.load(open(os.path.join(HERE, "outlines.json")))["ENGINEERING"]).buffer(-12)
MW, PW = 34.0, 20.0                    # mech / pilot walkway widths (px)
A_HUB, A_A, A_B, A_P = 128.0, 232.0, 420.0, 600.0   # apothems: the Reactor Core, rings A (by the lifts) and B, the outer ring P
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

# ---- the arms: where each leaves the promenade's angled corner, and its tip (measured on the owner's map)
ARMS = [(27, (2993, 973)), (153, (307, 973)), (210, (253, 2455)), (330, (3047, 2455))]
CORNER_OF = lambda deg: {0: 0, 1: 6, 2: 4, 3: 2}[int(deg // 90)]       # quadrant -> the promenade corner index
breaks, ARM_ROOT, ARM_DIR, ARM_MID = {}, {}, {}, {}
from shapely.geometry import LineString as _LS
for deg, tip in ARMS:
    # the arm's own centre line: from its tip back through the middle of the arm (the arms don't point at the hub)
    th = math.radians(deg); vx, vy = (tip[0] - C), (tip[1] - C); L0 = math.hypot(vx, vy); vx, vy = vx / L0, vy / L0
    mids = []
    for back in (260, 420):
        q = (tip[0] - vx * back, tip[1] - vy * back)
        cr = _LS([(q[0] + vy * 400, q[1] - vx * 400), (q[0] - vy * 400, q[1] + vx * 400)]).intersection(HULL)
        seg = min(getattr(cr, "geoms", [cr]), key=lambda g: g.distance(Point(q)))
        c_ = seg.interpolate(0.5, normalized=True); mids.append((c_.x, c_.y))
    ux, uy = mids[0][0] - mids[1][0], mids[0][1] - mids[1][1]; n_ = math.hypot(ux, uy); ux, uy = ux / n_, uy / n_
    # where that line meets the promenade's angled corner: (|dx| + |dy|) / sqrt 2 = A_P
    ox, oy = mids[1]
    sgx, sgy = (1 if tip[0] > C else -1), (1 if tip[1] > C else -1)
    t = (A_P * math.sqrt(2) - (sgx * (ox - C) + sgy * (oy - C))) / (sgx * ux + sgy * uy)
    p = (ox + ux * t, oy + uy * t)
    breaks.setdefault(CORNER_OF(deg), []).append(p); ARM_ROOT[deg] = p; ARM_DIR[deg] = (ux, uy); ARM_MID[deg] = mids[0]

# an arm that leaves right by a corner of the outer ring leaves from that corner's node itself
_sP = A_P * math.tan(math.radians(22.5))
_VP = [(C + _sP, C - A_P), (C + A_P, C - _sP), (C + A_P, C + _sP), (C + _sP, C + A_P), (C - _sP, C + A_P), (C - A_P, C + _sP), (C - A_P, C - _sP), (C - _sP, C - A_P)]
for deg in list(ARM_ROOT):
    p_ = ARM_ROOT[deg]
    v = min(_VP, key=lambda q: math.hypot(q[0] - p_[0], q[1] - p_[1]))
    if math.hypot(v[0] - p_[0], v[1] - p_[1]) < 3.0 * MW:
        ci = CORNER_OF(deg); breaks[ci] = [q for q in breaks[ci] if q is not p_]
        ARM_ROOT[deg] = v
        mx, my = ARM_MID[deg]; L_ = math.hypot(mx - v[0], my - v[1]); ARM_DIR[deg] = ((mx - v[0]) / L_, (my - v[1]) / L_)
# ---- the hub and the rings
R["Reactor Core"] = octo(C, C, A_HUB, A_HUB, A_HUB * 0.414)
ring(A_A, MW); ring(A_B, MW); ring(A_P, MW, breaks)
# the cross: from the hub out through every ring to the promenade (and N / S on up the top and bottom spikes)
for dx, dy in ((0, -1), (0, 1), (1, 0), (-1, 0)):
    a0, a1 = A_HUB, A_P
    HALLS.append(hall((C + dx * a0, C + dy * a0), (C + dx * a1, C + dy * a1), w=MW))
    DOORS.append((C + dx * a0, C + dy * a0, "h" if dx == 0 else "v"))
LANES = []
sA_ = A_A * math.tan(math.radians(22.5))
for sx in (-1, 1):
    for sy in (-1, 1):
        LANES += [(C + sx * sA_, C + sy * A_A, C + sx * sA_, C + sy * A_B, MW), (C + sx * A_A, C + sy * sA_, C + sx * A_B, C + sy * sA_, MW)]
for x0_, y0_, x1_, y1_, w_ in LANES: HALLS.append(hall((x0_, y0_), (x1_, y1_), w=w_))
TIPNAME = {27: "Repair Shop B", 153: "Repair Shop A", 210: "Fabrication A", 330: "Fabrication B"}
def arm(deg, tip):
    p = ARM_ROOT[deg]; up = tip[1] < C
    ux, uy = ARM_DIR[deg]
    # the pad: the biggest square (up to 110 px) that fits in the arm, as far out as it goes
    pad = None
    for k in range(60):
        d = math.hypot(tip[0] - p[0], tip[1] - p[1]) - 60 - 12 * k
        cx, cy = p[0] + ux * d, p[1] + uy * d
        for hw in (60, 52, 45):
            g = box(cx - hw, cy - hw, cx + hw, cy + hw)
            if HULL.contains(g): pad = (cx, cy, hw); break
        if pad: break
    if not pad: return None
    cx, cy, hw = pad
    sy = -1 if up else 1
    # first a short straight stub out of the promenade (clear of its angled corner), then the angled lane
    q = (p[0], p[1] + sy * 2.4 * MW)
    HALLS.append(hall(p, q, w=MW)); node(q[0], q[1], MW)
    shallow = abs(ux) > abs(uy)
    if shallow:      # out of the stub's side, ends square (vertical) at the pad's near side
        sx = 1 if ux > 0 else -1
        ex = cx - sx * hw
        a0 = (q[0] + sx * MW / 2, q[1] + sx * MW / 2 * uy / ux)
        ey = a0[1] + (ex - a0[0]) * uy / ux
        HALLS.append(dhall(a0, (ex, ey), w=MW, axis="x"))
        R[TIPNAME[deg]] = octo(cx, ey, hw, hw, hw * 0.3)
        DOORS.append((round(ex, 1), round(ey, 1), "v"))
        return TIPNAME[deg]
    ey = cy + hw if up else cy - hw                    # the lane ends square at the pad's near edge
    a0 = (q[0] + sy * MW / 2 * ux / uy * sy * sy, q[1] + sy * MW / 2)
    a0 = (q[0] + (MW / 2) * ux / abs(uy), q[1] + sy * MW / 2)
    ex = a0[0] + (ey - a0[1]) * ux / uy
    HALLS.append(dhall(a0, (ex, ey), w=MW, axis="y"))
    name = TIPNAME[deg]
    R[name] = octo(ex, cy, hw, hw, hw * 0.3) if abs(ex - cx) < 2 else octo(ex, cy, hw, hw, hw * 0.3)
    DOORS.append((round(ex, 1), round(ey, 1), "h"))
    return name
PADS = [arm(d, t) for d, t in ARMS]
print("tips:", PADS, {d: [round(v) for v in ARM_ROOT[d]] for d in ARM_ROOT})
# ---- the E / W arms: a straight mech lane down each (the model's arms run a little below the cross) to a launch gate
GATES = []
ARM_Y = 1697.0
for sx in (-1, 1):
    x = C + sx * (A_P + MW / 2 + 60)
    while HULL.contains(box(x - 40, ARM_Y - 40, x + 40, ARM_Y + 40)) or abs(x - C) < A_P + 200:
        nx = x + sx * 10
        if not HULL.contains(box(nx - 40, ARM_Y - 40, nx + 40, ARM_Y + 40)) and abs(x - C) >= A_P + 200: break
        x = nx
        if abs(x - C) > 1600: break
    hw = 40; ex = x - sx * hw
    HALLS.append(hall((C + sx * A_P, ARM_Y), (ex, ARM_Y), w=MW))
    nm = "Coolant Plant %s" % ("B" if sx > 0 else "A")
    R[nm] = octo(x, ARM_Y, hw, hw, hw * 0.3); DOORS.append((round(ex, 1), ARM_Y, "v")); GATES.append(nm)
# ---- the N / S: the cross runs on out of the outer ring to a launch pad at each end of the hull, rooms along it
NS_SEGS = []
for sy in (-1, 1):
    y = C + sy * (A_P + 120)
    while HULL.contains(box(C - 60, y - 60, C + 60, y + 60)): y += sy * 10
    y -= sy * 10
    ey = y - sy * 60
    HALLS.append(hall((C, C + sy * A_P), (C, ey), w=MW))
    nm = "Maintenance %s" % ("North" if sy < 0 else "South")
    R[nm] = octo(C, y, 60, 60, 18); DOORS.append((C, round(ey, 1), "h")); GATES.append(nm)
    NS_SEGS.append((C, min(C + sy * A_P, ey), C, max(C + sy * A_P, ey), MW))
# ---- the district sheet's big hangar rooms, in the band between ring B and the outer ring, either side of the cross
BIG = {(0, -1): ("Engine Control A", "Engine Control B"), (0, 1): ("Power Routing A", "Power Routing B"), (1, 0): ("Turbine Hall NE", "Turbine Hall SE"),
       (-1, 0): ("Turbine Hall NW", "Turbine Hall SW")}
sB = A_B * math.tan(math.radians(22.5)); sP = A_P * math.tan(math.radians(22.5))
for (dx, dy), (n1, n2) in BIG.items():
    for k, nm in ((-1, n1), (1, n2)):
        lo, hi = MW / 2 + 8, sP - 28                      # from the cross to clear of the outer ring's corner
        d0, d1 = A_B + MW / 2 + 8, A_P - MW / 2           # the band between ring B and the outer ring
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
    if 45 <= a < 135: return "Engine Deck"
    if 225 <= a < 315: return "Power Deck"
    return "Coolant East" if x > C else "Coolant West"
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
for a, w in ((A_A, MW), (A_B, MW), (A_P, MW)):
    s_ = a * math.tan(math.radians(22.5))
    SEGS += [(C - s_, C - a, C + s_, C - a, w), (C - s_, C + a, C + s_, C + a, w), (C - a, C - s_, C - a, C + s_, w), (C + a, C - s_, C + a, C + s_, w)]
SEGS += [(C, C - A_P, C, C - A_HUB, MW), (C, C + A_HUB, C, C + A_P, MW), (C - A_P, C, C - A_HUB, C, MW), (C + A_HUB, C, C + A_P, C, MW)]
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
            mech = rr > A_B + 20
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
    P["deck"] = "lower"; P["level"] = -1; P["hull"] = mapping(shape(json.load(open(os.path.join(HERE, "outlines.json")))["ENGINEERING"]))
    P["lifts"] = [[(b[0] + b[2]) / 2, (b[1] + b[3]) / 2] for b, _ in LIFTS.values()]
    MECHW = ("Reactor", "Engine Control", "Power Routing", "Turbine", "Coolant Plant", "Maintenance", "Repair Shop", "Fabrication")
    P["kinds"] = {k: ("lift" if k.startswith("Lift") else "mech" if k.startswith(MECHW) or any(k.endswith(" " + TAGWORD[t] + " " + k.split()[-1]) for t in MECH_TAGS) else "pilot") for k in R}
    json.dump(P, open(os.path.join(ENG, "deck_lower.json"), "w"))
    shutil.copy(os.path.join(tmp, "plan_on_map.jpg"), os.path.join(HERE, "engineering_plan_on_map.jpg"))
    print("ENGINEERING rooms", len(R), "angled pieces", len(planlib.DIAG), "unreachable", bad)
    sys.exit(1 if bad else 0)
