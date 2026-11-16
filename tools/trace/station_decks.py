#!/usr/bin/env python3
"""Station decks, the full build (owner, Nov 16 2026: "you know how to build it, build everything just like the ships,
only this one has five floors ... after red is purple ... the elevators ... the library of rooms ... mirror anything
whose silhouette doesn't line up").  PROPOSED plans: nothing goes into the game until the owner marks a station.

Per station (tools/trace/stations/stations.json), per deck (HANGAR, ENGINEERING, MAIN HUB, HABITAT, COMMAND):
  1 OUTLINE   the deck slice of the model (station_plans.deck_outlines), made MIRROR-TRUE: the bigger half about the
              lift axis, mirrored (the owner: "if the silhouette isn't good, mirror it").
  2 WALKWAYS  station_walkways.walkways(): hub, spines, octagon ring, pilot branches, lifts (red / blue / yellow).
  3 ROOMS     traced library rooms only (shape_library.json via decklib.fit / lib): slots stepped along every hall,
              both sides, the room turned square to its hall, a big room capping each spine end. Built on the right
              half and mirrored; decklib.settle / finalize give one shared wall and no overlaps.
  4 KINDS     a room is MECH (red) when it is big (>= 100 m2) and opens on a mech way, else PILOT (blue: narrow door).
  5 NAMES     the deck's role list (station_plans.ROLES), the hub deck's services nearest the hub; fillers after.
  6 KEYS      open / yellow / orange / red / purple, the ship formula carried up five decks (KEY CHAIN below), and the
              lifts: the main lift reaches every deck but COMMAND needs the RED card; the freight lifts skip COMMAND.
  7 CHECK     inside the outline, no overlaps, every room has a door on a hall, mirror-true, the card chain holds.
Writes tools/trace/stations/<model>/decks.json (metres, origin = lift axis) and decks.jpg (the review sheet).
usage: python3 -I tools/trace/station_decks.py [model ...]"""
import json, math, os, sys, random
import numpy as np, cv2
from shapely import affinity
from shapely.geometry import Point, LineString, Polygon, box
from shapely.ops import unary_union

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import station_plans as SP
import station_walkways as SW
import decklib
from decklib import fit, lib

PX = 10.0
WALL = 0.4 * PX
BIG_M2 = 100.0
CAP_BIG, CAP_MECH, CAP_PILOT = 360.0, 240.0, 80.0   # m2: the biggest room a leftover pocket makes (bigger: cut in strips)
KEY_COL = SP.KEY_COL
KEY_NAME = SP.KEY_NAME
RED, BLUE, YEL = SW.RED, SW.BLUE, SW.YEL
TAGS = {   # (mech room tags, pilot room tags) in order of preference
    "HANGAR": (["cargo", "machine", "engine", "weapons"], ["office", "closet", "cabin", "vestibule"]),
    "ENGINEERING": (["engine", "reactor", "machine", "cargo"], ["machine", "office", "closet", "cabin"]),
    "MAIN HUB": (["mess", "lounge", "cargo", "command"], ["office", "medbay", "weapons", "lounge", "cabin"]),
    "HABITAT": (["mess", "quarters", "lounge", "cargo"], ["cabin", "quarters", "office", "closet"]),
    "COMMAND": (["command", "bridge", "weapons", "cargo"], ["office", "command", "cabin", "weapons"]),
}
# KEY CHAIN (the ship formula, five decks): the YELLOW card lies open on the HANGAR deck (you come aboard there),
# the ORANGE card behind yellow doors on the MAIN HUB, the RED card behind orange doors in ENGINEERING, the PURPLE
# card behind red doors on the HABITAT, and the objective (the Commander's Office / the Vault) behind PURPLE on
# COMMAND, which the main lift only reaches with the RED card.
CHAIN = [("HANGAR", 0, 1), ("MAIN HUB", 1, 2), ("ENGINEERING", 2, 3), ("HABITAT", 3, 4)]   # (deck, door key of its room, card in it)
FILL_KEY = {"HANGAR": [0, 0, 1], "ENGINEERING": [1, 1, 2], "MAIN HUB": [0, 0, 0, 1], "HABITAT": [0, 1, 1, 2], "COMMAND": [3, 3, 4]}


