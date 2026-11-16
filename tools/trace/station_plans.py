#!/usr/bin/env python3
"""v13.166 (owner, Nov 15 2026: "build the space stations like the spaceships: take the silhouette and build out a plan
for it ... five floors ... an extra key lock, purple ... mechs go a certain way and pilots a certain way ... the main
hub lets you travel quickly where you need to go ... build them all first, I'll mark them later, with my approval").

PROPOSED plans only: nothing here goes into the game until the owner approves a station.

For every station model in the game (Data.STATION3D + Data.RETOPO_STATIONS):
  1. SILHOUETTE: the model is cut into thin horizontal slices; each deck's outline is that slice seen from above
     (the hull at that height), cleaned and straightened.
  2. FIVE DECKS, bottom to top: HANGAR, ENGINEERING, MAIN HUB (the widest slice), HABITAT, COMMAND.
  3. LAYOUT (the same formula on every station, shaped by its own outline): a round MAIN HUB in the middle (you
     start there when you dock; FAST TRAVEL from it), a ring corridor round it where it fits, spokes out to the
     station's arms (the outline's longest reaches), and rooms in the sectors between them.
  4. MECH / PILOT: the hub, ring, spokes and the big rooms are mech size (red); the small rooms are pilot-only behind
     narrow doors (blue).
  5. KEYS: green (open), YELLOW, ORANGE, RED and PURPLE (the station's deepest rooms: the commander, the vault).
     Deeper decks and rooms further from the hub take higher keys.
Writes tools/trace/stations/<model>/: plan.json (outlines and rooms in metres), plan.jpg (the five decks).
usage: python3 -I tools/trace/station_plans.py [model ...]   (no args: every station in stations.json)"""
import json, math, os, sys
import numpy as np, cv2, trimesh
from shapely.geometry import Polygon, MultiPolygon, Point, LineString, box
from shapely.ops import unary_union, nearest_points
from shapely import affinity

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "stations")
N = 640                 # raster px across the model's widest extent
NB = 48                 # horizontal slices
KEY_COL = {0: (90, 220, 90), 1: (40, 230, 255), 2: (20, 150, 255), 3: (50, 50, 240), 4: (230, 80, 200)}   # BGR
KEY_NAME = {0: "OPEN", 1: "YELLOW", 2: "ORANGE", 3: "RED", 4: "PURPLE"}
STYLE_W = {"Capital": 1600.0, "Trade": 1300.0, "Military": 1150.0, "Outpost": 900.0}   # m across (the game's station scale)
ST3D_W = {"st3d_aurelion_citadel": 1600.0, "st3d_veranthos_senate": 1600.0, "st3d_veranthos_summit": 1600.0}

# (name, kind, key, sign) - sign: the station page a walk-up sign opens ("" = none)
ROLES = {
    "HANGAR": [("Hangar Bay A", "mech", 0, ""), ("Hangar Bay B", "mech", 1, ""), ("Cargo Hold", "mech", 1, ""),
               ("Mech Workshop", "mech", 0, ""), ("Fuel Depot", "mech", 2, ""), ("Freight Office", "pilot", 1, ""),
               ("Flight Control", "pilot", 2, ""), ("Pilot Ready Room", "pilot", 0, ""), ("Parts Store", "pilot", 1, "")],
    "ENGINEERING": [("Reactor", "mech", 2, ""), ("Coolant Plant", "mech", 1, ""), ("Power Relay", "mech", 2, ""),
                    ("Maintenance Bay", "mech", 1, ""), ("Engineering Control", "pilot", 2, ""), ("Life Support", "pilot", 1, ""),
                    ("Water Recycling", "pilot", 1, ""), ("Tool Crib", "pilot", 1, ""), ("Crawlspace", "pilot", 2, "")],
    "MAIN HUB": [("Docking Concourse", "mech", 0, "launch"), ("Shipyard", "mech", 0, "ships"), ("Mech Dealer", "mech", 0, "mechs"),
                 ("Pilots' Lounge", "pilot", 0, "lounge"), ("Mission Center", "pilot", 0, "missions"), ("Weapons", "pilot", 0, "equipment"),
                 ("Supplies", "pilot", 0, "supplies"), ("Medical Bay", "pilot", 0, "repair"), ("Security Office", "pilot", 1, ""),
                 ("Customs", "pilot", 0, ""), ("Market Stalls", "pilot", 0, "")],
    "HABITAT": [("Mess Hall", "mech", 0, ""), ("Hydroponics", "mech", 1, ""), ("Private Quarters", "pilot", 1, "quarters"),
                ("Crew Cabins", "pilot", 1, ""), ("Gym", "pilot", 0, ""), ("Brig", "pilot", 2, ""), ("Chapel", "pilot", 0, ""),
                ("Officers' Cabins", "pilot", 2, ""), ("Laundry", "pilot", 1, "")],
    "COMMAND": [("Command", "pilot", 3, "command"), ("Commander's Office", "pilot", 4, ""), ("Vault", "mech", 4, ""),
                ("Armory", "mech", 3, ""), ("Comms Array", "pilot", 3, ""), ("Observation Deck", "pilot", 2, ""),
                ("Data Core", "pilot", 4, ""), ("Briefing Room", "pilot", 3, "")],
}
DECKS = ["HANGAR", "ENGINEERING", "MAIN HUB", "HABITAT", "COMMAND"]
DECK_KEY = {"HANGAR": 1, "ENGINEERING": 2, "MAIN HUB": 0, "HABITAT": 1, "COMMAND": 3}   # the filler rooms' key
FILL = {"mech": ["Storage Bay", "Loading Dock", "Service Bay"], "pilot": ["Office", "Storeroom", "Crew Room", "Lounge", "Workroom"]}


