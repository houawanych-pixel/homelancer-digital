#!/usr/bin/env python3
"""Veranthos Senate Station: five walkable decks measured from its own exterior model (v13.01 station rebuild).

Owner: "Replace the old Zelda-style station layouts ... built to the matching exterior silhouettes and new blueprint
concepts ... Measure the actual models ... Start with Veranthos." The blueprint picture
(HL_Unity_Veranthos-SenateStation_Hub3Level_BLUEPRINT_GENERATED_20261110_v3.png) is a ROOM-LAYOUT CONCEPT, not
geometry: the rooms it names are kept; every outline here comes from the model st3d_veranthos_senate.glb.

  python3 build_veranthos.py assets/stations3d/st3d_veranthos_senate.glb assets/stations_int [report_dir]

What is measured (and written to the report):
  - the model's size at the game's scale (STATION_WIDTH 340 m x st3d_scale 12.8 = 4352 m per model unit)
  - the hull footprint at each deck: the model as two height maps (top surface, underside); a deck may only use
    ground where the underside is below its floor and the top surface above its ceiling (floor + 18 m), joined to
    the axis, pulled in 9 m for the hull's thickness
  - the radial arms on the main deck (their directions are read from the model, not from the picture)
Decks: L3 MAIN, L2 UPPER and L4 LOWER follow the three pictured decks. L1 DOME and L5 KEEL are DESIGNED ADDITIONS
(marked "proposed"): the picture has no such floors; rooms the picture puts on its upper / lower map are moved there.
Lifts: four through-shafts on the diagonals at one radius, the same x,z on every deck. No central lift.
Not in this pass (owner): combat, quests, key locks.
Needs: numpy, opencv, trimesh.
"""
import json, sys, os
import numpy as np, cv2, trimesh

K = 340.0 * 12.8          # metres per model unit
PX = 3.0                  # metres per pixel of the working masks
N = 1500                  # mask size (4500 m square, the station in the middle)
HULL = 9.0                # m: hull thickness kept clear inside the measured footprint
WALL = 9.0                # m: wall between rooms
BODY_R = 1250.0           # m: a hole in a slab that lies wholly inside this radius is the body's own inside
ROOM_H = 18.0             # m: wall height in the game (StationInterior.WALL_H)
LIFT_R = 440.0            # m: the four shafts' distance from the axis (inside the smallest deck, outside the hub)
LIFT_A = (45, 135, 225, 315)
C = N / 2.0

def P(x, z): return (int(round(C + x / PX)), int(round(C + z / PX)))
def pol(r, a):            # a: degrees clockwise from the front (-Z), as on the map (north up)
    t = np.radians(a); return r * np.sin(t), -r * np.cos(t)

_HM = {}
def heightmaps(tri):
    """The hull as two height maps seen from above: its top surface and its underside over every 3 m square.
    Conservative: a triangle counts at its LOWEST point for the top map and its HIGHEST point for the underside."""
    if "top" in _HM: return _HM["top"], _HM["bot"]
    pts = (tri[:, :, [0, 2]] / PX + C).round().astype(np.int32)
    top = np.full((N, N), -1e9, np.float32); bot = np.full((N, N), 1e9, np.float32)
    lo = tri[:, :, 1].min(1); hi = tri[:, :, 1].max(1)
    for i in np.argsort(lo): cv2.fillPoly(top, [pts[i]], float(lo[i]))        # ascending: the highest ends on top
    for i in np.argsort(-hi): cv2.fillPoly(bot, [pts[i]], float(hi[i]))       # descending: the lowest ends on top
    _HM["top"], _HM["bot"] = top, bot
    return top, bot

def footprint(tri, y, clear=3.0):
    """Where a room with its floor at height y fits inside the hull: the hull's underside is below the floor and its
    top surface above the ceiling (floor + ROOM_H), with `clear` metres to spare each way. Only the piece joined to
    the station's axis is kept; then it is pulled in 9 m for the hull's own thickness."""
    top, bot = heightmaps(tri)
    im = ((bot < y - clear) & (top > y + ROOM_H + clear)).astype(np.uint8)
    im = cv2.morphologyEx(im, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    n, lab = cv2.connectedComponents(im, connectivity=8)
    core = (lab == lab[int(C), int(C)]).astype(np.uint8) if lab[int(C), int(C)] else np.zeros_like(im)
    k = int(round(HULL / PX))
    return cv2.erode(core, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * k + 1, 2 * k + 1))), core