def parts(g): return SW.parts(g)
ROUND = tuple(r["id"] for r in json.load(open(os.path.join(HERE, "shape_library.json")))["rooms"] if r["kind"] == "round" or len(r["poly"]) > 14)   # (no round / curvy blobs: straight walls)
def M(g): return affinity.scale(g, -1, 1, origin=(0, 0))


def mirror_true(ol):
    """the bigger half about x = 0, mirrored (one clean symmetric deck)"""
    big = 1e6
    R = ol.intersection(box(0, -big, big, big)); L = ol.intersection(box(-big, -big, 0, big))
    half = R if R.area >= L.area else M(L)
    g = unary_union([half, M(half)]).buffer(0.5).buffer(-0.5)
    return max(parts(g), key=lambda q: q.area) if parts(g) else ol


def place(g, rid_txt, ang, cx, cy, side):
    """a fitted room (centred at 0, its width along x) turned onto its hall: x along the hall, +y away from it"""
    if side < 0: g = affinity.scale(g, 1, -1, origin=(0, 0))
    g = affinity.rotate(g, ang, origin=(0, 0))
    return affinity.translate(g, cx, cy)


def rooms_for(W, role, seed):
    rng = random.Random(seed)
    free = W["inner"].difference(W["ways"].buffer(WALL * 1.5)).difference(unary_union([q for _, q in W["lifts"]]).buffer(WALL * 2))
    free = free.buffer(-WALL / 2)
    tm, tp = TAGS[role]
    placed = []     # [(poly, kind_hint, hall_kind, door_pt, hall_dist)]
    taken = Polygon()
    def reach(p, n, lim):
        r = 0.0
        while r < lim and free.contains(Point(p[0] + n[0] * (r + PX), p[1] + n[1] * (r + PX))): r += PX
        return r
    def try_slot(base, u, n, along, depth, hk, axis_cap=False):
        nonlocal taken
        # how deep the room can go: free space straight out from the hall, at both ends and the middle of the slot
        dmax = min(reach(base + u * s2 * along * 0.4, n, depth) for s2 in (-1, 0, 1))
        if dmax < 3.4 * PX: return False
        depth = dmax
        for d in (depth, depth * 0.85, depth * 0.7, depth * 0.55):
            if d < 3.4 * PX: break
            for a2 in (along, along * 0.8, along * 0.62):
                if a2 < 3.4 * PX: break
                mech = hk == "mech" and a2 * d >= BIG_M2 * PX * PX * 0.9
                tags = tm if mech else tp
                try: g, rid = fit(tags, 0, 0, a2 / PX, d / PX, max_change=1.6, exclude=ROUND)
                except Exception: continue
                ang = math.degrees(math.atan2(u[1], u[0]))
                cx, cy = base[0] + n[0] * (d / 2), base[1] + n[1] * (d / 2)
                side = 1 if (u[0] * n[1] - u[1] * n[0]) > 0 else -1
                q = place(g, rid, ang, cx, cy, side)
                if axis_cap: q = unary_union([q, M(q)]).buffer(0.5).buffer(-0.5)
                if q.is_empty or not free.buffer(0.5).contains(q) and q.difference(free).area > 0.04 * q.area: continue
                q = q.intersection(free)
                q = max(parts(q), key=lambda r: r.area) if parts(q) else q
                if q.is_empty or q.area < 9 * PX * PX: continue
                if q.intersection(taken).area > 0.02 * q.area: continue
                taken = unary_union([taken, q.buffer(WALL)])
                placed.append({"poly": q, "src": rid, "hall": hk, "door": (base[0] - n[0] * 0.2 * PX, base[1] - n[1] * 0.2 * PX), "axis": axis_cap})
                return True
        return False
    hub = Point(0, 0)
    lines = sorted(W["lines"], key=lambda L: (L[0] != "mech", Point(L[1]).distance(hub)))
    for hk, a, b in lines:
        a, b = np.array(a, float), np.array(b, float)
        if max(a[0], b[0]) < -0.5: continue                                # (the left half is the mirror)
        L = float(np.linalg.norm(b - a))
        if L < 6 * PX: continue
        u = (b - a) / L
        hw = (SW.WM if hk == "mech" else SW.WP) / 2
        step = ((18 if role in ("HANGAR", "ENGINEERING") else 14) if hk == "mech" else 9) * PX
        depth = ((30 if role in ("HANGAR", "ENGINEERING") else 22) if hk == "mech" else 13) * PX
        t = W["hub_r"] + 2 * PX if Point(a).distance(hub) < 1 else 3 * PX
        on_axis = abs(a[0]) < 1 and abs(b[0]) < 1
        while t + step * 0.5 < L - 2 * PX:
            mid = a + u * (t + step / 2)
            for s in (1, -1):
                n = np.array([-u[1], u[0]]) * s
                if on_axis and n[0] < 0: continue                         # (on the axis: build the right side only)
                if not on_axis and mid[0] + n[0] * depth / 2 < -0.5 and mid[0] > -0.5:
                    if n[0] < 0 and abs(u[0]) > 0.3: continue
                base = mid + n * (hw + WALL)
                try_slot(base, u, n, step - WALL * 2, depth, hk)
            t += step
        if hk == "mech" and Point(a).distance(hub) < 1:                    # the spine's end: one big room capping it
            base = b + u * (WALL)
            try_slot(base, np.array([u[1], -u[0]]), u, 20 * PX, 26 * PX, hk, axis_cap=on_axis)
    # the pockets left over (corners, wing tips, between halls): each gets the library room that best fits it,
    # turned to the pocket's own long side, if it touches a hall
    ways = W["ways"]
    left = free.intersection(box(-0.5 * PX, -1e6, 1e6, 1e6)).difference(taken)
    pockets = []
    for P0 in parts(left.buffer(-0.5 * PX).buffer(0.5 * PX)):
        # a big pocket is cut into strips across its long side, one room each (no giant sector-shaped rooms)
        cap = (CAP_BIG if role in ("HANGAR", "ENGINEERING") else CAP_MECH) if P0.distance(W["mech"]) < 2.5 * PX else CAP_PILOT
        n = max(1, int(math.ceil(P0.area / (cap * PX * PX))))
        if n == 1: pockets.append(P0); continue
        rr0 = P0.minimum_rotated_rectangle; xy0 = list(rr0.exterior.coords)
        e1 = np.array(xy0[1]) - np.array(xy0[0]); e2 = np.array(xy0[2]) - np.array(xy0[1])
        lng, sht = (e1, e2) if np.linalg.norm(e1) >= np.linalg.norm(e2) else (e2, e1)
        o = np.array(xy0[0]) if np.linalg.norm(e1) >= np.linalg.norm(e2) else np.array(xy0[1])
        for i in range(n):
            a0, a1 = o + lng * i / n, o + lng * (i + 1) / n
            strip = Polygon([tuple(a0), tuple(a1), tuple(a1 + sht), tuple(a0 + sht)]).buffer(-WALL / 2, join_style=2)
            pockets += parts(P0.intersection(strip))
    for P in sorted(pockets, key=lambda q: -q.area):
        if P.area < 40 * PX * PX or P.distance(ways) > 2.5 * PX: continue
        rr = P.minimum_rotated_rectangle
        xy = list(rr.exterior.coords)
        e1 = (xy[1][0] - xy[0][0], xy[1][1] - xy[0][1]); e2 = (xy[2][0] - xy[1][0], xy[2][1] - xy[1][1])
        l1, l2 = math.hypot(*e1), math.hypot(*e2)
        u = np.array(e1) / max(l1, 1e-6) if l1 >= l2 else np.array(e2) / max(l2, 1e-6)
        A, B = max(l1, l2) * 0.92, min(l1, l2) * 0.92
        if B < 3.4 * PX: continue
        near_mech = P.distance(W["mech"]) <= P.distance(W["pilot"]) if not W["pilot"].is_empty else True
        mech = near_mech and P.area >= BIG_M2 * PX * PX
        try: g, rid = fit(tm if mech else tp, 0, 0, A / PX, B / PX, max_change=1.6, exclude=ROUND)
        except Exception: continue
        ang = math.degrees(math.atan2(u[1], u[0]))
        q = affinity.translate(affinity.rotate(g, ang, origin=(0, 0)), rr.centroid.x, rr.centroid.y).intersection(P)
        q = max(parts(q), key=lambda r: r.area) if parts(q) else q
        if q.is_empty or q.area < 20 * PX * PX: continue
        from shapely.ops import nearest_points
        dp = nearest_points(ways, q)[0]
        taken = unary_union([taken, q.buffer(WALL)])
        placed.append({"poly": q, "src": rid, "hall": "mech" if near_mech else "pilot", "door": (dp.x, dp.y),
                       "axis": q.centroid.x < 0.5 * PX and q.bounds[0] < -0.5 * PX})
    # mirror: the right half's rooms to the left (rooms already on the axis stay single)
    R, meta = {}, {}
    k = 0
    for p in placed:
        k += 1
        c = p["poly"].centroid
        if p["axis"] or abs(c.x) < 0.5 * PX:
            if not p.get("sym_done") and p["poly"].bounds[0] < -0.5 * PX:
                p["poly"] = unary_union([p["poly"], M(p["poly"])]).intersection(free).buffer(0)
                p["poly"] = max(parts(p["poly"]), key=lambda r: r.area)
            R["r%d" % k] = p["poly"]; meta["r%d" % k] = dict(p, twin=None)
        else:
            R["r%d" % k] = p["poly"]; R["r%dm" % k] = M(p["poly"])
            meta["r%d" % k] = dict(p, twin="r%dm" % k)
            meta["r%dm" % k] = dict(p, poly=M(p["poly"]), door=(-p["door"][0], p["door"][1]), twin="r%d" % k)
    return R, meta


