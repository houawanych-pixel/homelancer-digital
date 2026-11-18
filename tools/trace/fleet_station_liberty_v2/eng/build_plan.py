#!/usr/bin/env python3
"""Liberty Hub (Veranthos Customs) MAIN HUB deck v2, in the SHIP construction (planlib, 10 px = 1 m) on the owner's
"Veranthos Customs inner map - mech & pilot ways (concept)" (Nov 18 2026: "I like the walkways on this map"; "a lot
of small rooms to show the massive size ... pull them from the library that we made").

Walkways, as on his map (v13.222 engine: angled hallways, planlib.dhall):
  the CENTRAL CUSTOMS HUB (the 360 main hub) in the middle, a pilot ring round it (ring A),
  two mech rings (B, C) and the outer mech promenade (P), all octagons with their angled corners,
  the cross (N / S / E / W spokes) from the hub out through every ring,
  short links between the rings, and a mech lane up every docking arm to its dock pad at the tip.
Rooms: rows along the rings' straight sides, each room a traced library shape (shape_library.json) fitted to its
slot (stretch within 1.4x), a door on the walkway; the district names from his map. Mirror-true left / right.
Writes plan.json etc. (planlib.run), overrides.json (room kinds), gameplay.json (first pass, then fleet_formula)."""
import json, math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
TR = os.path.join(HERE, "..", "..")
sys.path.insert(0, TR)
import planlib
from planlib import *
from shapely.geometry import Polygon, box, Point, shape
from shapely import affinity
from shapely.ops import unary_union

C = 1650.0
HULL = shape(json.load(open(os.path.join(HERE, "..", "hull.json")))["hull"]).buffer(-12)
MW, PW = 34.0, 20.0                    # mech / pilot walkway widths (px)
A_HUB, A_A, A_B, A_C, A_P = 150.0, 232.0, 420.0, 640.0, 860.0   # apothems: hub room, rings A B C, promenade P
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
ARMS = [(32, (3066, 779)), (54, (2535, 419)), (126, (765, 419)), (148, (235, 776)),
        (216, (375, 2577)), (234, (719, 2947)), (306, (2578, 2949)), (324, (2925, 2577))]