class Deck:
    def __init__(self, foot):
        self.foot = foot; self.f = np.zeros((N, N), np.uint8); self.rooms = []; self.doors = []
        yy, xx = np.mgrid[0:N, 0:N]
        self.R = np.hypot(xx - C, yy - C) * PX
        self.A = (np.degrees(np.arctan2(xx - C, -(yy - C))) % 360.0)
    def band(self, r0, r1, a0=None, a1=None):
        m = (self.R >= r0) & (self.R < r1)
        if a0 is not None:
            a0 %= 360; a1 %= 360
            m &= ((self.A >= a0) & (self.A < a1)) if a0 < a1 else ((self.A >= a0) | (self.A < a1))
        return m.astype(np.uint8)
    def corridor(self, m): self.f |= (m & self.foot)
    def avenue(self, a, r0, r1, w):                       # a straight radial passage
        x0, z0 = pol(r0, a); x1, z1 = pol(r1, a)
        m = np.zeros((N, N), np.uint8); cv2.line(m, P(x0, z0), P(x1, z1), 1, int(round(w / PX)))
        self.corridor(m)
    def room(self, name, m, min_area=1800.0):
        m = (m & self.foot & (1 - cv2.dilate(self.f, np.ones((2 * int(WALL / PX) + 1,) * 2, np.uint8)))).astype(np.uint8)
        n, lab, st, _ = cv2.connectedComponentsWithStats(m, connectivity=4)
        if n < 2: return None
        i = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
        if st[i, cv2.CC_STAT_AREA] * PX * PX < min_area: return None
        m = (lab == i).astype(np.uint8)
        dm = cv2.distanceTransform(m, cv2.DIST_L2, 5); y, x = np.unravel_index(int(np.argmax(dm)), dm.shape)
        self.f |= m
        r = {"name": name, "mask": m, "at": ((x - C) * PX, (y - C) * PX), "rad": float(dm[y, x]) * PX, "doors": 0}
        self.rooms.append(r); return r
    def door(self, x, z, yaw, w=14.0, depth=None, room=None, clip=False):
        """A doorway cut through a wall at (x, z); yaw (degrees) = the direction you walk through it."""
        depth = depth or (WALL + 12.0)
        t = np.radians(yaw); d = np.array([np.sin(t), -np.cos(t)]); s = np.array([d[1], -d[0]])
        c = np.array([x, z])
        pts = [c + a * s * w / 2 + b * d * depth / 2 for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        m = np.zeros((N, N), np.uint8); cv2.fillPoly(m, [np.array([P(*p) for p in pts], np.int32)], 1)
        if clip: m &= self.foot
        elif (m & (1 - self.foot)).any(): return False
        self.f |= m
        self.doors.append({"x": round(float(x), 1), "z": round(float(z), 1), "yaw": round(float(yaw), 1), "w": w})
        if room is not None: room["doors"] += 1
        return True
    def rdoor(self, r, a, room=None, w=14.0, clip=False):  # a door through a ring wall (you walk along the radius)
        x, z = pol(r, a); return self.door(x, z, a, w, room=room, clip=clip)
    def tdoor(self, r, a, room=None, w=14.0):             # a door through a radial wall (you walk round the ring)
        x, z = pol(r, a); return self.door(x, z, a + 90, w, room=room)

# ---- room modules (owner: "You can't just use basic shapes like pie shapes ... more advanced shapes"; the reference
# deck plans he sent are separate, purpose-shaped rooms joined by short necks, inside a solid hull) ----
def _w(c, ang, u, t):     # local (u = outward along the radius, t = clockwise round the ring) -> world x,z
    a = np.radians(ang); d = np.array([np.sin(a), -np.cos(a)]); q = np.array([np.cos(a), np.sin(a)])
    return c + u * d + t * q
def _poly(m, c, ang, pts): cv2.fillPoly(m, [np.array([P(*_w(c, ang, u, t)) for u, t in pts], np.int32)], 1)
def _disc(m, c, ang, u, t, r): cv2.circle(m, P(*_w(c, ang, u, t)), max(2, int(round(r / PX))), 1, -1)
def _oct(m, c, ang, a, b, u0=0.0, t0=0.0, k=0.34):
    ch = k * min(a, b)
    _poly(m, c, ang, [(u0 + u, t0 + t) for u, t in ((-a + ch, -b), (a - ch, -b), (a, -b + ch), (a, b - ch), (a - ch, b), (-a + ch, b), (-a, b - ch), (-a, -b + ch))])

SHAPES = ("oct", "capsule", "rotunda", "bays", "apse", "cross", "hex", "twin", "keystone")
def shape(kind, c, ang, a, b):
    """One room module centred at c, turned to face along the radius `ang`; a = half-depth (radial), b = half-width."""
    m = np.zeros((N, N), np.uint8)
    if kind == "oct": _oct(m, c, ang, a, b)
    elif kind == "capsule":
        e = max(0.0, b - a); _poly(m, c, ang, [(-a, -e), (a, -e), (a, e), (-a, e)]); _disc(m, c, ang, 0, -e, a); _disc(m, c, ang, 0, e, a)
    elif kind == "rotunda":                                # a round chamber with alcoves, octagonal wings if there is width
        R = min(a, b)
        _disc(m, c, ang, 0, 0, R * 0.84)
        for k in range(6): q = np.radians(30 + 60 * k); _disc(m, c, ang, 0.8 * R * np.cos(q), 0.8 * R * np.sin(q), 0.2 * R)
        if b > 1.5 * R:
            hw = (b - R * 0.7) / 2
            for sg in (-1, 1): _oct(m, c, ang, 0.5 * a, hw, 0.0, sg * (R * 0.7 + hw))
    elif kind == "bays":                                   # a hall with a row of alcoves along its outer wall
        _oct(m, c, ang, 0.7 * a, b, -0.3 * a, 0.0, 0.25)
        n = max(2, int(b / (0.55 * a))); w = 2 * b / (2 * n + 1)
        for k in range(n):
            t = -b + w * (2 * k + 1.5); _oct(m, c, ang, 0.36 * a, w * 0.5, 0.64 * a, t, 0.4)
    elif kind == "apse":                                   # a hall that ends in a half-round
        _oct(m, c, ang, 0.5 * a, b, -0.5 * a, 0.0, 0.2)
        _poly(m, c, ang, [(a * np.sin(q), b * 0.86 * np.cos(q)) for q in np.linspace(0, np.pi, 40)])
    elif kind == "cross":
        _oct(m, c, ang, 0.62 * a, 0.62 * b); _oct(m, c, ang, a, 0.3 * b, k=0.3); _oct(m, c, ang, 0.34 * a, b, k=0.3)
    elif kind == "hex":
        e = max(0.0, b - 0.75 * a); _poly(m, c, ang, [(a, -e), (a, e), (0, b), (-a, e), (-a, -e), (0, -b)])
    elif kind == "twin":                                   # two chambers and the link between them: one room
        for sg in (-1, 1): _oct(m, c, ang, a, 0.42 * b, 0.0, sg * 0.56 * b)
        _poly(m, c, ang, [(-0.3 * a, -0.2 * b), (0.3 * a, -0.2 * b), (0.3 * a, 0.2 * b), (-0.3 * a, 0.2 * b)])
    else:                                                  # keystone: wide outside, narrow inside, cut corners
        _poly(m, c, ang, [(-a, -0.55 * b), (-a, 0.55 * b), (-0.2 * a, b), (0.7 * a, b), (a, 0.8 * b), (a, -0.8 * b), (0.7 * a, -b), (-0.2 * a, -b)])
    return m

def module(dk, name, kind, c, ang, a, b, allowed):
    """Place one module as large as fits wholly inside `allowed` (depth and width are fitted separately)."""
    best = None; no = (1 - allowed)
    for sa in (1.0, 0.9, 0.8, 0.7, 0.6, 0.5):
        for sb in (1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4):
            if best is not None and sa * sb <= best[0]: continue
            mm = shape(kind, c, ang, a * sa, b * sb)
            if not (mm & no).any(): best = (sa * sb, mm)
    if best is None: return None
    m = best[1]
    if m.sum() * PX * PX < 1500.0: return None
    dm = cv2.distanceTransform(m, cv2.DIST_L2, 5); cp = P(*c)
    dk.f |= m
    r = {"name": name, "mask": m, "at": (float(c[0]), float(c[1])), "rad": float(dm[cp[1], cp[0]]) * PX, "doors": 0, "links": set()}
    dk.rooms.append(r); return r

def neck(dk, p0, p1, r0, r1=None, w=18.0):
    """A short passage from room r0 (centre p0) to p1 (a point on a passage, or room r1's centre); one sliding door
    where it leaves r0."""
    p0 = np.array(p0, float); p1 = np.array(p1, float)
    m = np.zeros((N, N), np.uint8); cv2.line(m, P(*p0), P(*p1), 1, max(3, int(round(w / PX))))
    if (m & (1 - dk.foot)).any(): return False
    L = float(np.hypot(*(p1 - p0)));
    if L < 1: return False
    d = (p1 - p0) / L; q = None
    for k in range(int(L / 2.0)):
        pt = p0 + d * k * 2.0; px = P(*pt)
        if not r0["mask"][px[1], px[0]]: q = pt + d * 6.0; break
    if q is None: return False
    dk.f |= m
    yaw = float(np.degrees(np.arctan2(d[0], -d[1])) % 360)
    dk.doors.append({"x": round(float(q[0]), 1), "z": round(float(q[1]), 1), "yaw": round(yaw, 1), "w": w})
    r0["doors"] += 1
    if r1 is not None: r1["doors"] += 1; r0["links"].add(r1["name"]); r1["links"].add(r0["name"])
    return True

def district(dk, name, r0, r1, av0, av1, rows, seed, inner=True, outer=True, pad=24.0):
    """A district between two ring passages and two avenues (at av0 and av1 degrees): rows of separate room modules,
    each a different shape, joined by necks to the passages, to each other and across the rows. No pie slices."""
    rng = np.random.RandomState(seed)
    span = (av1 - av0) % 360
    allowed = (dk.foot & (1 - cv2.dilate(dk.f, np.ones((2 * int((WALL + 6) / PX) + 1,) * 2, np.uint8)))).astype(np.uint8)
    edges = np.linspace(r0, r1, len(rows) + 1)
    if len(rows) > 1: edges[1:-1] += rng.uniform(-0.1, 0.1, len(rows) - 1) * (r1 - r0) / len(rows)
    kinds = list(SHAPES); rng.shuffle(kinds); ki = 0
    grid = []; k = 0
    for ri, cnt in enumerate(rows):
        ra, rb = edges[ri] + 10.0, edges[ri + 1] - 10.0; rm = (ra + rb) / 2
        pd = np.degrees(pad / rm)
        cuts = (np.arange(1, cnt) / cnt + rng.uniform(-0.22, 0.22, cnt - 1) / cnt) if cnt > 1 else []
        ang = [0.0] + list(cuts) + [1.0]; row = []
        for ci in range(cnt):
            b0 = av0 + pd + ang[ci] * (span - 2 * pd); b1 = av0 + pd + ang[ci + 1] * (span - 2 * pd)
            mid = (b0 + b1) / 2; half = np.radians((b1 - b0) / 2) * rm - 10.0
            k += 1
            cell = (allowed & dk.band(ra, rb, b0, b1)).astype(np.uint8)
            kind = kinds[ki % len(kinds)]; ki += 1
            a, b = (rb - ra) / 2, max(20.0, half)
            if rb - ra < 200.0: b = min(b, 1.5 * a)          # in a thin ring a straight room cannot be long: keep it compact
            if kind in ("rotunda",) and b < a: a = b
            r = module(dk, "%s %d" % (name, k) if sum(rows) > 1 else name, kind, np.array(pol(rm, mid)), mid, a, b, cell)
            if r is not None: r["_rm"] = rm; r["_mid"] = mid; r["_kind"] = kind
            row.append(r)
        grid.append(row)
    made = [r for row in grid for r in row if r is not None]
    for ri, row in enumerate(grid):
        for ci, r in enumerate(row):
            if r is None: continue
            if ri == 0 and inner: neck(dk, r["at"], pol(r0 - WALL - 4, r["_mid"]), r)
            if ri == len(grid) - 1 and outer: neck(dk, r["at"], pol(r1 + WALL + 4, r["_mid"]), r)
            if ci + 1 < len(row) and row[ci + 1] is not None: neck(dk, r["at"], row[ci + 1]["at"], r, row[ci + 1])
            if ri > 0:
                prev = [p for p in grid[ri - 1] if p is not None]
                if prev:
                    p = min(prev, key=lambda q: abs((q["_mid"] - r["_mid"] + 180) % 360 - 180))
                    neck(dk, r["at"], p["at"], r, p)
    for r in made:                                        # no dead ends: a room with one way in gets a second, to an avenue
        if r["doors"] >= 2: continue
        for av in sorted((av0, av1), key=lambda q: abs((q - r["_mid"] + 180) % 360 - 180)):
            if neck(dk, r["at"], pol(r["_rm"], av), r): break
    return made

def _diamond(k):
    m = np.zeros((2 * k + 1, 2 * k + 1), np.uint8)
    for y in range(2 * k + 1): w = k - abs(y - k); m[y, k - w:k + w + 1] = 1
    return m

def complex_(dk, r0, r1, a0, a1, rows, G=40.0, av_half=15.0):
    """A district as ONE complex (owner's ChatGPT interior study of this deck, 10 Nov: "Arrivals & Customs" with its
    arrivals hall, screening lanes, baggage inspection and waiting lounge, and so on): a walled block between the ring,
    the promenade and two avenues, with its own corridors inside and its named rooms as walled rooms off them.
    rows: inner to outer, each (depth weight, [(name, width weight, kind), ...]); kind "sector" follows the block's
    curve with cut corners, any SHAPES name is fitted into its cell."""
    span = (a1 - a0) % 360
    D = (dk.band(r0, r1, a0, a1) & dk.foot & (1 - cv2.dilate(dk.f, np.ones((2 * int(WALL / PX) + 1,) * 2, np.uint8)))).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(D, connectivity=4)
    if n < 2: return []
    D = (lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))).astype(np.uint8)
    dk.f |= D
    kw = np.ones((2 * int(WALL / PX) + 1,) * 2, np.uint8)
    tot = sum(r[0] for r in rows); depth = (r1 - r0) - G * (len(rows) + 1); ra = r0 + G; made = []
    for wgt, cells in rows:
        rb = ra + depth * wgt / tot; rm = (ra + rb) / 2
        mg = np.degrees((av_half + WALL + G) / ra); g = np.degrees(G / rm)
        use = span - 2 * mg - g * (len(cells) - 1); tw = sum(c[1] for c in cells); b0 = a0 + mg
        for nm, cw, kind in cells:
            b1 = b0 + use * cw / tw; mid = (b0 + b1) / 2
            cell = (cv2.morphologyEx(dk.band(ra, rb, b0, b1), cv2.MORPH_OPEN, _diamond(6)) & D).astype(np.uint8)
            c = np.array(pol(rm, mid))
            if kind != "sector":
                a, b = (rb - ra) / 2, np.radians((b1 - b0) / 2) * rm; best = None; no = 1 - cell
                for sa in (1.0, 0.9, 0.8, 0.7, 0.6, 0.5):
                    for sb in (1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4):
                        if best is not None and sa * sb <= best[0]: continue
                        mm = shape(kind, c, mid, a * sa, b * sb)
                        if not (mm & no).any(): best = (sa * sb, mm)
                if best is not None: cell = best[1]
            b0 = b1 + g
            if cell.sum() * PX * PX < 1500.0: continue
            dk.f &= (1 - (cv2.dilate(cell, kw) & (1 - cell) & D))             # the room's own walls
            dm = cv2.distanceTransform(cell, cv2.DIST_L2, 5); cp = P(*c)
            r = {"name": nm, "mask": cell, "at": (float(c[0]), float(c[1])), "rad": float(dm[cp[1], cp[0]]) * PX, "doors": 0, "links": set(), "_kind": kind}
            dk.rooms.append(r); made.append(r)
            wide = np.radians(b1 - b0 + g) * rm > 1.6 * (rb - ra)
            for yaw in (mid, mid + 180) + ((mid + 90, mid - 90) if wide else ()):   # doors: to the corridors inside and outside it
                t = np.radians(yaw); d = np.array([np.sin(t), -np.cos(t)])
                for k in range(1, 400):
                    q = c + d * k * 2.0; px = P(*q)
                    if not cell[px[1], px[0]]:
                        dk.door(q[0] + d[0] * WALL / 2, q[1] + d[1] * WALL / 2, yaw, 16.0, depth=WALL + 16.0, room=r); break
        ra = rb + G
    # the complex's gates: two on the lift concourse side, three on the promenade, two on each avenue
    for fa in (0.3, 0.7): dk.rdoor(r0 - WALL / 2, a0 + span * fa, None, w=22.0)
    for fa in (0.22, 0.5, 0.78): dk.rdoor(r1 + WALL / 2, a0 + span * fa, None, w=22.0)
    for av, sg in ((a0, 1), (a1, -1)):
        for fr in (0.3, 0.72):
            rr = r0 + (r1 - r0) * fr; x, z = pol(rr, av); t = np.radians(av); q = np.array([np.cos(t), np.sin(t)]) * sg * (av_half + WALL / 2)
            dk.door(x + q[0], z + q[1], av + 90, 20.0, depth=WALL + 16.0)
    return made