def grow(R, W, by=4.5 * PX):
    """each room grows (square corners) into the free space nearest to it - its own share, never past a neighbour's -
    so the deck fills up with rooms that keep their traced character"""
    free = W["inner"].difference(unary_union([W["ways"]] + [q for _, q in W["lifts"]]).buffer(WALL * 1.5))
    keys = [k for k in R if not k.endswith("m")]
    pts = {k: R[k] for k in R}
    out = dict(R)
    for k in keys:
        g = R[k]
        big = g.buffer(by, join_style=2)
        others = unary_union([pts[o] for o in R if o != k and o != k + "m"]) if len(R) > 1 else Polygon()
        # the half-way line to every neighbour: keep the part of the growth nearer to this room than to the others
        share = big.intersection(free)
        if not others.is_empty:
            near = others.buffer(by, join_style=2)
            contested = share.intersection(near)
            mine = contested.intersection(g.buffer(by * 0.5, join_style=2))
            share = unary_union([share.difference(near), mine])
        g2 = unary_union([g, share]).buffer(0.5, join_style=2).buffer(-0.5, join_style=2)
        g2 = max(parts(g2), key=lambda q: q.area) if parts(g2) else g
        try: g2 = decklib.clean(g2, nub=8.0)
        except Exception: pass
        out[k] = g2
        if (k + "m") in R: out[k + "m"] = M(g2)
    return out