# ---------------------------------------------------------------- silhouette slices
def _proj(v, lo, hi, s, a, b, flip=False):
    P = np.zeros((len(v), 2), np.int32)
    P[:, 0] = ((v[:, a] - (lo[a] + hi[a]) / 2) / s * (N - 40) + N / 2).astype(np.int32)
    yb = (v[:, b] - (lo[b] + hi[b]) / 2) / s * (N - 40)
    P[:, 1] = (N / 2 - yb if flip else N / 2 + yb).astype(np.int32)
    return P


def slices(path):
    """Each deck's floor plan at a height h: the columns (seen from above) where the hull spans h (its lowest surface
    below h and its highest above). Two depth maps, one pass each over the triangles.
    A station that stands upright (its front view much bigger than its top view: a wheel on edge) is cut front to
    back instead, its decks laid in the plane of that front view."""
    m = trimesh.load(path, force="scene").to_geometry()
    v, F = m.vertices, m.faces
    lo, hi = v.min(0), v.max(0)
    def area(a, b):
        sc = max(hi[a] - lo[a], hi[b] - lo[b])
        img = np.zeros((200, 200), np.uint8)
        P = ((v[:, [a, b]] - lo[[a, b]]) / sc * 190 + 5).astype(np.int32)
        for t in F: cv2.fillConvexPoly(img, P[t], 255)
        return float((img > 0).sum()) * ((hi[a] - lo[a]) * (hi[b] - lo[b])) / (sc * sc)
    upright = area(0, 1) > 1.6 * area(0, 2)
    a, b, d = (0, 1, 2) if upright else (0, 2, 1)
    s = max(hi[a] - lo[a], hi[b] - lo[b])
    P = _proj(v, lo, hi, s, a, b, flip=upright)
    H = hi[d] - lo[d]
    q = lambda y: (1 + (y - lo[d]) / H * 60000).astype(np.int64)
    ty = v[:, d][F]
    tmax = q(ty.max(1)); tmin = q(ty.min(1))
    ymax = np.zeros((N, N), np.uint16)
    for t in np.argsort(tmax):
        cv2.fillConvexPoly(ymax, P[F[t]], int(tmax[t]))
    ymin = np.full((N, N), 65535, np.uint16)
    for t in np.argsort(-tmin):
        cv2.fillConvexPoly(ymin, P[F[t]], int(tmin[t]))
    cover = ymax > 0
    masks = []
    for i in range(NB):
        h = 1 + (i + 0.5) / NB * 60000
        masks.append(np.where(cover & (ymin <= h) & (ymax >= h), 255, 0).astype(np.uint8))
    top = np.where(cover, 255, 0).astype(np.uint8)
    # the side view (the cut direction up the picture), for the sheet
    sa, sb = (0, 2) if upright else (0, 1)
    ss = max(hi[sa] - lo[sa], hi[sb] - lo[sb], s)
    Q = _proj(v, lo, hi, ss, sa, sb, flip=True)
    side = np.zeros((N, N), np.uint8)
    for t in range(len(F)): cv2.fillConvexPoly(side, Q[F[t]], 255)
    return masks, top, side, (lo, hi, ss, d, upright)


def clean(mask):
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    m = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, k)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m, 8)
    if n <= 1: return m * 0
    big = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    m = np.where(lab == big, 255, 0).astype(np.uint8)
    # small holes are part of the floor; big ones (open courts) stay
    inv = 255 - m
    n2, lab2, st2, _ = cv2.connectedComponentsWithStats(inv, 4)
    for i in range(1, n2):
        x, y, w, h, a = st2[i]
        if x > 0 and y > 0 and x + w < N and y + h < N and a < 0.02 * N * N: m[lab2 == i] = 255
    return m


def outline(mask):
    cs, hier = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    if not cs: return None
    shell = None
    holes = []
    for i, c in enumerate(cs):
        a = cv2.approxPolyDP(c, 3.0, True)[:, 0, :]
        if len(a) < 3: continue
        if hier[0][i][3] == -1:
            if shell is None or cv2.contourArea(c) > cv2.contourArea(shell[1]): shell = (a, c)
        else: holes.append(a)
    if shell is None: return None
    p = Polygon(shell[0], [h for h in holes if Polygon(h).area > 400]).buffer(0)
    if isinstance(p, MultiPolygon): p = max(p.geoms, key=lambda g: g.area)
    return p