def outlines(mask):
    cs, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    out = []
    for c in cs:
        if len(c) < 10: continue
        a = cv2.approxPolyDP(c, 0.6, True).reshape(-1, 2).astype(float)
        if len(a) < 3: continue
        a += 0.5; votes = 0
        for k in range(len(a)):
            p, q = a[k], a[(k + 1) % len(a)]; e = q - p; L = np.hypot(*e)
            if L < 2: continue
            m = (p + q) / 2 + np.array([e[1], -e[0]]) / L * 1.6
            x, y = int(m[0]), int(m[1])
            if 0 <= x < N and 0 <= y < N: votes += 1 if mask[y, x] else -1
        if votes < 0: a = a[::-1]
        out.append([round(float(v), 1) for v in ((a - C) * PX).reshape(-1)])
    return out

def lifts_xy(): return [[round(v, 1) for v in pol(LIFT_R, a)] for a in LIFT_A]

def scalloped(dk, r_out, n=16, big=()):
    """A round hall with a ring of alcoves (bigger ones where its doors are)."""
    m = np.zeros((N, N), np.uint8); cv2.circle(m, P(0, 0), int((r_out - 34.0) / PX), 1, -1)
    for k in range(n):
        a = 360.0 * k / n; rr = 40.0 if any(abs((a - q + 180) % 360 - 180) < 1 for q in big) else 24.0
        cv2.circle(m, P(*pol(r_out - rr, a)), int(rr / PX), 1, -1)
    return m