def clean_set(R, W):
    """one wall between neighbours, no overlaps (decklib.tidy per room; the twin is the mirror), inside the deck"""
    HALLS = unary_union([W["ways"]] + [q for _, q in W["lifts"]]).buffer(WALL)
    order = sorted([k for k in R if not k.endswith("m")], key=lambda k: -R[k].area)
    out, blocked = {}, [HALLS]
    for k in order:
        B = unary_union(blocked)
        g = R[k].intersection(W["inner"]).difference(B)
        g = max(parts(g), key=lambda q: q.area) if parts(g) else Polygon()
        if g.is_empty or g.area < 9 * PX * PX: continue
        try:
            t = decklib.tidy(decklib.dedupe(g), B, rounds=6)
            if not t.is_empty and t.area > 0.8 * g.area: g = t
        except Exception: pass
        if (k + "m") in R:
            if g.intersection(M(g)).area > 0.02 * g.area:   # (a room reaching over the axis: make it one symmetric room)
                g = unary_union([g, M(g)]).difference(B)
                g = max(parts(g), key=lambda q: q.area) if parts(g) else g
                out[k] = g; blocked.append(g.buffer(WALL / 2)); continue
            out[k] = g; out[k + "m"] = M(g)
            blocked += [g.buffer(WALL / 2), M(g).buffer(WALL / 2)]
        else:
            out[k] = g; blocked.append(g.buffer(WALL / 2))
    return out