CORNER_OF = lambda deg: {0: 0, 1: 6, 2: 4, 3: 2}[int(deg // 90)]       # quadrant -> the promenade corner index
breaks, ARM_ROOT, ARM_DIR = {}, {}, {}
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
    breaks.setdefault(CORNER_OF(deg), []).append(p); ARM_ROOT[deg] = p; ARM_DIR[deg] = (ux, uy)

# ---- the hub and the rings
R["Main Hub (Central Customs)"] = octo(C, C, A_HUB, A_HUB, A_HUB * 0.414)
ring(A_A, PW); ring(A_B, MW); ring(A_C, MW); ring(A_P, MW, breaks)
# the cross: from the hub out through every ring to the promenade (and N / S on up the top and bottom spikes)
for dx, dy in ((0, -1), (0, 1), (1, 0), (-1, 0)):
    a0, a1 = A_HUB, A_P
    HALLS.append(hall((C + dx * a0, C + dy * a0), (C + dx * a1, C + dy * a1), w=MW))
    DOORS.append((C + dx * a0, C + dy * a0, "h" if dx == 0 else "v"))
# links between the rings, off the cross (on the straight sides): B-C and C-P, at 0.55 of the side
for a0, a1 in ((A_B, A_C), (A_C, A_P)):
    s0 = a0 * math.tan(math.radians(22.5)) * 0.55
    for sx in (-1, 1):
        for rot in range(4):
            p, q = (C + sx * s0, C - a0), (C + sx * s0, C - a1)
            g = affinity.rotate(hall(p, q, w=PW if a0 == A_B else MW), 90 * rot, origin=(C, C))
            HALLS.append(g)

# side lanes: from each ring's corner straight out to the next ring's straight side, so every angled sector between two
# rings has straight walkways on its sides (and rooms along them)
LANES = []
for a0, a1, w_ in ((A_A, A_B, PW), (A_B, A_C, MW), (A_C, A_P, MW)):
    s0 = a0 * math.tan(math.radians(22.5))
    for sx in (-1, 1):
        for sy in (-1, 1):
            LANES += [(C + sx * s0, C + sy * a0, C + sx * s0, C + sy * a1, w_), (C + sx * a0, C + sy * s0, C + sx * a1, C + sy * s0, w_)]
for x0_, y0_, x1_, y1_, w_ in LANES: HALLS.append(hall((x0_, y0_), (x1_, y1_), w=w_))

# ---- the docking arms: a mech lane from the promenade up the arm, a dock pad at the tip
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
        R["Dock Pad %d" % deg] = octo(cx, ey, hw, hw, hw * 0.3)
        DOORS.append((round(ex, 1), round(ey, 1), "v"))
        return "Dock Pad %d" % deg
    ey = cy + hw if up else cy - hw                    # the lane ends square at the pad's near edge
    a0 = (q[0] + sy * MW / 2 * ux / uy * sy * sy, q[1] + sy * MW / 2)
    a0 = (q[0] + (MW / 2) * ux / abs(uy), q[1] + sy * MW / 2)
    ex = a0[0] + (ey - a0[1]) * ux / uy
    HALLS.append(dhall(a0, (ex, ey), w=MW, axis="y"))
    name = "Dock Pad %d" % deg
    R[name] = octo(ex, cy, hw, hw, hw * 0.3) if abs(ex - cx) < 2 else octo(ex, cy, hw, hw, hw * 0.3)
    DOORS.append((round(ex, 1), round(ey, 1), "h"))
    return name
PADS = [arm(d, t) for d, t in ARMS]
# the top and bottom spikes: the cross runs on up / down to a pad
for sy, tipy in ((-1, 482), (1, 2809)):
    for k in range(40):
        cy = tipy - sy * (75 + 12 * k)
        g = box(C - 55, cy - 55, C + 55, cy + 55)
        if HULL.contains(g): break
    ey = cy - sy * 55
    HALLS.append(hall((C, C + sy * A_P), (C, ey), w=MW))
    R["Dock Pad %s" % ("N" if sy < 0 else "S")] = octo(C, cy, 55, 55, 16)
    DOORS.append((C, ey, "h"))

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
    left = x < C
    if 67.5 <= a < 112.5: return "Pilot Services" if left else "Crew Services"
    if 247.5 <= a < 292.5: return "Logistics & Supply" if left else "Transit Concourse"
    if 22.5 <= a < 67.5: return "Customs Processing NE"
    if 112.5 <= a < 157.5: return "Customs Processing NW"
    if 157.5 <= a < 202.5: return "Cargo Inspection West"
    if a >= 337.5 or a < 22.5: return "Cargo Inspection East"
    if 202.5 <= a < 247.5: return "Mech Servicing West"
    return "Mech Servicing East"
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
for a, w in ((A_A, PW), (A_B, MW), (A_C, MW), (A_P, MW)):
    s_ = a * math.tan(math.radians(22.5))
    SEGS += [(C - s_, C - a, C + s_, C - a, w), (C - s_, C + a, C + s_, C + a, w), (C - a, C - s_, C - a, C + s_, w), (C + a, C - s_, C + a, C + s_, w)]
SEGS += [(C, C - A_P, C, C - A_HUB, MW), (C, C + A_HUB, C, C + A_P, MW), (C - A_P, C, C - A_HUB, C, MW), (C + A_HUB, C, C + A_P, C, MW)]
for a0, a1 in ((A_B, A_C), (A_C, A_P)):
    s0 = a0 * math.tan(math.radians(22.5)) * 0.55
    w_ = PW if a0 == A_B else MW
    for sx in (-1, 1):
        SEGS += [(C + sx * s0, C - a1, C + sx * s0, C - a0, w_), (C + sx * s0, C + a0, C + sx * s0, C + a1, w_),
                 (C - a1, C + sx * s0, C - a0, C + sx * s0, w_), (C + a0, C + sx * s0, C + a1, C + sx * s0, w_)]
SEGS += LANES
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
            mech = rr > A_C + 20
            depth, length = (88, 96) if mech else (62, 70)
            if u + length > u1 - 4: break
            if horiz:
                e = y0 + side * w / 2
                bx = box(u, min(e, e + side * depth), u + length, max(e, e + side * depth))
                door = (u + length / 2, e, "h")
            else:
                e = x0 + side * w / 2
                bx = box(min(e, e + side * depth), u, max(e, e + side * depth), u + length)
                door = (e, u + length / 2, "v")
            cx = (bx.bounds[0] + bx.bounds[2]) / 2
            if cx >= C + 2 and not blocked(bx):
                mb = mirror_box(bx)
                if not blocked(mb) or abs(cx - C) < 2:
                    seed = abs(hash((si, side, k))) % 997
                    place(bx, door, mech, seed)
                    if not bx.equals(mb) and not blocked(mb):
                        md = (2 * C - door[0], door[1], door[2])
                        g0 = R[list(R)[-1]]
                        place(mb, md, mech, seed)
                        R[list(R)[-1]] = affinity.scale(g0, -1, 1, origin=(C, C))   # (the twin: the same shape, mirrored)
                    u += length + 8; k += 1; continue
            u += 10

# the station's services (the 360 rooms) and the lifts: named rooms in the rows nearest the cross
SERVICES = [("Crew Services", "Mission Center"), ("Pilot Services", "Pilots' Lounge"), ("Cargo Inspection East", "Shipyard"),
            ("Cargo Inspection West", "Mech Dealer"), ("Transit Concourse", "Supplies"), ("Logistics & Supply", "Weapons"),
            ("Customs Processing NE", "Medical Bay"), ("Customs Processing NW", "Command")]
def nearest_cross(nm):
    c = R[nm].centroid; return min(abs(c.x - C), abs(c.y - C))
for sec, svc in SERVICES:
    cands = sorted([k for k in R if k.startswith(sec + " ")], key=lambda k: (nearest_cross(k), -R[k].area))
    if cands: R[svc] = R.pop(cands[0])
lifts = []
for sec in ("Crew Services", "Transit Concourse", "Cargo Inspection East", "Cargo Inspection West"):
    cands = sorted([k for k in R if k.startswith(sec + " ") and R[k].distance(Point(C, C)) < A_B], key=nearest_cross)
    if cands:
        nm = "Lift (%s)" % sec.split()[-1].replace("Services", "north").replace("Concourse", "south")
        R[nm] = box(*R.pop(cands[0]).bounds); lifts.append(nm)

START = (C, C - A_B)
S = Ship("station_liberty_v2", HERE, os.path.join(HERE, "..", "source.jpg"), C, R, HALLS, DOORS, start=START, center_y=C)
if __name__ == "__main__":
    bad = run(S)
    MECHW = ("Dock Pad", "Main Hub")
    kinds = {}
    for k, g in R.items():
        if k.startswith("Lift"): kinds[k] = "lift"
        elif k.startswith(MECHW) or any(k.endswith(" " + TAGWORD[t] + " " + k.split()[-1]) for t in MECH_TAGS) or k in ("Shipyard", "Mech Dealer", "Supplies", "Weapons"): kinds[k] = "mech"
        else: kinds[k] = "pilot"
    json.dump({"entry": "Dock Pad S", "C": "Main Hub (Central Customs)", "kinds": kinds}, open(os.path.join(HERE, "overrides.json"), "w"), indent=1)
    pt = lambda k: [int(R[k].representative_point().x), int(R[k].representative_point().y)]
    G = {"entry": {"room": "Dock Pad S", "at": pt("Dock Pad S")}, "locks": [], "guards": [], "wreck": [], "patrols": [], "targets": {},
         "lifts": [{"room": k, "at": pt(k)} for k in lifts], "room_guards": {k: (2 if kinds[k] == "mech" else 0) for k in R if kinds[k] != "lift"},
         "note": "Liberty Hub MAIN HUB deck v2"}
    json.dump(G, open(os.path.join(HERE, "gameplay.json"), "w"), indent=1)
    print("rooms", len(R), "pilot", sum(1 for v in kinds.values() if v == "pilot"), "mech", sum(1 for v in kinds.values() if v == "mech"),
          "angled hallway pieces", len(planlib.DIAG), "pads", [p for p in PADS])
    sys.exit(1 if bad else 0)