def ring_core(dk, hub_name, hub_r, ring=(410.0, 470.0), hub_doors=(0, 90, 180, 270)):
    """What every deck shares: the central hall, the lift concourse round it with the four shafts on it."""
    dk.corridor(dk.band(ring[0], ring[1]))
    hub = dk.room(hub_name, scalloped(dk, ring[0] - WALL, 16, hub_doors))
    for a in hub_doors: dk.rdoor(ring[0] - WALL / 2, a, hub, w=22.0)
    return hub

def build(glb, outdir, repdir=None):
    mesh = trimesh.load(glb, force="scene")
    mesh = mesh.to_geometry() if hasattr(mesh, "to_geometry") else mesh.dump(concatenate=True)
    v = np.asarray(mesh.vertices) * K; tri = v[np.asarray(mesh.faces)]
    rep = {"model": os.path.basename(glb), "metres_per_model_unit": K,
           "size_m": {"x": round(float(np.ptp(v[:, 0]))), "z": round(float(np.ptp(v[:, 2]))), "height": round(float(np.ptp(v[:, 1])))}}
    # the radial arms, read from the model: hull between 1300 and 1700 m from the axis, by direction
    cen = tri.mean(1); rr = np.hypot(cen[:, 0], cen[:, 2]); aa = np.degrees(np.arctan2(cen[:, 0], -cen[:, 2])) % 360
    h, _ = np.histogram(aa[(rr > 1300) & (rr < 1700)], bins=120, range=(0, 360))
    hs = np.convolve(np.r_[h[-2:], h, h[:2]], np.ones(3) / 3, "valid")[1:-1] if False else h.astype(float)
    arms = []; i = 0; on = hs > 0.04 * hs.max()
    start = next(j for j in range(120) if not on[j])
    for j in range(start, start + 121):
        jj = j % 120
        if on[jj] and (not arms or arms[-1][1] is not None): arms.append([jj, None, 0.0, 0.0])
        if on[jj]: arms[-1][2] += hs[jj] * (j * 3 + 1.5); arms[-1][3] += hs[jj]
        elif arms and arms[-1][1] is None: arms[-1][1] = jj
    arm_dirs = sorted(round((a[2] / a[3]) % 360, 1) for a in arms if a[3] > 0)
    rep["arms"] = {"count": len(arm_dirs), "directions_deg_clockwise_from_front": arm_dirs, "blueprint_picture_shows": 10}
    # Floor heights (m, from the model's centre), chosen from the measured top and underside of the hull:
    # the wide disc is only about 130 m thick at its rim (top about -130 m, underside -259 m), so the two full-width
    # decks (MAIN, LOWER) both sit inside it; UPPER and DOME are in the drum and dome above, KEEL in the plug below.
    LEVELS = [("L1", "DOME DECK", 340.0 / K, True), ("L2", "UPPER DECK", 100.0 / K, False), ("L3", "MAIN DECK", -185.0 / K, False),
              ("L4", "LOWER DECK", -235.0 / K, False), ("L5", "KEEL DECK", -340.0 / K, True)]
    decks = []; levels_out = []
    for lid, lname, ym, proposed in LEVELS:
        # the hull must hold the room at floor height AND at ceiling height (a thin cut at each, both must cover it)
        mfoot, raw = footprint(tri, ym * K)
        tmp = Deck(mfoot)
        Rin = float(tmp.R[mfoot == 0].min()) if (mfoot == 0).any() else 9999.0  # the biggest circle about the axis inside the hull
        # Owner: "fix those outer silhouette ... looks like a scribble and needs to be connected ... cylinders, the right
        # shape, the right squares. The right line work." So the deck's edge is CLEAN geometry fitted to the measurement:
        # the body is the largest circle that fits inside the measured hull; each arm the model has is a straight
        # spoke to a cleanly shaped pod at the measured direction and distance. (Where an arm on the model is thinner
        # than the spoke, the deck is wider than the model there: counted in the report.)
        foot = (tmp.R < Rin).astype(np.uint8)
        arm_parts = []
        ports = []
        if lid == "L3":
            beyond = (mfoot & (tmp.R > Rin + 14).astype(np.uint8))
            names = {0: "North Docking Bay", 180: "South Docking Bay", 90: "East Hangar Approach", 270: "West Hangar Approach"}
            pod_kinds = ("rotunda", "oct", "capsule")
            for ai, a_arm in enumerate(arm_dirs):
                near = min(names, key=lambda q: abs((a_arm - q + 180) % 360 - 180))
                cardinal = abs((a_arm - near + 180) % 360 - 180) < 8
                nm = names[near] if cardinal else "Docking Arm %03d" % int(round(a_arm))
                dev = np.abs((tmp.A - a_arm + 180) % 360 - 180)
                pod = (beyond & (dev < 7) & (tmp.R > 1500)).astype(np.uint8)
                if pod.sum() == 0: arm_parts.append({"name": nm, "a": a_arm, "built": False}); continue
                ys, xs = np.nonzero(pod); rr_ = tmp.R[ys, xs]
                a_true = float(np.degrees(np.arctan2((xs - C).mean(), -(ys - C).mean())) % 360)
                r_far = float(np.percentile(rr_, 97)); wid = float(cv2.distanceTransform(pod, cv2.DIST_L2, 5).max()) * PX
                size = float(np.clip(wid * 1.5, 80.0, 125.0)); r_pod = r_far - size
                c = np.array(pol(r_pod, a_true))
                pm = shape("cross" if cardinal else pod_kinds[ai % 3], c, a_true, size, size * (1.5 if cardinal else 0.8))
                sp = np.zeros((N, N), np.uint8); cv2.line(sp, P(*pol(Rin - 12, a_true)), P(*c), 1, int(round(36.0 / PX)))
                node = shape("oct", np.array(pol((Rin + r_pod) / 2, a_true)), a_true, 34.0, 34.0)   # a junction halfway out
                # docking ports along the spoke (owner: "multiple ships can dock on there at once to load unload"):
                # airlock bays on both sides, a quarter and three quarters of the way out
                for fr in (0.27, 0.73):
                    rr_p = Rin + (r_pod - size - Rin) * fr
                    for sg in (-1, 1):
                        pc = _w(np.array(pol(rr_p, a_true)), a_true, 0.0, sg * 38.0)
                        node |= shape("oct", pc, a_true, 30.0, 24.0)
                        ports.append({"x": round(float(pc[0]), 1), "z": round(float(pc[1]), 1), "arm": nm, "side": "cw" if sg > 0 else "ccw"})
                foot |= pm | sp | node
                arm_parts.append({"name": nm, "a": a_true, "built": True, "pod": pm, "spoke": sp | node, "c": c, "r_pod": r_pod,
                                  "model_arm_inside_width_m": round(2 * float(cv2.distanceTransform((beyond & (dev < 4) & (tmp.R < Rin + 200)).astype(np.uint8), cv2.DIST_L2, 5).max()) * PX, 1)})
        dk = Deck(foot)
        if lid == "L3":
            ring_core(dk, "Central Public Hub / Senate Rotunda", 380.0, hub_doors=(0, 45, 90, 135, 180, 225, 270, 315))
            Rp0 = Rin - 64.0                                    # the promenade round the rim
            dk.corridor(dk.band(Rp0, Rin))
            spans = [("Customs / Arrivals", 336, 22, (2, 3)), ("Medbay", 22, 62, (2, 2)), ("Mission Center", 62, 108, (1, 2)),
                     ("Security Post", 108, 172, (2, 2)), ("Escape Pod", 172, 187, (1,)), ("Cantina / Lounge", 187, 244, (2, 3)),
                     ("Embassy Row", 244, 292, (3, 2)), ("Market / Shops", 292, 336, (3, 4))]
            # Room names inside each complex are the working labels on the owner's ChatGPT interior study (not canon).
            sec = "sector"
            COMPLEX = {
                "Customs / Arrivals": [(1.0, [("Waiting Lounge", 1, "apse")]), (2.2, [("Arrivals Hall", 1, sec), ("Screening Lanes", 1.5, "bays"), ("Baggage Inspection", 1, sec)])],
                "Medbay": [(1.0, [("Pharmacy", 1, "oct")]), (1.2, [("Ward A", 1, sec), ("Ward B", 1, sec)]), (1.2, [("Triage", 1, "keystone"), ("Treatment", 1, sec)])],
                "Mission Center": [(1.0, [("Briefing Room A", 1, "oct"), ("Briefing Room B", 1, "oct")]), (1.3, [("Terminal Hall", 1, "bays")])],
                "Security Post": [(1.0, [("Security Reception", 1, "apse")]), (1.2, [("Interview Rooms", 1, "oct"), ("Holding Cells", 1.3, "bays")]), (1.2, [("Equipment Lockers", 1, sec)])],
                "Cantina / Lounge": [(1.0, [("Lounge Booths 1", 1, sec), ("Lounge Booths 2", 1, sec)]), (1.6, [("Cantina Bar", 1, "capsule")]), (1.0, [("Lounge Booths 3", 1, sec), ("Lounge Booths 4", 1, "hex"), ("Lounge Booths 5", 1, sec)])],
                "Embassy Row": [(1.0, [("Embassy Reception", 1, "apse")]), (1.3, [("Embassy Conference Hall", 1.4, "oct"), ("Embassy Suite 1", 1, sec)]), (1.2, [("Embassy Suite 2", 1, sec), ("Embassy Suite 3", 1, "keystone"), ("Embassy Suite 4", 1, sec)])],
                "Market / Shops": [(1.0, [("Market Stall %d" % k, 1, sec) for k in (1, 2)]), (1.0, [("Market Stall %d" % k, 1, ("oct" if k == 4 else sec)) for k in (3, 4, 5)]),
                                   (1.0, [("Market Stall %d" % k, 1, sec) for k in (6, 7, 8, 9)]), (1.0, [("Market Stall %d" % k, 1, ("hex" if k == 12 else sec)) for k in (10, 11, 12, 13, 14)])],
            }
            for a in sorted({s_[1] for s_ in spans}): dk.avenue(a, 470.0, Rp0, 30.0)   # avenues between the districts
            for si, (nm, a0, a1, rows) in enumerate(spans):
                if nm == "Escape Pod": district(dk, nm, Rp0 - WALL - 230.0, Rp0 - WALL, a0, a1, rows, 11 + si, inner=False)   # at the rim, where a pod can leave
                else: complex_(dk, 470.0 + WALL, Rp0 - WALL, a0, a1, COMPLEX[nm])
            got = []
            for ap in arm_parts:
                if not ap["built"]: got.append({"name": ap["name"], "direction_deg": round(ap["a"], 1), "built": False}); continue
                dk.f |= ap["spoke"] | ap["pod"]
                dm = cv2.distanceTransform(ap["pod"], cv2.DIST_L2, 5); cp = P(*ap["c"])
                r = {"name": ap["name"], "mask": ap["pod"], "at": (float(ap["c"][0]), float(ap["c"][1])), "rad": float(dm[cp[1], cp[0]]) * PX, "doors": 1, "links": set()}
                dk.rooms.append(r)
                x, z = pol(Rin + 14, ap["a"])                   # the gate where the arm leaves the promenade
                dk.doors.append({"x": round(float(x), 1), "z": round(float(z), 1), "yaw": round(ap["a"], 1), "w": 36.0})
                got.append({"name": ap["name"], "direction_deg": round(ap["a"], 1), "built": True, "pod_centre_from_axis_m": round(ap["r_pod"]),
                            "model_arm_inside_width_m": ap["model_arm_inside_width_m"], "spoke_width_m": 36.0})
            rep["main_deck_arms_built"] = got
        elif lid == "L2":
            ring_core(dk, "Senate Chamber", 380.0)
            Ro = Rin - 6
            spans = [("Delegate Offices (north)", 330, 30, (2,)), ("Delegate Offices", 30, 140, (4,)), ("Officer Quarters", 140, 250, (4,)), ("Command / Comms", 250, 330, (3,))]
            for a in (330, 30, 140, 250): dk.avenue(a, 470.0, Ro - 20, 24.0)
            sec = "sector"
            L2C = {"Delegate Offices (north)": [(1, [("Delegate Office 1", 1, sec), ("Delegate Office 2", 1, "oct")])],
                   "Delegate Offices": [(1, [("Delegate Office 3", 1, sec), ("Delegate Office 4", 1, "apse"), ("Delegate Office 5", 1, sec), ("Delegate Office 6", 1, "oct")])],
                   "Officer Quarters": [(1, [("Officer Quarters 1", 1, sec), ("Officer Quarters 2", 1, "oct"), ("Officer Quarters 3", 1, sec), ("Officer Quarters 4", 1, "keystone")])],
                   "Command / Comms": [(1, [("Command Center", 1.4, "bays"), ("Comms Room", 1, sec)])]}
            for si, (nm, a0, a1, rows) in enumerate(spans):
                complex_(dk, 470.0 + WALL, Ro, a0, a1, L2C[nm], G=30.0, av_half=12.0)
        elif lid == "L1":
            dk.corridor(dk.band(410.0, min(470.0, Rin)))
            arch = dk.room("Archives / Records", scalloped(dk, 200.0, 12, (60, 240)))
            gm = dk.band(214.0 + WALL, 372.0)                   # the gallery: a ring hall with viewing alcoves on its outer wall
            for k_ in range(12):
                if k_ % 3: cv2.circle(gm, P(*pol(372.0, 30.0 * k_)), int(24 / PX), 1, -1)
            gal = dk.room("Observation Gallery", gm)
            for a in (0, 90, 180, 270): dk.door(*pol(390.0, a), a, 22.0, depth=44.0, room=gal)
            for a in (60, 240): dk.door(*pol(206.0, a), a, 14.0, depth=40.0, room=arch)
            if gal: gal["doors"] += 2
        elif lid == "L4":
            ring_core(dk, "Engineering", 380.0)
            Ro0 = Rin - 64.0
            dk.corridor(dk.band(Ro0, Rin - 20.0))                # the outer service ring
            spans = [("Security / Brig", 300, 60, (3, 4)), ("Life Support", 60, 180, (2, 3)), ("Maintenance", 180, 300, (4, 3))]
            for a in (300, 60, 180): dk.avenue(a, 470.0, Ro0, 30.0)
            sec = "sector"
            L4C = {"Security / Brig": [(1.0, [("Brig Processing", 1, "apse"), ("Security Office", 1, "oct")]), (1.2, [("Brig Cells A", 1, "bays"), ("Brig Cells B", 1, "bays"), ("Armory Locker", 0.8, sec)]),
                                       (1.1, [("Brig Storage %d" % k, 1, sec) for k in (1, 2, 3, 4)])],
                   "Life Support": [(1.0, [("Life Support Control", 1, "oct")]), (1.3, [("Air Plant", 1, "capsule"), ("Water Plant", 1, "capsule")]),
                                    (1.1, [("Life Support Bay %d" % k, 1, (sec if k != 2 else "hex")) for k in (1, 2, 3)])],
                   "Maintenance": [(1.0, [("Maintenance Office", 1, "oct"), ("Tool Store", 1, sec)]), (1.2, [("Workshop A", 1, "bays"), ("Workshop B", 1, sec), ("Parts Store", 1, "keystone")]),
                                   (1.1, [("Maintenance Bay %d" % k, 1, sec) for k in (1, 2, 3, 4)])]}
            for si, (nm, a0, a1, rows) in enumerate(spans):
                complex_(dk, 470.0 + WALL, Ro0 - WALL, a0, a1, L4C[nm])
        else:
            ring_core(dk, "Reactor", 380.0, hub_doors=(90, 270))
            Ro = Rin - 6
            for a in (150, 210, 330, 30): dk.avenue(a, 470.0, Ro - 20, 20.0)
            sec = "sector"
            complex_(dk, 470.0 + WALL, Ro, 210, 330, [(1, [("Cargo Hold %d" % k, 1, sec) for k in (1, 2, 3, 4)])], G=30.0, av_half=10.0)
            complex_(dk, 470.0 + WALL, Ro, 30, 150, [(1, [("Cargo Hold %d" % k, 1, sec) for k in (5, 6, 7, 8)])], G=30.0, av_half=10.0)
            complex_(dk, 470.0 + WALL, Ro, 150, 210, [(1, [("Escape Pod", 1, "capsule"), ("Coolant Store", 1, sec)])], G=30.0, av_half=10.0)
            complex_(dk, 470.0 + WALL, Ro, 330, 30, [(1, [("Reactor Control", 1.3, "bays"), ("Reactor Monitoring", 1, sec)])], G=30.0, av_half=10.0)   # (working labels: a designed addition)
        for (x, z) in lifts_xy():                                # the shafts: a lobby bay on the concourse
            m = np.zeros((N, N), np.uint8); cv2.circle(m, P(x, z), int(26 / PX), 1, -1); dk.f |= (m & foot)
        dk.f &= foot
        # keep what you can walk to from the first lift (a person 1.5 m wide: shrink the floor a pixel)
        er = cv2.erode(dk.f, np.ones((3, 3), np.uint8))
        _, lab = cv2.connectedComponents(er, connectivity=4)
        lx = [P(x, z) for x, z in lifts_xy()]
        s0 = lab[lx[0][1], lx[0][0]]
        live = cv2.dilate((lab == s0).astype(np.uint8), np.ones((5, 5), np.uint8)) if s0 else np.zeros_like(dk.f)
        cut = [r["name"] for r in dk.rooms if not live[int(C + r["at"][1] / PX), int(C + r["at"][0] / PX)]]
        dk.f &= live
        dk.rooms = [r for r in dk.rooms if r["name"] not in cut]
        outside = int((dk.f & (1 - raw)).sum())
        lifts_ok = [bool(s0 and lab[p[1], p[0]] == s0) for p in lx]
        one_door = sorted(r["name"] for r in dk.rooms if r["doors"] < 2)
        shapes_used = sorted({r.get("_kind", "") for r in dk.rooms} - {""})
        rep[lid] = {"name": lname, "height_m": round(ym * K), "proposed_addition": proposed, "hull_inscribed_radius_m": round(Rin),
                    "floor_area_km2": round(float(dk.f.sum()) * PX * PX / 1e6, 3), "floor_outside_measured_hull_px": outside,
                    "rooms": len(dk.rooms), "doors": len(dk.doors), "rooms_dropped_unreachable": cut,
                    "lifts_on_walkable_floor": lifts_ok, "one_door_rooms": one_door, "room_shapes": shapes_used,
                    "floor_outside_measured_hull_m2": round(outside * PX * PX)}
        decks.append((lid, lname, ym, proposed, dk, raw))
        # the deck map (north up = the docking front), the measured hull behind the rooms
        hullm = cv2.dilate(foot, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13, 13)))   # the clean hull line: the deck's edge plus the hull's thickness
        im = np.zeros((N, N, 3), np.uint8); im[:] = (40, 16, 8); im[hullm > 0] = (62, 30, 12); im[dk.f > 0] = (110, 62, 20)
        cs, _ = cv2.findContours(hullm, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE); cv2.drawContours(im, cs, -1, (200, 150, 60), 2, cv2.LINE_AA)
        cs, _ = cv2.findContours(dk.f, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE); cv2.drawContours(im, cs, -1, (255, 230, 90), 1, cv2.LINE_AA)
        for d_ in dk.doors: cv2.circle(im, P(d_["x"], d_["z"]), 3, (90, 255, 90), -1)
        for (x, z), nm in zip(lifts_xy(), ("NE", "SE", "SW", "NW")):
            p = P(x, z); cv2.rectangle(im, (p[0] - 8, p[1] - 8), (p[0] + 8, p[1] + 8), (255, 255, 255), 2)
            cv2.putText(im, "LIFT " + nm, (p[0] - 26, p[1] - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1, cv2.LINE_AA)
        for r in dk.rooms:
            t = r["name"].upper(); fs = 0.42 if r["rad"] > 60 else 0.3
            sz = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, fs, 1)[0]; p = P(*r["at"])
            cv2.putText(im, t, (p[0] - sz[0] // 2, p[1] + 4), cv2.FONT_HERSHEY_SIMPLEX, fs, (255, 255, 255), 1, cv2.LINE_AA)
        cv2.putText(im, "VERANTHOS SENATE STATION  -  %s %s" % (lid, lname), (30, 44), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 240, 170), 2, cv2.LINE_AA)
        cv2.putText(im, ("DESIGNED ADDITION - not on the blueprint picture" if proposed else "rooms from the blueprint concept") + "  |  clean outline fitted to st3d_veranthos_senate at %+d m" % round(ym * K),
                    (30, 72), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (120, 200, 255), 1, cv2.LINE_AA)
        mp = "veranthos_%s.jpg" % lid.lower()
        cv2.imwrite(os.path.join(outdir, mp), cv2.resize(im, (1024, 1024), interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 85])
        if repdir: cv2.imwrite(os.path.join(repdir, "veranthos_%s_full.jpg" % lid.lower()), im, [cv2.IMWRITE_JPEG_QUALITY, 88])
        levels_out.append({"id": lid, "name": lname, "y": round(ym * K, 1), "proposed": proposed, "map": mp,
                           "walls": outlines(dk.f), "doors": dk.doors,
                           "rooms": [{"name": r["name"], "x": round(r["at"][0], 1), "z": round(r["at"][1], 1), "rad": round(r["rad"] * 1.4, 1)} for r in dk.rooms],
                           "lifts": lifts_xy(), "ports": ports})
    # lift alignment: the same x,z on every deck, on walkable floor on every deck
    rep["lifts"] = {"shafts_xz_m": dict(zip(("NE", "SE", "SW", "NW"), lifts_xy())), "distance_from_axis_m": LIFT_R,
                    "serve": "all four shafts serve L1-L5" if all(all(rep[l[0]]["lifts_on_walkable_floor"]) for l in LEVELS) else "NOT all shafts reach every deck: see each deck"}
    out = {"id": "veranthos", "name": "Veranthos Senate Station", "model": "st3d_veranthos_senate", "system": "veranthos",
           "extent_m": N * PX, "start": {"level": "L3", "x": lifts_xy()[2][0] + 30.0, "z": lifts_xy()[2][1]},
           "note": "Outlines measured from the exterior model. Rooms follow the blueprint concept on L2-L4; L1 and L5 are designed additions. No combat, quests or key locks in this pass.",
           "levels": levels_out}
    json.dump(out, open(os.path.join(outdir, "veranthos.json"), "w"), separators=(",", ":"))
    if repdir:
        json.dump(rep, open(os.path.join(repdir, "veranthos_report.json"), "w"), indent=1)
        # side view: the model's profile with the five deck floors (their real width at that height) drawn on it
        S = 0.25; W_ = 1200; H_ = 700
        im = np.zeros((H_, W_, 3), np.uint8); im[:] = (40, 16, 8)
        pts = np.stack([v[:, 0] * S + W_ / 2, -v[:, 1] * S + H_ / 2], 1)
        cv2.fillPoly(im, list(pts[np.asarray(mesh.faces)].round().astype(np.int32)), (120, 80, 40))
        for lid, lname, ym, proposed, dk, raw in decks:
            xs = np.nonzero(dk.f.any(axis=0))[0]; x0, x1 = (xs.min() - C) * PX, (xs.max() - C) * PX
            y = int(-ym * K * S + H_ / 2)
            cv2.line(im, (int(x0 * S + W_ / 2), y), (int(x1 * S + W_ / 2), y), (90, 255, 255) if not proposed else (90, 160, 255), 3)
            cv2.putText(im, "%s %s  %+d m" % (lid, lname, round(ym * K)), (20, y + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1, cv2.LINE_AA)
        for a in LIFT_A:
            x = pol(LIFT_R, a)[0]
            cv2.line(im, (int(x * S + W_ / 2), int(340.0 * S + H_ / 2)), (int(x * S + W_ / 2), int(-340.0 * S + H_ / 2)), (255, 255, 255), 1)
        cv2.putText(im, "SIDE VIEW (from the front): st3d_veranthos_senate at game scale, deck floors and lift shafts", (20, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 240, 170), 1, cv2.LINE_AA)
        cv2.imwrite(os.path.join(repdir, "veranthos_side.jpg"), im, [cv2.IMWRITE_JPEG_QUALITY, 88])
    print(json.dumps(rep, indent=1))

if __name__ == "__main__":
    build(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