def name_rooms(R, meta, role, seed):
    rng = random.Random(seed)
    roles = SP.ROLES[role]
    mech_names = [r for r in roles if r[1] == "mech"]
    pilot_names = [r for r in roles if r[1] == "pilot"]
    order = sorted(R, key=lambda k: (R[k].centroid.distance(Point(0, 0)), k))
    out = {}
    used = set()
    for k in order:
        g = R[k]
        a = g.area / PX / PX
        kind = "mech" if (a >= BIG_M2 and meta[k]["hall"] == "mech") else "pilot"
        pool = mech_names if kind == "mech" else pilot_names
        nm = next((r for r in pool if r[0] not in used), None)
        if nm is None:
            base = rng.choice(SP.FILL[kind])
            i = 1
            while "%s %d" % (base, i) in used: i += 1
            nm = ("%s %d" % (base, i), kind, rng.choice(FILL_KEY[role]), "")
        used.add(nm[0])
        out[k] = {"name": nm[0], "kind": kind, "key": int(nm[2]), "sign": nm[3]}
    return out


def door_on(g, p, hall_kind, kind):
    """the door: the point on the room's wall nearest where its slot met the hall, its width by kind"""
    from shapely.ops import nearest_points
    q = nearest_points(g.exterior, Point(p))[0]
    return {"at": [round(q.x / PX, 2), round(q.y / PX, 2)], "width_m": 3.2 if kind == "mech" else 1.4}


def keys_chain(decks, seed):
    """the station's card chain across the decks (CHAIN), plus the objective on COMMAND; -> notes, ok"""
    rng = random.Random(seed)
    notes, ok = [], True
    for role, door_key, card in CHAIN:
        D = next(d for d in decks if d["role"] == role)
        cand = [r for r in D["rooms"] if r["kind"] == "pilot"] or D["rooms"]
        if not cand: ok = False; notes.append("%s: no room for the %s card" % (role, KEY_NAME[card])); continue
        cand.sort(key=lambda r: -math.hypot(*r["centre"]))
        r = cand[min(len(cand) - 1, rng.randint(0, 2))]
        r["key"] = door_key
        r["card"] = card
        notes.append("%s card: %s (%s), %s doors" % (KEY_NAME[card], r["name"], role, KEY_NAME[door_key]))
    C = next(d for d in decks if d["role"] == "COMMAND")
    obj = next((r for r in C["rooms"] if r["name"] in ("Commander's Office", "Vault")), None) or (max(C["rooms"], key=lambda r: r["area_m2"]) if C["rooms"] else None)
    if obj is None: ok = False; notes.append("COMMAND: no room for the objective")
    else:
        obj["key"] = 4; obj["objective"] = True
        notes.append("OBJECTIVE: %s (COMMAND), PURPLE doors" % obj["name"])
    for D in decks:   # every card door is below the card it needs being reachable: a room's key <= the cards found so far
        for r in D["rooms"]:
            if r.get("card") and r["key"] >= r["card"]: ok = False
    return notes, ok