def pick_decks(masks):
    area = np.array([float((m > 0).sum()) for m in masks])
    sm = np.convolve(area, np.ones(3) / 3, mode="same")
    hub = int(np.argmax(sm))
    ok = np.where(sm >= 0.3 * sm.max())[0]
    L, U = int(ok.min()), int(ok.max())
    d1 = max(1, (hub - L) // 2) if hub > L else 0
    d2 = max(1, (U - hub) // 2) if U > hub else 0
    idx = [max(L, hub - 2 * d1), max(L, hub - d1), hub, min(U, hub + d2), min(U, hub + 2 * d2)]
    return idx, sm


def deck_mask(masks, i):
    return clean(masks[i])


# ---------------------------------------------------------------- the layout formula
def sector(c, r0, r1, a0, a1, n=24):
    pts = [(c[0] + r1 * math.cos(a0 + (a1 - a0) * i / n), c[1] + r1 * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]
    pts += [(c[0] + r0 * math.cos(a1 - (a1 - a0) * i / n), c[1] + r0 * math.sin(a1 - (a1 - a0) * i / n)) for i in range(n + 1)]
    return Polygon(pts).buffer(0)


def reach(inner, c, a, rmax):
    r = 0.0
    step = 3.0
    while r < rmax:
        if not inner.contains(Point(c[0] + (r + step) * math.cos(a), c[1] + (r + step) * math.sin(a))): break
        r += step
    return r


def parts(g):
    if g.is_empty: return []
    return list(g.geoms) if hasattr(g, "geoms") else [g]


def layout(poly, c, role, hubR, W, T):
    """poly: the deck outline (px). c: the lift axis. Returns halls, rooms (slots), lifts, notes."""
    inner = poly.buffer(-T * 1.5)
    if inner.is_empty: return None
    if not inner.contains(Point(c)):
        rl = ring_layout(inner, c, role, hubR, W, T)   # a ring-shaped deck round the lift axis: the corridor runs round it
        if rl is not None: return rl
    if not inner.contains(Point(c)):   # (the lift still goes through the middle; the deck's own core sits nearest it)
        p2 = nearest_points(inner.buffer(-hubR * 0.6) if not inner.buffer(-hubR * 0.6).is_empty else inner, Point(c))[0]
        c = (p2.x, p2.y)
    A = [i * math.pi / 36 for i in range(72)]
    R = [reach(inner, c, a, N) for a in A]
    Rmed = float(np.median(R))
    core_r = hubR if role == "MAIN HUB" else hubR * 0.62
    core_r = min(core_r, max(14.0, 0.3 * Rmed))   # (a small deck: a small core, narrower halls)
    W = min(W, max(12.0, 0.14 * Rmed))
    core = Point(c).buffer(core_r, 48).intersection(inner)
    # spokes: the outline's longest reaches (its arms), at least 30 degrees apart
    order = sorted(range(72), key=lambda i: -R[i])
    sp = []
    for i in order:
        if R[i] < core_r + W * 1.5: break
        if all(min(abs(i - j), 72 - abs(i - j)) >= 6 for j in sp): sp.append(i)
        if len(sp) >= 12: break
    for i in (0, 18, 36, 54):   # (at least the four main ways)
        if len(sp) >= 4: break
        if all(min(abs(i - j), 72 - abs(i - j)) >= 6 for j in sp) and R[i] > core_r + W * 2: sp.append(i)
    rr = core_r + max(W * 3.2, 0.36 * (Rmed - core_r))
    ring = Point(c).buffer(rr + W / 2, 96).difference(Point(c).buffer(rr - W / 2, 96))
    ring_in = ring.intersection(inner)
    ring_ok = ring_in.area > 0.7 * ring.area and rr + W < Rmed * 0.95
    def halls_of(nsp, with_ring):
        pick = sorted(sp[:nsp])
        hs, spk = [core], []
        for i in pick:
            a = A[i]
            L = LineString([c, (c[0] + (R[i] - T) * math.cos(a), c[1] + (R[i] - T) * math.sin(a))])
            g = L.buffer(W / 2, cap_style=2, join_style=2).intersection(inner)
            g = max(parts(g), key=lambda q: q.area) if parts(g) else g
            spk.append((a, R[i], g))
            hs.append(g)
        if with_ring: hs.append(ring_in)
        H = unary_union(hs)
        H = max(parts(H), key=lambda q: q.area) if len(parts(H)) > 1 else H
        return H, spk
    # the halls may take at most about half the deck: fewer spokes, then no ring, on a small deck
    best = None
    for nsp, wr in [(len(sp), ring_ok), (min(len(sp), 8), ring_ok), (min(len(sp), 6), ring_ok), (min(len(sp), 4), ring_ok),
                    (min(len(sp), 6), False), (min(len(sp), 4), False), (min(len(sp), 3), False), (min(len(sp), 2), False)]:
        H, spokes = halls_of(nsp, wr)
        free = 1.0 - H.buffer(T * 1.2).intersection(inner).area / max(inner.area, 1)
        if best is None or free > best[0] + 0.02: best = (free, H, spokes, wr)
        if free >= 0.5: break
    _, H, spokes, has_ring = best
    # rooms: the sectors between spokes, inside the ring and outside it
    zone = inner.difference(H.buffer(T * 1.2))
    angs = [s[0] for s in spokes]
    if len(angs) < 3: angs = sorted(set(angs + [i * math.pi / 3 + 0.3 for i in range(6)]))   # (no arms to follow: six sectors round the core)
    slots = []
    bands = [(core_r + T, rr - W / 2 - T), (rr + W / 2 + T, N)] if has_ring else [(core_r + T, N)]
    target = max(48.0, min(110.0, 0.32 * Rmed))   # px: a room's width along the arc
    for k in range(len(angs)):
        a0 = angs[k]
        a1 = angs[(k + 1) % len(angs)] + (2 * math.pi if k + 1 == len(angs) else 0)
        if a1 <= a0: a1 += 2 * math.pi
        for (r0, r1) in bands:
            if r1 - r0 < W: continue
            rmid = r0 + min(r1 - r0, Rmed) * 0.5
            n_ang = max(1, int(round((a1 - a0) * rmid / target)))
            depth = min(r1, max(R) + 10) - r0
            n_rad = 2 if depth > target * 2.2 else 1
            for ia in range(n_ang):
                b0 = a0 + (a1 - a0) * ia / n_ang
                b1 = a0 + (a1 - a0) * (ia + 1) / n_ang
                edges = [r0 + (min(r1, max(R) + 10) - r0) * j / n_rad for j in range(n_rad + 1)]
                if n_rad == 1: edges[-1] = r1
                for ir in range(n_rad):
                    cell = sector(c, edges[ir], edges[ir + 1], b0, b1).intersection(zone)
                    for p in parts(cell):
                        p = p.buffer(-T / 2, join_style=2).buffer(0)   # (a wall between neighbours)
                        for q in parts(p):
                            if q.area < 0.35 * target * target * 0.5: continue
                            q = q.simplify(1.5)
                            mrr = q.minimum_rotated_rectangle
                            if q.area / max(mrr.area, 1) < 0.28: continue   # (slivers)
                            slots.append(q)
    lifts = [("Main Lift", Point(c).buffer(core_r * 0.22, 16))]
    if has_ring and len(spokes) >= 2:
        s0 = spokes[0][0]
        s1 = min(spokes[1:], key=lambda s: abs(abs((s[0] - s0 + math.pi) % (2 * math.pi) - math.pi) - math.pi))[0]
        for nm, a in (("Freight Lift", s0), ("Freight Lift", s1)):
            p = (c[0] + rr * math.cos(a), c[1] + rr * math.sin(a))
            lifts.append((nm, box(p[0] - W * 0.4, p[1] - W * 0.4, p[0] + W * 0.4, p[1] + W * 0.4)))
    return {"c": c, "halls": H, "slots": slots, "lifts": lifts, "ring": has_ring, "spokes": len(spokes), "core_r": core_r}


def ring_layout(inner, c, role, hubR, W, T):
    """A deck that is a ring (or a band) round the station's axis: one corridor round its middle, rooms either side."""
    A = [i * math.pi / 36 for i in range(72)]
    mids, ok = [], 0
    for a in A:
        r, rin, rout = 0.0, None, None
        while r < N:
            inside = inner.contains(Point(c[0] + r * math.cos(a), c[1] + r * math.sin(a)))
            if inside and rin is None: rin = r
            if not inside and rin is not None:
                rout = r
                break
            r += 3.0
        if rin is not None and rout is not None and rout - rin > W * 1.5:
            ok += 1
            mids.append((rin + rout) / 2)
    if ok < 40: return None
    rm = float(np.median(mids))
    H = Point(c).buffer(rm + W / 2, 128).difference(Point(c).buffer(rm - W / 2, 128)).intersection(inner)
    if H.is_empty: return None
    zone = inner.difference(H.buffer(T * 1.2))
    target = max(70.0, 0.32 * rm)
    n = max(6, int(round(2 * math.pi * rm / target)))
    slots = []
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        for (r0, r1) in ((0, rm), (rm, N)):
            cell = sector(c, r0, r1, a0, a1).intersection(zone)
            for p in parts(cell):
                p = p.buffer(-T / 2, join_style=2).buffer(0)
                for q in parts(p):
                    if q.area < 0.2 * target * target: continue
                    mrr = q.minimum_rotated_rectangle
                    if q.area / max(mrr.area, 1) < 0.35: continue
                    slots.append(q.simplify(1.5))
    a = math.pi / 2   # the lift lobby: on the ring, front side
    lp = (c[0] + rm * math.cos(a), c[1] + rm * math.sin(a))
    lp = nearest_points(H, Point(lp))[0]
    lifts = [("Lift", Point(lp.x, lp.y).buffer(W * 0.45, 16)), ("Lift", Point(c[0] - (lp.x - c[0]), c[1] - (lp.y - c[1])).buffer(W * 0.45, 16).intersection(H.buffer(W)))]
    lifts = [l for l in lifts if not l[1].is_empty]
    return {"c": (lp.x, lp.y), "halls": H, "slots": slots, "lifts": lifts, "ring": True, "spokes": 0, "core_r": W}


def assign(L, role, rng_seed):
    """names, mech / pilot and keys onto the slots"""
    c = L["c"]
    slots = sorted(L["slots"], key=lambda q: -q.area)
    roles = list(ROLES[role])
    mech = [r for r in roles if r[1] == "mech"]
    pilot = [r for r in roles if r[1] == "pilot"]
    n = len(slots)
    n_mech = min(len(slots), max(len(mech), int(round(n * 0.35))))
    mech_slots = slots[:n_mech]
    pilot_slots = slots[n_mech:]
    out = []
    fk = DECK_KEY[role]
    def place(sl, names, kind):
        # the higher keys go to the rooms furthest from the hub
        sl = sorted(sl, key=lambda q: -Point(c).distance(q.centroid))
        names = sorted(names, key=lambda r: (-r[2], 1 if r[3] else 0))
        while len(names) < len(sl):
            i = len(names)
            names.append((FILL[kind][i % len(FILL[kind])], kind, fk if i % 3 else max(0, fk - 1), ""))
        names = names[:len(sl)]
        names = sorted(names, key=lambda r: (-r[2], 1 if r[3] else 0))   # (furthest first: the high keys; the station's services last, so nearest the hub)
        for q, r in zip(sl, names): out.append({"name": r[0], "kind": kind, "key": int(r[2]), "sign": r[3], "poly": q})
    # the docking concourse (your ship) on the front side (+Z, the docking approach), the hangar the same
    if role in ("MAIN HUB", "HANGAR") and mech_slots:
        front = max(mech_slots, key=lambda q: q.centroid.y - c[1] - 0.2 * abs(q.centroid.x - c[0]))
        first = mech[0]
        out.append({"name": first[0], "kind": "mech", "key": first[2], "sign": first[3], "poly": front})
        mech_slots = [q for q in mech_slots if q is not front]
        mech = mech[1:]
    place(mech_slots, list(mech), "mech")
    place(pilot_slots, list(pilot), "pilot")
    # dedupe filler names (Office 2, Office 3 ...)
    seen = {}
    for r in out:
        k = r["name"]
        seen[k] = seen.get(k, 0) + 1
        if seen[k] > 1: r["name"] = "%s %d" % (k, seen[k])
    return out


def doors(L, rooms, W):
    H = L["halls"]
    out = []
    has = set()
    for i, r in enumerate(rooms):
        q = r["poly"]
        a, b = nearest_points(q.exterior, H.boundary if hasattr(H, "boundary") else H)
        if a.distance(b) < W * 0.9:
            w = W * (0.62 if r["kind"] == "mech" else 0.3)
            out.append({"at": (a.x, a.y), "to": (b.x, b.y), "w": w, "key": r["key"], "room": r["name"]})
            has.add(i)
    for _ in range(3):   # a room not on a hall opens into a neighbour that is
        for i, r in enumerate(rooms):
            if i in has: continue
            best = None
            for j in has:
                d = r["poly"].distance(rooms[j]["poly"])
                if d < W * 0.6 and (best is None or d < best[0]): best = (d, j)
            if best:
                a, b = nearest_points(r["poly"].exterior, rooms[best[1]]["poly"].exterior)
                r["key"] = max(r["key"], rooms[best[1]]["key"])
                out.append({"at": (a.x, a.y), "to": (b.x, b.y), "w": W * (0.62 if r["kind"] == "mech" and rooms[best[1]]["kind"] == "mech" else 0.3), "key": r["key"], "room": r["name"]})
                has.add(i)
    stubs = []
    for i, r in enumerate(rooms):   # still shut in: a short pilot passage to the nearest hall
        if i in has: continue
        a, b = nearest_points(r["poly"], H)
        if a.distance(b) < N * 0.3:
            stubs.append(LineString([a, b]).buffer(W * 0.22, cap_style=2))
            out.append({"at": (a.x, a.y), "to": (a.x + (b.x - a.x) * 0.15, a.y + (b.y - a.y) * 0.15), "w": W * 0.3, "key": r["key"], "room": r["name"]})
            has.add(i)
    if stubs: L["halls"] = unary_union([H] + stubs)
    for i, r in enumerate(rooms): r["reach"] = i in has
    return out


# ---------------------------------------------------------------- drawing
def draw_deck(poly, L, rooms, drs, title, sub):
    img = np.zeros((N, N, 3), np.uint8)
    def fill(g, col):
        for p in parts(g):
            cv2.fillPoly(img, [np.array(p.exterior.coords, np.int32)], col)
            for h in p.interiors: cv2.fillPoly(img, [np.array(h.coords, np.int32)], (0, 0, 0))
    def edge(g, col, t):
        for p in parts(g):
            cv2.polylines(img, [np.array(p.exterior.coords, np.int32)], True, col, t, cv2.LINE_AA)
            for h in p.interiors: cv2.polylines(img, [np.array(h.coords, np.int32)], True, col, t, cv2.LINE_AA)
    fill(poly, (22, 22, 22))
    fill(L["halls"], (70, 52, 52))
    for r in rooms: fill(r["poly"], (40, 40, 120) if r["kind"] == "mech" else (120, 70, 30))
    edge(L["halls"], (230, 230, 230), 1)
    for r in rooms: edge(r["poly"], (240, 240, 240), 2)
    for d in drs:   # the doorway: a bar across the gap in its key colour
        ax, ay = d["at"]; bx, by = d["to"]
        vx, vy = bx - ax, by - ay
        ln = math.hypot(vx, vy) or 1.0
        px, py = -vy / ln, vx / ln
        h = d["w"] / 2
        pts = np.array([(ax + px * h, ay + py * h), (bx + px * h, by + py * h), (bx - px * h, by - py * h), (ax - px * h, ay - py * h)], np.int32)
        cv2.fillPoly(img, [pts], KEY_COL[d["key"]])
        cv2.polylines(img, [pts], True, (0, 0, 0), 1)
    edge(poly, (255, 255, 255), 3)
    for nm, g in L["lifts"]:
        fill(g, (200, 200, 60))
        cx, cy = int(g.centroid.x), int(g.centroid.y)
        cv2.putText(img, "L", (cx - 4, cy + 4), 0, 0.38, (0, 0, 0), 1, cv2.LINE_AA)
    c = L["c"]
    if "MAIN HUB" in title:
        cx, cy = int(c[0]), int(c[1])
        star = [(cx + (14 if i % 2 == 0 else 6) * math.cos(-math.pi / 2 + i * math.pi / 5), cy + (14 if i % 2 == 0 else 6) * math.sin(-math.pi / 2 + i * math.pi / 5)) for i in range(10)]
        cv2.fillPoly(img, [np.array(star, np.int32) + np.array([0, -int(L["core_r"] * 0.5)])], (60, 220, 255))
        cv2.putText(img, "MAIN HUB", (cx - 30, cy + int(L["core_r"] * 0.45)), 0, 0.4, (255, 255, 255), 1, cv2.LINE_AA)
        cv2.putText(img, "START / FAST TRAVEL", (cx - 62, cy + int(L["core_r"] * 0.45) + 14), 0, 0.36, (60, 220, 255), 1, cv2.LINE_AA)
    for r in rooms:
        q = r["poly"]
        p = q.representative_point()
        txt = r["name"]
        sc = 0.34 if len(txt) < 14 else 0.3
        (tw, th), _ = cv2.getTextSize(txt, 0, sc, 1)
        x, y = int(p.x - tw / 2), int(p.y + th / 2)
        cv2.putText(img, txt, (x, y), 0, sc, (0, 0, 0), 3, cv2.LINE_AA)
        cv2.putText(img, txt, (x, y), 0, sc, (255, 255, 255), 1, cv2.LINE_AA)
        if r["key"] > 0: cv2.circle(img, (x - 6, y - th // 2), 4, KEY_COL[r["key"]], -1)
        if not r.get("reach", True): cv2.putText(img, "no door", (x, y + 12), 0, 0.3, (80, 80, 255), 1, cv2.LINE_AA)
    cv2.rectangle(img, (0, 0), (N, 44), (0, 0, 0), -1)
    cv2.putText(img, title, (10, 20), 0, 0.6, (255, 255, 255), 1, cv2.LINE_AA)
    cv2.putText(img, sub, (10, 38), 0, 0.42, (180, 180, 180), 1, cv2.LINE_AA)
    return img


def legend_panel(top, side, idx, sm, info):
    img = np.zeros((N, N, 3), np.uint8)
    t = cv2.resize(top, (300, 300))
    s = cv2.resize(side, (300, 300))
    img[60:360, 10:310] = cv2.cvtColor(t, cv2.COLOR_GRAY2BGR) // 2
    img[60:360, 330:630] = cv2.cvtColor(s, cv2.COLOR_GRAY2BGR) // 2
    cv2.putText(img, "PLAN VIEW (the decks' plane)", (10, 52), 0, 0.45, (200, 200, 200), 1, cv2.LINE_AA)
    cv2.putText(img, "SIDE: the five deck cuts", (330, 52), 0, 0.45, (200, 200, 200), 1, cv2.LINE_AA)
    for k, i in enumerate(idx):   # where each deck cuts the model
        y = int(330 + 300 * (0.5 - (((i + 0.5) / NB) - 0.5) * 1.0) - 300 * 0.5) if False else None
    ys = info["ycut"]
    for k, (nm, yf) in enumerate(zip(DECKS, ys)):
        y = int(60 + 300 * yf)
        cv2.line(img, (330, y), (630, y), (60, 220, 255), 1)
        cv2.putText(img, "%d %s" % (k + 1, nm), (334, y - 3), 0, 0.33, (60, 220, 255), 1, cv2.LINE_AA)
    y = 390
    rows = [("mech room / way (red)", (40, 40, 120)), ("pilot-only room (blue)", (120, 70, 30)), ("corridor (mech)", (70, 52, 52)), ("lift", (200, 200, 60))]
    for t2, col in rows:
        cv2.rectangle(img, (14, y - 12), (34, y + 2), col, -1)
        cv2.putText(img, t2, (42, y), 0, 0.45, (230, 230, 230), 1, cv2.LINE_AA)
        y += 24
    y = 390
    for k in range(5):
        cv2.rectangle(img, (330, y - 12), (350, y + 2), KEY_COL[k], -1)
        cv2.putText(img, "door: %s%s" % (KEY_NAME[k], " (green)" if k == 0 else ""), (358, y), 0, 0.45, (230, 230, 230), 1, cv2.LINE_AA)
        y += 24
    y = 500
    for line in info["lines"]:
        cv2.putText(img, line, (14, y), 0, 0.42, (230, 230, 230), 1, cv2.LINE_AA)
        y += 20
    return img


# ---------------------------------------------------------------- one station
def deck_outlines(st):
    """The five deck outlines (px, N x N) of a station model and its lift axis c (shared with station_walkways.py)."""
    model = st["model"]
    path = os.path.join(REPO, "assets", "stations3d", model + ".glb")
    masks, top, side, (lo, hi, s, dax, upright) = slices(path)
    idx, sm = pick_decks(masks)
    hubR = max(30.0, min(70.0, 0.11 * (N - 40)))
    hub_poly = outline(deck_mask(masks, idx[2]))
    c = (N / 2, N / 2)
    # the station seen from above, thin spikes and antennas taken off: where a slice is too broken up to live in, the
    # deck is this silhouette, drawn in a little more for each deck away from the hub (the station tapers)
    sm_k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (25, 25))
    silm = cv2.morphologyEx(cv2.morphologyEx(top, cv2.MORPH_CLOSE, sm_k), cv2.MORPH_OPEN, sm_k)
    sil = outline(clean(silm))
    src = []
    polys = []
    for k, role in enumerate(DECKS):
        i = idx[k]
        poly = outline(deck_mask(masks, i))
        need = 0.6 if role == "MAIN HUB" else 0.3
        if sil is not None and (poly is None or poly.area < need * sil.area or poly.length / math.sqrt(max(poly.area, 1)) > 14.0):
            taper = 0.06 * math.sqrt(sil.area) * abs(k - 2)
            p2 = sil.buffer(-taper, join_style=1)
            p2 = max(parts(p2), key=lambda g: g.area) if parts(p2) else sil
            poly = p2 if poly is None or p2.area > poly.area else poly
            src.append("silhouette")
        else: src.append("slice")
        if poly is None or poly.area < 4000:
            poly = hub_poly.buffer(-30) if hub_poly is not None else Point(c).buffer(200)
        polys.append(poly)
    # the lift axis: the station's middle when the hub deck has room round it, else the hub deck's deepest point
    hp = polys[2]
    c = (N / 2, N / 2)
    if not hp.buffer(-hubR * 1.6).contains(Point(c)):
        hm = np.zeros((N, N), np.uint8)
        cv2.fillPoly(hm, [np.array(hp.exterior.coords, np.int32)], 255)
        dm = cv2.distanceTransform(hm, cv2.DIST_L2, 5)
        yy, xx = np.unravel_index(int(np.argmax(dm)), dm.shape)
        c = (float(xx), float(yy))
    return {"masks": masks, "top": top, "side": side, "lo": lo, "hi": hi, "s": s, "dax": dax, "upright": upright,
            "idx": idx, "sm": sm, "polys": polys, "src": src, "c": c, "hubR": hubR, "hub_poly": hub_poly}


def build(st):
    model = st["model"]
    O = deck_outlines(st)
    masks, top, side, lo, hi, s, dax, upright = O["masks"], O["top"], O["side"], O["lo"], O["hi"], O["s"], O["dax"], O["upright"]
    idx, sm, polys, src, c, hubR, hub_poly = O["idx"], O["sm"], O["polys"], O["src"], O["c"], O["hubR"], O["hub_poly"]
    style = next((k for k in STYLE_W if "_%s_" % k in model), None)
    width_m = STYLE_W.get(style, ST3D_W.get(model, 1000.0))
    mpp = width_m / (N - 40)
    T = 4.0                 # px wall gap
    W = max(18.0, 0.05 * (N - 40))   # px mech hall width
    decks = []
    panels = []
    for k, role in enumerate(DECKS):
        i = idx[k]
        poly = polys[k]
        L = layout(poly, c, role, hubR, W, T)
        if L is None: continue
        rooms = assign(L, role, k)
        drs = doors(L, rooms, W)
        n_m = sum(1 for r in rooms if r["kind"] == "mech")
        kc = {}
        for r in rooms: kc[r["key"]] = kc.get(r["key"], 0) + 1
        area_m2 = poly.area * mpp * mpp
        sub = "%d rooms (%d mech, %d pilot) · %s · %s · %d x %d m" % (len(rooms), n_m, len(rooms) - n_m, "ring + %d spokes" % L["spokes"] if L["ring"] else "%d spokes" % L["spokes"],
            " ".join("%s %d" % (KEY_NAME[q][0], kc[q]) for q in sorted(kc)), (poly.bounds[2] - poly.bounds[0]) * mpp, (poly.bounds[3] - poly.bounds[1]) * mpp)
        panels.append(draw_deck(poly, L, rooms, drs, "%d  %s DECK" % (k + 1, role), sub))
        toM = lambda g: [[round((x - N / 2) * mpp, 1), round((y - N / 2) * mpp, 1)] for x, y in g.exterior.coords]
        decks.append({"deck": k + 1, "role": role, "outline_from": src[k], "slice": i, "y_frac": round((i + 0.5) / NB, 3), "area_m2": round(area_m2),
                      "outline": toM(poly), "halls": [toM(p) for p in parts(L["halls"])],
                      "rooms": [{"name": r["name"], "kind": r["kind"], "key": r["key"], "key_name": KEY_NAME[r["key"]], "sign": r["sign"], "door": r["reach"], "poly": toM(r["poly"])} for r in rooms],
                      "doors": [{"room": d["room"], "key": d["key"], "at": [round((d["at"][0] - N / 2) * mpp, 1), round((d["at"][1] - N / 2) * mpp, 1)], "width_m": round(d["w"] * mpp, 1)} for d in drs],
                      "lifts": [{"name": nm, "at": [round((g.centroid.x - N / 2) * mpp, 1), round((g.centroid.y - N / 2) * mpp, 1)]} for nm, g in L["lifts"]],
                      "hub": [round((L["c"][0] - N / 2) * mpp, 1), round((L["c"][1] - N / 2) * mpp, 1)]})
    ycut = [1.0 - (i + 0.5) / NB for i in idx]
    # the side view is centred on the model's middle: map the slice heights onto it
    H = hi[dax] - lo[dax]
    ycut = [0.5 - ((lo[dax] + H * (i + 0.5) / NB) - (lo[dax] + hi[dax]) / 2) / s * (N - 40) / N for i in idx]
    tot = sum(d["area_m2"] for d in decks)
    nrooms = sum(len(d["rooms"]) for d in decks)
    lines = ["%s  (%s)" % (st["name"], st["faction"] or "-"), "model %s" % model, "system %s" % st["system"],
             "about %d m across · 5 decks · %d rooms · %d m2" % (width_m, nrooms, tot),
             "stands upright: decks cut front to back" if upright else "decks cut level, bottom to top",
             "deck outlines: " + ", ".join("%d %s" % (k + 1, x) for k, x in enumerate(src)),
             "PROPOSED: not in the game until you approve it."]
    panels.append(legend_panel(top, side, idx, sm, {"ycut": ycut, "lines": lines}))
    row1 = np.hstack(panels[0:3])
    row2 = np.hstack(panels[3:6]) if len(panels) >= 6 else np.hstack(panels[3:] + [np.zeros((N, N, 3), np.uint8)] * (3 - len(panels[3:])))
    sheet = np.vstack([row2, row1])   # (top row: HABITAT, COMMAND, legend; bottom: HANGAR, ENGINEERING, MAIN HUB)
    # reorder so decks read top-down: COMMAND, HABITAT, legend / MAIN HUB, ENGINEERING, HANGAR
    sheet = np.vstack([np.hstack([panels[4], panels[3], panels[5]]), np.hstack([panels[2], panels[1], panels[0]])])
    od = os.path.join(OUT, model)
    os.makedirs(od, exist_ok=True)
    cv2.imwrite(os.path.join(od, "plan.jpg"), cv2.resize(sheet, (1440, 960), interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 74])
    json.dump({"station": st["name"], "faction": st["faction"], "system": st["system"], "sid": st["sid"], "slot": st["slot"], "model": model,
               "status": "PROPOSED", "metres_across": width_m, "metres_per_px": round(mpp, 4), "decks": decks}, open(os.path.join(od, "plan.json"), "w"), indent=1)
    return {"model": model, "name": st["name"], "rooms": nrooms, "area": tot, "noreach": sum(1 for d in decks for r in d["rooms"] if not r["door"])}


if __name__ == "__main__":
    S = json.load(open(os.path.join(HERE, "stations", "stations.json")))
    want = sys.argv[1:]
    for st in S:
        if want and st["model"] not in want: continue
        r = build(st)
        print("%-40s %-28s %3d rooms %7d m2  no-door %d" % (r["model"], r["name"][:28], r["rooms"], r["area"], r["noreach"]), flush=True)