def draw(W, rooms, title, sub, role):
    img = SW.draw(W, title, sub, role)
    g = W["outline"]; x0, y0, x1, y1 = g.bounds
    S = 600.0 / max(x1 - x0, y1 - y0)
    ox, oy = 320 - (x0 + x1) / 2 * S, 340 - (y0 + y1) / 2 * S
    T = lambda q: affinity.affine_transform(q, [S, 0, 0, S, ox, oy])
    over = img.copy()
    for r in rooms:
        q = T(r["_poly"])
        col = (70, 60, 150) if r["kind"] == "mech" else (150, 95, 45)
        cv2.fillPoly(over, [np.array(q.exterior.coords, np.int32)], col)
    img[:] = cv2.addWeighted(over, 0.7, img, 0.3, 0)
    for r in rooms:
        q = T(r["_poly"])
        cv2.polylines(img, [np.array(q.exterior.coords, np.int32)], True, (245, 245, 245), 1, cv2.LINE_AA)
        d = T(Point(r["door"]["at"][0] * PX, r["door"]["at"][1] * PX))
        rr = max(3, int(r["door"]["width_m"] * PX * S / 2))
        cv2.circle(img, (int(d.x), int(d.y)), rr, KEY_COL[r["key"]], -1)
        cv2.circle(img, (int(d.x), int(d.y)), rr, (0, 0, 0), 1)
    for r in rooms:
        q = T(r["_poly"])
        if q.area < 260: continue
        t = r["name"] + (" ★%s" % KEY_NAME[r["card"]] if r.get("card") else "") + (" ◆" if r.get("objective") else "")
        lb = decklib.label_box(q, t.replace("★", "*").replace("◆", "[OBJ]"))
        if lb is None: continue
        lines, sc, bx = lb
        y = bx.bounds[1] + 9
        for ln in lines:
            (tw, th), _ = cv2.getTextSize(ln, 0, sc, 1)
            col = (0, 255, 255) if r.get("card") or r.get("objective") else (255, 255, 255)
            cv2.putText(img, ln, (int(bx.centroid.x - tw / 2), int(y)), 0, sc, (0, 0, 0), 3, cv2.LINE_AA)
            cv2.putText(img, ln, (int(bx.centroid.x - tw / 2), int(y)), 0, sc, col, 1, cv2.LINE_AA)
            y += th + 4
    return img


def legend(top, st, lines, chain):
    img = SW.legend(top, st, lines)
    cv2.rectangle(img, (325, 236), (640, 360), (0, 0, 0), -1)
    y = 250
    for txt, col in (("mech room (red, wide door)", (70, 60, 150)), ("pilot room (blue, narrow door)", (150, 95, 45))):
        cv2.rectangle(img, (330, y - 13), (352, y + 3), col, -1)
        cv2.putText(img, txt, (360, y), 0, 0.45, (230, 230, 230), 1, cv2.LINE_AA)
        y += 24
    x = 330
    for k in range(5):
        cv2.circle(img, (x + 8, y - 5), 7, KEY_COL[k], -1)
        cv2.putText(img, KEY_NAME[k][:3], (x + 18, y), 0, 0.4, (230, 230, 230), 1, cv2.LINE_AA)
        x += 60
    y = 520
    for ln in chain[:6]:
        cv2.putText(img, ln[:70], (14, y), 0, 0.38, (60, 220, 255), 1, cv2.LINE_AA)
        y += 18
    cv2.putText(img, "LIFTS: main lift every deck, COMMAND needs RED; freight lifts skip COMMAND", (14, y + 4), 0, 0.36, (0, 215, 255), 1, cv2.LINE_AA)
    return img


def build(st):
    model = st["model"]
    O = SP.deck_outlines(st)
    style = next((k for k in SW.STYLE_M if "_%s_" % k in model), None)
    width_m = SW.STYLE_M.get(style, SW.ST3D_M.get(model, 120.0))
    f = width_m * PX / (SP.N - 40)
    c0 = O["c"]
    to_plan = lambda g: affinity.affine_transform(g, [f, 0, 0, f, -c0[0] * f, -c0[1] * f])
    seed = sum(map(ord, model))
    panels, decks, problems = [], [], []
    Ws = []
    for k, role in enumerate(SP.DECKS):
        ol = mirror_true(to_plan(O["polys"][k]))
        W = SW.walkways(ol, (0.0, 0.0), role, width_m * PX)
        Rp, meta = rooms_for(W, role, seed + k)
        R = clean_set(grow(Rp, W), W)
        names = name_rooms(R, meta, role, seed + k)
        rooms = []
        for kk, g in R.items():
            nm = names[kk]
            rooms.append({"id": kk, "name": nm["name"], "kind": nm["kind"], "key": nm["key"], "sign": nm["sign"],
                          "src": meta[kk]["src"], "area_m2": round(g.area / PX / PX, 1),
                          "centre": [round(g.centroid.x / PX, 2), round(g.centroid.y / PX, 2)],
                          "poly": [[round(x / PX, 2), round(y / PX, 2)] for x, y in g.exterior.coords],
                          "door": door_on(g, meta[kk]["door"], meta[kk]["hall"], nm["kind"]), "_poly": g})
        # checks
        allr = unary_union([r["_poly"] for r in rooms]) if rooms else Polygon()
        ovl = sum(a["_poly"].intersection(b["_poly"]).area for i, a in enumerate(rooms) for b in rooms[i + 1:]) / PX / PX
        out_ = allr.difference(W["outline"]).area / PX / PX
        hits = allr.intersection(W["ways"]).area / PX / PX
        sym = allr.symmetric_difference(M(allr)).area / max(1.0, allr.area)
        if ovl > 2: problems.append("%s: rooms overlap %.0f m2" % (role, ovl))
        if out_ > 2: problems.append("%s: %.0f m2 outside the hull" % (role, out_))
        if hits > 2: problems.append("%s: rooms on a hall %.0f m2" % (role, hits))
        if sym > 0.03: problems.append("%s: not mirror-true (%.0f%%)" % (role, sym * 100))
        if len(rooms) < 4: problems.append("%s: only %d rooms" % (role, len(rooms)))
        decks.append({"deck": k + 1, "role": role, "rooms": rooms, "_W": W})
        Ws.append(W)
    chain, ok = keys_chain(decks, seed)
    if not ok: problems.append("key chain broken")
    for D in decks:
        W, role, rooms = D["_W"], D["role"], D["rooms"]
        nm = len(rooms); nmech = sum(r["kind"] == "mech" for r in rooms)
        sub = "%d rooms (%d mech, %d pilot) · %d m2 of rooms · mirror-true" % (nm, nmech, nm - nmech, sum(r["area_m2"] for r in rooms))
        panels.append(draw(W, rooms, "%d  %s DECK" % (D["deck"], role), sub, role))
    lines = ["%s  (%s)" % (st["name"], st["faction"] or "-"), "system %s" % st["system"], "model %s" % model,
             "interior about %d m across, 5 decks" % width_m, "PROPOSED: X = close, O = fix"]
    panels.append(legend(O["top"], st, lines, chain))
    sheet = np.vstack([np.hstack([panels[4], panels[3], panels[5]]), np.hstack([panels[2], panels[1], panels[0]])])
    od = os.path.join(SP.OUT, model)
    os.makedirs(od, exist_ok=True)
    cv2.imwrite(os.path.join(od, "decks.jpg"), cv2.resize(sheet, (1920, 1280), interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 82])
    out = {"station": st["name"], "model": model, "faction": st["faction"], "system": st["system"], "status": "PROPOSED (full decks)",
           "metres_across": width_m, "units": "metres, origin = the lift axis", "key_names": KEY_NAME,
           "lifts": {"main": "every deck; COMMAND needs the RED card", "freight": "every deck but COMMAND"},
           "chain": chain, "problems": problems, "decks": []}
    for D in decks:
        W = D["_W"]
        out["decks"].append({"deck": D["deck"], "role": D["role"],
                             "outline": [[round(x / PX, 2), round(y / PX, 2)] for x, y in W["outline"].exterior.coords],
                             "halls": [{"kind": kd, "from": [round(a[0] / PX, 2), round(a[1] / PX, 2)], "to": [round(b[0] / PX, 2), round(b[1] / PX, 2)],
                                        "width_m": SW.WM / PX if kd == "mech" else SW.WP / PX} for kd, a, b in W["lines"]],
                             "hub_radius_m": round(W["hub_r"] / PX, 2),
                             "lifts": [{"name": n2, "at": [round(q.centroid.x / PX, 2), round(q.centroid.y / PX, 2)]} for n2, q in W["lifts"]],
                             "rooms": [{k2: v for k2, v in r.items() if k2 != "_poly"} for r in D["rooms"]]})
    json.dump(out, open(os.path.join(od, "decks.json"), "w"), indent=1)
    return {"model": model, "rooms": [len(D["rooms"]) for D in decks], "problems": problems}


if __name__ == "__main__":
    S = json.load(open(os.path.join(SP.OUT, "stations.json")))
    want = sys.argv[1:]
    for st in S:
        if want and st["model"] not in want: continue
        r = build(st)
        print("%-42s rooms %s  %s" % (r["model"], r["rooms"], "; ".join(r["problems"]) or "OK"), flush=True)
