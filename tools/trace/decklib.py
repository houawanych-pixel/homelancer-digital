#!/usr/bin/env python3
"""Composed UPPER and LOWER decks for a fleet ship (owner, 13 Nov 2026: "compose it, do top and bottom floor, see
the examples"). There is no blueprint for these decks: they are PROPOSED layouts for the owner's approval, drawn
with the same engineering rules as the traced main deck (planlib: one wall thickness, one door width, hallways =
centre line + width, mirrored about the ship's axis). Each deck sits centre-mass inside the ship's own hull
silhouette (measured from the HoloDeck picture: the glowing hull, filled, mirrored, thin fins opened away), and
the lift shafts stand at exactly the same spot as on the main deck.

A ship's eng/build_decks.py holds the rooms of both decks and calls decklib.run(...). Outputs per deck in eng/:
deck_<name>.json (same schema as plan.json + level, lifts), deck_<name>.png (white on black, hull in red, the main
deck ghosted) and deck_<name>_on_map.jpg (on the original picture)."""
import json, math, os
import cv2, numpy as np
from shapely.geometry import Polygon, MultiPolygon, box, mapping, shape
from shapely.ops import unary_union
import planlib
from planlib import Ship, build, reach, raster, PX_PER_M, T, DOOR

def hull(src_path, ax, fin=14):
    """The ship's outer silhouette from its HoloDeck picture: glow pixels, closed, holes filled, mirrored about ax,
    then opened by `fin` px so thin fins and spikes drop out (the decks belong in the body)."""
    im = cv2.imread(src_path)
    hsv = cv2.cvtColor(im, cv2.COLOR_BGR2HSV)
    m = ((hsv[:, :, 2] > 70) & (hsv[:, :, 1] > 60)).astype(np.uint8)
    m[:, :] &= 1
    H, W = m.shape
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15)))
    ff = m.copy(); pad = np.zeros((H + 2, W + 2), np.uint8)
    cv2.floodFill(ff, pad, (0, 0), 1)
    m = m | (1 - ff)
    n, lab, st, _ = cv2.connectedComponentsWithStats(m, connectivity=4)
    big = 1 + int(np.argmax(st[1:, 4])) if n > 1 else 0
    m = (lab == big).astype(np.uint8)
    xs = np.arange(W); src_x = np.clip(np.round(2 * ax - xs).astype(int), 0, W - 1)
    m = m & m[:, src_x]                      # symmetric: keep only what both halves agree on
    if fin > 0:
        m = cv2.morphologyEx(m, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * fin + 1, 2 * fin + 1)))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m, connectivity=4)
    big = 1 + int(np.argmax(st[1:, 4])) if n > 1 else 0
    m = (lab == big).astype(np.uint8)
    cs, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    c = max(cs, key=cv2.contourArea)
    c = cv2.approxPolyDP(c, 2.0, True)[:, 0, :]
    return Polygon(c).buffer(0)

_LIB = None
def lib(rid, cx, cy, w=None, h=None, rot=0, flip=False):
    """A room shape from the traced reference library (tools/trace/shape_library.json): rotated by rot degrees,
    mirrored if flip, scaled to w x h metres (either alone keeps the aspect; neither: true size), centred on (cx, cy)
    plan px (10 px = 1 m). Remembered in SOURCES so the sheet can say which traced room each room came from."""
    global _LIB
    from shapely import affinity
    if _LIB is None:
        _LIB = {r["id"]: r for r in json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "shape_library.json")))["rooms"]}
    g = Polygon(_LIB[rid]["poly"])
    if flip: g = affinity.scale(g, -1, 1, origin=(0, 0))
    if rot: g = affinity.rotate(g, rot, origin=(0, 0))
    x0, y0, x1, y1 = g.bounds; bw, bh = x1 - x0, y1 - y0
    sx = (w / bw) if w else ((h / bh) if h else 1.0)
    sy = (h / bh) if h else sx
    g = affinity.scale(g, sx * PX_PER_M, sy * PX_PER_M, origin=(0, 0))
    g = affinity.translate(g, cx - g.centroid.x, cy - g.centroid.y)
    LAST_FIT.clear(); LAST_FIT.update({"id": rid, "rot": rot, "flip": flip, "aspect_change": round(max(sx / sy, sy / sx), 3)})
    return clean(g.buffer(0))
LAST_FIT = {}

def clean(g, nub=3.0, snap_deg=3.0, short=5.0):
    """Owner: "a door is a gap with a frame, not a bump; snap near-straight edges straight; no edges under 0.5 m".
    Opening and closing by `nub` px removes the traced door alcoves and nubs; edges within snap_deg of the axes are
    made exactly straight; edges shorter than `short` px are dropped."""
    if g.is_empty: return g
    g = g.buffer(-nub, join_style=2).buffer(nub, join_style=2).buffer(nub, join_style=2).buffer(-nub, join_style=2)
    g = max(getattr(g, "geoms", [g]), key=lambda q: q.area).simplify(0.8)
    pts = [list(p) for p in g.exterior.coords[:-1]]
    t = math.tan(math.radians(snap_deg))
    for _ in range(2):
        n = len(pts)
        for i in range(n):
            a, b = pts[i], pts[(i + 1) % n]
            dx, dy = b[0] - a[0], b[1] - a[1]
            if abs(dy) <= t * abs(dx) and abs(dy) > 0: m = (a[1] + b[1]) / 2; a[1] = b[1] = m
            elif abs(dx) <= t * abs(dy) and abs(dx) > 0: m = (a[0] + b[0]) / 2; a[0] = b[0] = m
    out = []
    for p in pts:
        if out and math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) < short: continue
        out.append(p)
    if len(out) > 3 and math.hypot(out[0][0] - out[-1][0], out[0][1] - out[-1][1]) < short: out.pop()
    q = Polygon(out).buffer(0) if len(out) >= 3 else g
    return max(getattr(q, "geoms", [q]), key=lambda r: r.area)

def dedupe(g, eps=0.6):
    """Drop repeated / near-coincident vertices (left by a boolean cut)."""
    out = []
    for p in g.exterior.coords[:-1]:
        if out and math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) < eps: continue
        out.append(p)
    if len(out) > 3 and math.hypot(out[0][0] - out[-1][0], out[0][1] - out[-1][1]) < eps: out.pop()
    k = 0   # (and points in the middle of a straight run)
    while len(out) > 3 and k < len(out):
        a, b, c = out[k - 1], out[k], out[(k + 1) % len(out)]
        if abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) < 0.5 * max(1.0, math.hypot(c[0] - a[0], c[1] - a[1])) * 0.05:
            out.pop(k); continue
        k += 1
    return Polygon(out).buffer(0) if len(out) >= 3 else g

def fit(tags, cx, cy, w, h, max_change=1.3, fill_min=0.0, exclude=(), min_w=3.2):
    """Pick the traced room for a function: from the library rooms tagged `tags` (in order of preference), the one
    whose shape (turned 0 / 90 degrees, mirrored or not) best fits a w x h metre box with its aspect changed by at
    most max_change; scaled to sit inside the box. Returns (polygon, "id ...") and leaves the fit in LAST_FIT."""
    global _LIB
    if _LIB is None: lib("fury_01", 0, 0)
    best = None
    for ti, tag in enumerate(tags):
        for r in _LIB.values():
            if r["tag"] != tag or r["id"] in exclude or r["area_m2"] < 6: continue
            for rot in (0, 90):
                bw, bh = (r["w_m"], r["h_m"]) if rot == 0 else (r["h_m"], r["w_m"])
                a_s, a_t = bw / bh, w / h
                a_f = min(max(a_t, a_s / max_change), a_s * max_change)
                fw, fh = (w, w / a_f) if w / a_f <= h else (h * a_f, h)
                if min(fw, fh) < min_w: continue                     # (owner: no room under 3 m wide)
                score = ti * 0.6 + abs(math.log(a_t / a_s)) + (1 - (fw * fh) / (w * h)) * 0.8
                if best is None or score < best[0]: best = (score, r["id"], rot, fw, fh, r["name"])
    _, rid, rot, fw, fh, nm = best
    g = lib(rid, cx, cy, w=fw, h=fh, rot=rot)
    return g, "%s %s" % (rid, nm)

def _min_width_ok(g, m=3.0):
    r = m * PX_PER_M / 2 - 0.1
    core = g.buffer(-r, join_style=2)
    if core.is_empty: return False
    back = core.buffer(r, join_style=2)
    return back.area >= g.area * 0.85

def tidy(g, blocked, short=5.0, snap_deg=3.0, rounds=4):
    """Clean a cut room's outline without letting it into its neighbours: merge edges under `short` px into one
    point, snap near-axis edges straight, cut the neighbours away again; repeat until it holds."""
    t = math.tan(math.radians(snap_deg))
    for _ in range(rounds):
        pts = [list(p) for p in g.exterior.coords[:-1]]
        changed = False
        out = []
        for p in pts:
            if out and math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) < short:
                out[-1] = [(p[0] + out[-1][0]) / 2, (p[1] + out[-1][1]) / 2]; changed = True; continue
            out.append(p)
        if len(out) > 3 and math.hypot(out[0][0] - out[-1][0], out[0][1] - out[-1][1]) < short: out.pop(); changed = True
        n = len(out)
        for i in range(n):
            a, b = out[i], out[(i + 1) % n]
            dx, dy = b[0] - a[0], b[1] - a[1]
            if 0.01 < abs(dy) <= t * abs(dx): b[1] = a[1]; changed = True
            elif 0.01 < abs(dx) <= t * abs(dy): b[0] = a[0]; changed = True
        if len(out) < 3: break
        q = Polygon(out).buffer(0)
        if blocked is not None: q = q.difference(blocked)
        q = max(getattr(q, "geoms", [q]), key=lambda r: r.area)
        g = dedupe(q)
        if not changed: break
    return g

def settle(R, HALLS, whole=(), grow=3.0, twins=None, mirror_fn=None, mode="close"):
    """Owner: "no room may overlap another room, a corridor, a lift or the hull" / "one wall line" / "service space
    at least 1 m". Rooms in `whole` (round rooms, octagons, lift cars, the brig: shapes that are their job) are placed
    first and never cut. Every other room grows a little, then any gap under 1 m left to a neighbour or a corridor
    is closed (the strip between them joins the room), then it loses what a hallway, a whole room or an earlier room
    holds: neighbours share ONE wall; anything further apart is service space (>= 1 m). twins {port: starboard}: the
    starboard room is the port room mirrored (mirror_fn), so both sides stay exactly alike."""
    from shapely.ops import unary_union
    twins = twins or {}; stb = set(twins.values())
    blocked = [unary_union(HALLS)] + [R[k] for k in R if k in whole]
    out = {}
    for k, g in R.items():
        if k in whole: out[k] = g; continue
        if k in stb: continue
        B = unary_union(blocked)
        if mode == "simple":       # (the owner-preferred pass 2a look: grow a little, wrap the neighbours, keep the gaps as service)
            g = clean(g.buffer(4.0, join_style=2).simplify(0.5)).difference(B)
            g = tidy(dedupe(max(getattr(g, "geoms", [g]), key=lambda q: q.area)), B)
            out[k] = g; blocked.append(g)
            if k in twins and mirror_fn: out[twins[k]] = mirror_fn(g); blocked.append(out[twins[k]])
            continue
        g = clean(g.buffer(grow, join_style=2).simplify(0.5))
        near = g.buffer(10.0, join_style=2).intersection(B.buffer(10.0, join_style=2)).difference(B)   # (a sub-1 m gap: close it)
        g = clean(unary_union([g, near]), nub=6.0).difference(B)       # (closing by 6 px: no steps where a neighbour ends)
        g = dedupe(max(getattr(g, "geoms", [g]), key=lambda q: q.area))
        g = tidy(g, B, rounds=8)
        out[k] = g; blocked.append(g)
        if k in twins and mirror_fn:
            out[twins[k]] = mirror_fn(g); blocked.append(out[twins[k]])
    return {k: out[k] for k in R}

def finalize(R, HALLS, order, twins=None, mirror_fn=None, keep=()):
    """Last pass before the check: each room (port / centre; starboard = its mirror) is tidied against EVERYTHING
    else (corridors, connectors and every other room), so nothing overlaps and the outlines stay clean."""
    from shapely.ops import unary_union
    twins = twins or {}; stb = set(twins.values()); R = dict(R)
    from shapely import set_precision
    for k in R:                                   # (whole pixels: no sub-pixel slants or steps between neighbours)
        if k in keep and len(R[k].exterior.coords) > 40: continue      # (round rooms stay true circles)
        R[k] = set_precision(R[k], 1.0)
    HU = unary_union(HALLS)
    for k in order:
        if k in keep or k in stb: continue
        others = unary_union([HU] + [R[o] for o in R if o != k and o != twins.get(k)])
        g = R[k].difference(others)
        for nb in [HU] + [R[o] for o in R if o != k and o != twins.get(k)]:   # (a gap under 1 m to anything: close it, one wall)
            d = g.distance(nb)
            if 0.05 < d < 10.0:
                strip = g.buffer(d + 0.6, join_style=2).intersection(nb.buffer(d + 0.6, join_style=2)).difference(nb)
                g = unary_union([g, strip]).buffer(0.2, join_style=2).buffer(-0.2, join_style=2)
        g = max(getattr(g, "geoms", [g]), key=lambda q: q.area)
        R[k] = set_precision(tidy(g.difference(others), others, rounds=8), 1.0)
        R[k] = dedupe(max(getattr(R[k], "geoms", [R[k]]), key=lambda q: q.area))
        if k in twins and mirror_fn: R[twins[k]] = mirror_fn(R[k])
    return R

def label_box(g, t, at=None):
    """Where a room's label goes: lines, font scale and its box (x0, y0, x1, y1). Shrinks / wraps to fit the room."""
    from shapely.geometry import Point
    c = Point(at) if at else g.representative_point(); words = t.split(); s = 0.34
    best = None
    for lines in ([t], [" ".join(words[:(len(words) + 1) // 2]), " ".join(words[(len(words) + 1) // 2:])] if len(words) > 1 else None):
        if lines is None: continue
        for sc in [0.34 - 0.02 * i for i in range(8)]:
            sz = [cv2.getTextSize(l, cv2.FONT_HERSHEY_SIMPLEX, sc, 1)[0] for l in lines]
            w = max(z[0] for z in sz); h = sum(z[1] + 4 for z in sz)
            bx = box(c.x - w / 2 - 1, c.y - h / 2 - 1, c.x + w / 2 + 1, c.y + h / 2 + 1)
            if g.buffer(-1).contains(bx): return lines, sc, bx
            if best is None: best = (lines, sc, bx)
    return best

def check(R, HALLS, DOORS, hullp, features, labels, floor, walls, start, whole=(), fits=None, niches=(), round_rooms=(), lift_ok=None, soft=()):
    """The owner's automatic check, run on every plan: 1 no overlaps, 2 inside the hull (shrunk by the wall),
    3 reachable through doors from the lift, 4 furniture 0.3 m inside its room, 5 labels inside their room,
    6 no double walls (two things either share one wall or stand at least 1 m apart: service space), 7 lifts lined up
    with the other decks, 8 aspect change of every traced room <= 1.4x, 9 every room at least 3 m wide, 10 clean
    edges (straight within 3 degrees, none under 0.5 m), 11 doors only between walkable spaces, niches inside rooms."""
    from shapely.ops import unary_union
    HU = unary_union(HALLS); fails = {i: [] for i in range(1, 12)}
    ks = list(R)
    for i, a in enumerate(ks):
        for b in ks[i + 1:]:
            if not R[a].intersection(R[b]).buffer(-0.5).is_empty: fails[1].append("%s / %s" % (a, b))
            elif 1.0 < R[a].distance(R[b]) < 10.0: fails[6].append("%s / %s" % (a, b))
        if not R[a].intersection(HU).buffer(-0.5).is_empty: fails[1].append("%s / a corridor near %s" % (a, [round(v) for v in R[a].intersection(HU).bounds]))
        elif 1.0 < R[a].distance(HU) < 10.0: fails[6].append("%s / a corridor" % a)
    inner_hull = hullp.buffer(-T)
    for k, g in R.items():
        if not inner_hull.contains(g.buffer(-0.5)): fails[2].append(k)
    S = Ship("check", ".", SRC_FOR_CHECK[0], 0, R, HALLS, DOORS, start)
    for k, ok in reach(S, floor, walls, start).items():
        if not ok: fails[3].append(k)
    for k, fs in features.items():
        room_in = R[k].buffer(-3.0)
        for f in fs:
            if not room_in.contains(f): fails[4].append(k)
    for k, (lines, sc, bx) in labels.items():
        if not R[k].buffer(-1).contains(bx): fails[5].append(k)
    if lift_ok: fails[7] += lift_ok
    for k, ch in (fits or {}).items():
        if ch > 1.4: fails[8].append("%s %.2fx" % (k, ch))
    for k, g in R.items():
        if not k.startswith("Lift") and not _min_width_ok(g): fails[9].append(k)   # (a lift car is the main deck's shaft)
    t3 = math.tan(math.radians(3.0))
    for k, g in R.items():
        if k in round_rooms: continue
        pts = list(g.exterior.coords)
        for (ax_, ay), (bx_, by) in zip(pts, pts[1:]):
            L_ = math.hypot(bx_ - ax_, by - ay); dx, dy = abs(bx_ - ax_), abs(by - ay)
            if L_ < 1.5: continue            # (sub-pixel joins from the boolean cuts: not a visible edge)
            if L_ < 4.9 or (0.01 < dy <= t3 * dx and dy > 1.0) or (0.01 < dx <= t3 * dy and dx > 1.0):
                fails[10].append(k); break
    walk = unary_union(list(R.values()) + [HU]).buffer(0.01)
    for x, y, o in DOORS:
        e = T + 3.0
        pa, pb = ((x, y - e), (x, y + e)) if o == "h" else ((x - e, y), (x + e, y))
        from shapely.geometry import Point
        if not (walk.contains(Point(pa)) and walk.contains(Point(pb))): fails[11].append("door at %s" % ((round(x), round(y)),))
    for rk, nb, lab in niches:
        if not R[rk].buffer(0.3).contains(nb): fails[11].append("niche in %s" % rk)
    names = {1: "rooms overlap", 2: "outside the hull", 3: "not reachable through doors", 4: "furniture through a wall",
             5: "label across a wall", 6: "double wall (gap < 1 m)", 7: "lifts not lined up", 8: "shape stretched > 1.4x",
             9: "room under 3 m wide", 10: "edges not clean", 11: "door / niche onto service"}
    n = sum(len(v) for i, v in fails.items() if i not in soft)
    print("CHECK: %d failure(s)" % n)
    for i in range(1, 12):
        print("  %2d %-28s %s" % (i, names[i], "OK" if not fails[i] else ("WARN: " if i in soft else "FAIL: ") + "; ".join(fails[i])))
    return [names[i] + ": " + f for i in fails if i not in soft for f in fails[i]]
SRC_FOR_CHECK = [None]
def k_whole(k, whole): return k in whole

def _label(im, lab, col):
    lines, sc, bx = lab
    x0, y0, x1, y1 = bx.bounds; y = y0 + 1
    for l in lines:
        (w, h), _ = cv2.getTextSize(l, cv2.FONT_HERSHEY_SIMPLEX, sc, 1)
        y += h + 2
        cv2.putText(im, l, (int((x0 + x1) / 2 - w / 2), int(y)), cv2.FONT_HERSHEY_SIMPLEX, sc, col, 1, cv2.LINE_AA)
        y += 2

def _draw(S, floor, walls, hullp, main_floor, lifts, title, png, jpg, features, labels, nfail, extra=None):
    src = cv2.imread(S.src)
    plan = np.zeros_like(src); ov = (src * 0.35).astype(np.uint8)
    mf = raster(main_floor, src.shape[:2]) > 0
    plan[mf] = (24, 24, 24)
    hp = np.array(hullp.exterior.coords, np.int32)
    for im in (plan, ov): cv2.polylines(im, [hp], True, (60, 60, 220), 2, cv2.LINE_AA)
    fl = raster(floor, src.shape[:2]) > 0
    ov[fl] = (ov[fl] * 0.5).astype(np.uint8)
    if extra:
        outline, svc, svc_names, NICHE, hatches, cover = extra
        sm = raster(svc, src.shape[:2]) > 0        # service space: dark grey, not walkable
        plan[sm] = (58, 58, 58); ov[sm] = (58, 58, 58)
        om = raster(outline.boundary.buffer(T / 2, join_style=2), src.shape[:2]) > 0
        plan[om] = (255, 255, 255); ov[om] = (255, 255, 255)
    plan[fl] = (70, 38, 12)                         # this deck's floor: dark blue (the main deck under it: grey)
    wm = raster(walls, src.shape[:2]) > 0
    plan[wm] = (255, 255, 255); ov[wm] = (255, 255, 255)
    for f in [f for fs in features.values() for f in fs]:   # furniture / function lines: not walls
        for g in getattr(f, "geoms", [f]):
            ring = g.exterior if g.geom_type == "Polygon" else g
            for im in (plan, ov): cv2.polylines(im, [np.array(ring.coords, np.int32)], g.geom_type == "Polygon", (70, 170, 210), 1, cv2.LINE_AA)
    if extra:
        n = 0
        for p in sorted(getattr(svc, "geoms", [svc]), key=lambda q: -q.area):   # small labels on the bigger service pieces
            if p.area < 150: continue
            c = p.representative_point(); t = svc_names[n % len(svc_names)] if svc_names else "service"; n += 1
            (w, h), _ = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, 0.27, 1)
            if not p.buffer(-1).contains(box(c.x - w / 2, c.y - h / 2, c.x + w / 2, c.y + h / 2)):
                t = t[:5]; (w, h), _ = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, 0.24, 1)
                if not p.buffer(-0.5).contains(box(c.x - w / 2, c.y - h / 2, c.x + w / 2, c.y + h / 2)): continue
            for im in (plan, ov): cv2.putText(im, t, (int(c.x - w / 2), int(c.y + h / 2)), cv2.FONT_HERSHEY_SIMPLEX, 0.27, (170, 170, 170), 1, cv2.LINE_AA)
        for rk, nb, lab in NICHE:
            x0, y0, x1, y1 = [int(round(v)) for v in nb.bounds]
            for im in (plan, ov):
                cv2.rectangle(im, (x0, y0), (x1, y1), (90, 200, 120), -1)
                cv2.putText(im, lab[0].upper(), (x0 + (x1 - x0) // 2 - 3, y1 - 1), cv2.FONT_HERSHEY_SIMPLEX, 0.26, (10, 40, 10), 1, cv2.LINE_AA)
        for (x, y), o in hatches:   # maintenance hatches into the service space: a short orange dash on the corridor wall
            for im in (plan, ov):
                if o == "v": cv2.line(im, (int(x), int(y - 6)), (int(x), int(y + 6)), (0, 140, 255), 3)
                else: cv2.line(im, (int(x - 6), int(y)), (int(x + 6), int(y)), (0, 140, 255), 3)
    for (x, y) in lifts:
        for im in (plan, ov):
            cv2.rectangle(im, (int(x - 9), int(y - 9)), (int(x + 9), int(y + 9)), (0, 200, 255), 2)
    for x, y in S.PROPOSED_DOORS:
        for im in (plan, ov): cv2.circle(im, (int(x), int(y)), 14, (0, 200, 255), 2, cv2.LINE_AA)
    for k, lab in labels.items():
        for im in (plan, ov): _label(im, lab, (255, 220, 120))
    for im in (plan, ov):
        cv2.putText(im, title, (24, src.shape[0] - 30), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 255, 255), 2, cv2.LINE_AA)
        cv2.putText(im, "PROPOSED  red = hull  dark grey = service space  green = niches (C console L locker M med F fuse W weapons S shelves P pod hatch)  orange = maintenance hatches  gold = lifts  CHECK: %d failures" % nfail, (24, src.shape[0] - 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.42, (180, 180, 180), 1, cv2.LINE_AA)
    cv2.imwrite(png, plan); cv2.imwrite(jpg, ov, [cv2.IMWRITE_JPEG_QUALITY, 86])

def run(sid, here, src, ax, name, level, R, HALLS, DOORS, lifts, start=None, proposed=(), fin=14, title=None,
        features=None, short=None, whole=(), anchor=None, service=(), niches=(), hatches=(), source=None, coverage=(0.55, 0.65),
        fits=None, round_rooms=(), lift_ok=None, outline_style="close", soft=()):
    """Build one composed deck, run the owner's automatic check on it and draw it (the check result is printed and
    written on the picture). features: {room: [polygons / lines]}; short: {room: label}. Returns the failures."""
    hullp = hull(src, ax, fin)
    # niches (owner: "niches are not doors"): a small recess on the ROOM side of a wall, the wall whole behind it,
    # drawn as a filled box with its letter (C console, L locker, M med station, F fuse box, W weapon rack, S shelves,
    # P pod hatch); never touching the service space
    R = dict(R); NICHE = []
    for rk, (x, y), side, lab in niches:
        nb = {"n": box(x - 6, y + 2.5, x + 6, y + 9.5), "s": box(x - 6, y - 9.5, x + 6, y - 2.5),
              "w": box(x + 2.5, y - 6, x + 9.5, y + 6), "e": box(x - 9.5, y - 6, x - 2.5, y + 6)}[side]
        NICHE.append((rk, nb, lab))
    S = Ship(sid + "_" + name, here, src, ax, R, HALLS, DOORS, start or lifts[0], proposed)
    floor, walls = build(S)
    # the deck's structure: everything round and between the rooms inside the deck's outline is SERVICE SPACE
    used = unary_union(list(R.values()) + list(HALLS))
    if outline_style == "ring":   # (pass 2a: the deck's structure runs 1 m round the outer rooms)
        outline = used.buffer(10, join_style=2).buffer(8).buffer(-8).intersection(hullp.buffer(-T / 2))
    else:
        outline = used.buffer(30, join_style=2).buffer(-30, join_style=2).intersection(hullp.buffer(-T / 2))   # (one wall line: the deck's edge IS the outer rooms' walls)
    outline = max(getattr(outline, "geoms", [outline]), key=lambda q: q.area)
    outline = Polygon(outline.exterior)            # (no holes: the space between the rooms is structure too)
    svc = outline.difference(used.buffer(T / 2, join_style=2))
    cover = unary_union(list(R.values())).area / outline.area
    features = features or {}; short = short or {}
    labels = {k: label_box(g, short.get(k, k).upper(), (anchor or {}).get(k)) for k, g in R.items()}
    SRC_FOR_CHECK[0] = src
    bad = check(R, HALLS, DOORS, hullp, features, labels, floor, walls, S.START, whole, fits, NICHE, round_rooms, lift_ok, soft)
    print("  12 rooms / deck area           %.0f%% %s" % (cover * 100, "OK" if coverage[0] <= cover <= coverage[1] else "FAIL (want %d-%d%%)" % (coverage[0] * 100, coverage[1] * 100)))
    if not coverage[0] <= cover <= coverage[1]: bad.append("rooms cover %.0f%% of the deck" % (cover * 100))
    for x, y in lifts:
        if not floor.contains(box(x - 3, y - 3, x + 3, y + 3)): bad.append("no floor at lift %s" % ((x, y),))
    P = json.load(open(os.path.join(here, "plan.json")))
    main_floor = shape(P["floor"])
    _draw(S, floor, walls, hullp, main_floor, lifts, title or name.upper() + " DECK",
          os.path.join(here, "deck_%s.png" % name), os.path.join(here, "deck_%s_on_map.jpg" % name), features, labels, len(bad),
          extra=(outline, svc, list(service), NICHE, list(hatches), cover))
    json.dump({"ship": sid, "deck": name, "level": level, "proposed": True, "units": "source px", "px_per_m": PX_PER_M,
               "thickness": T, "door": DOOR, "mirror_x": ax, "start": S.START, "lifts": [list(l) for l in lifts],
               "features": {k: [mapping(f) for f in fs] for k, fs in features.items()},
               "rooms": {k: mapping(g) for k, g in R.items()}, "halls": [mapping(h) for h in HALLS],
               "center_y": S.center_y, "doors": DOORS, "proposed_doors": list(proposed), "floor": mapping(floor),
               "walls": mapping(walls), "hull": mapping(hullp), "check_failures": bad, "outline": mapping(outline),
               "service": mapping(svc), "rooms_cover": round(cover, 3), "from_library": source or {}},
              open(os.path.join(here, "deck_%s.json" % name), "w"))
    print(sid, name, "rooms", len(R), "doors", len(DOORS), "-> %d failure(s)" % len(bad))
    return bad

def both(path_png_a, path_png_b, out_jpg):
    """The two decks side by side (one picture for the owner)."""
    a = cv2.imread(path_png_a); b = cv2.imread(path_png_b)
    h = max(a.shape[0], b.shape[0])
    pad = lambda im: cv2.copyMakeBorder(im, 0, h - im.shape[0], 0, 0, cv2.BORDER_CONSTANT)
    out = np.hstack([pad(a), np.full((h, 12, 3), 90, np.uint8), pad(b)])
    s = min(1.0, 1800.0 / out.shape[1])
    out = cv2.resize(out, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
    cv2.imwrite(out_jpg, out, [cv2.IMWRITE_JPEG_QUALITY, 86])

def source_sheet(deck_jsons, out_jpg):
    """One card per composed room: the traced reference room it came from (left, true shape) and the room as placed
    on the deck (right), with both names: the owner sees where every room's shape comes from."""
    libr = {r["id"]: r for r in json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "shape_library.json")))["rooms"]}
    cards = []
    for p in deck_jsons:
        D = json.load(open(p))
        for k, src in D.get("from_library", {}).items():
            cards.append((D["deck"], k, src, shape(D["rooms"][k])))
    CW, CH, cols = 300, 120, 6
    rows = (len(cards) + cols - 1) // cols
    img = np.zeros((rows * CH + 40, cols * CW, 3), np.uint8)
    cv2.putText(img, "WHERE EACH ROOM'S SHAPE COMES FROM  (left: traced reference room   right: the room on the deck)", (10, 26), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1, cv2.LINE_AA)
    def put(g, cx, cy, k, col):
        x0, y0, x1, y1 = g.bounds; c = g.centroid
        pts = np.array([[cx + (x - c.x) * k, cy + (y - c.y) * k] for x, y in g.exterior.coords], np.int32)
        cv2.fillPoly(img, [pts], (70, 38, 12)); cv2.polylines(img, [pts], True, col, 1, cv2.LINE_AA)
    for n, (deck, k, src, g) in enumerate(cards):
        ox, oy = (n % cols) * CW, (n // cols) * CH + 40
        cv2.rectangle(img, (ox + 2, oy + 2), (ox + CW - 3, oy + CH - 3), (60, 60, 60), 1)
        rid = src.split(" ")[0]
        if rid in libr:
            lp = Polygon(libr[rid]["poly"]); x0, y0, x1, y1 = lp.bounds
            put(lp, ox + 70, oy + 52, min(70.0 / max(x1 - x0, 1e-6), 70.0 / max(y1 - y0, 1e-6)), (160, 160, 160))
        x0, y0, x1, y1 = g.bounds
        put(g, ox + 220, oy + 52, min(70.0 / max(x1 - x0, 1e-6), 70.0 / max(y1 - y0, 1e-6)), (255, 255, 255))
        cv2.putText(img, "%s: %s" % (deck.upper(), k)[:40], (ox + 6, oy + CH - 22), cv2.FONT_HERSHEY_SIMPLEX, 0.36, (255, 220, 120), 1, cv2.LINE_AA)
        cv2.putText(img, src[:46], (ox + 6, oy + CH - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.32, (170, 170, 170), 1, cv2.LINE_AA)
    cv2.imwrite(out_jpg, img, [cv2.IMWRITE_JPEG_QUALITY, 86])


class Deck:
    """Rooms, halls, doors, niches and hatches of one composed deck, and which traced room each room came from;
    the port side is mirrored to starboard about the ship's axis `ax`."""
    def __init__(s, ax):
        from planlib import mirror
        s.AX = ax; s.M = mirror(ax)
        s.R, s.H, s.D, s.FROM, s.F, s.NICHE, s.HATCH, s.TW, s.FIT = {}, [], [], {}, {}, [], [], {}, {}
    def room(s, name, g, src=None, twin=None, feat=()):
        if isinstance(g, tuple): g, src = g
        s.R[name] = g; s.FROM[name] = src; s.F[name] = list(feat)
        if src and not src.startswith("lift") and LAST_FIT: s.FIT[name] = LAST_FIT["aspect_change"]
        if twin:
            s.R[twin] = s.M(g); s.FROM[twin] = src + " (mirrored)"; s.F[twin] = [s.M(f) for f in feat]; s.TW[name] = twin
            if name in s.FIT: s.FIT[twin] = s.FIT[name]
    def ctr(s, name): c = s.R[name].centroid; return c.x, c.y
    def feat(s, name, fs):
        s.F[name] = list(fs)
        if name in s.TW: s.F[s.TW[name]] = [s.M(q) for q in fs]
    def hall(s, g, both=True):
        s.H.append(g)
        if both: s.H.append(s.M(g))
    def door(s, x, y, o, both=True):
        s.D.append((x, y, o))
        if both and abs(x - s.AX) > 1: s.D.append((round(2 * s.AX - x, 1), y, o))
    def link(s, name, to, w=16, both=True):
        """A short connector from the room's wall to the corridor point `to` (straight along x or y); the door on the
        room's wall where it meets it (no connector if the room already meets the corridor there)."""
        from shapely.geometry import LineString, Point
        from planlib import hall
        g = s.R[name]; tx, ty = to; c = g.centroid
        horiz = abs(tx - c.x) > abs(ty - c.y)
        ray = LineString([(c.x, ty), (tx, ty)]) if horiz else LineString([(tx, c.y), (tx, ty)])
        hit = g.boundary.intersection(ray)
        pts = [p for p in getattr(hit, "geoms", [hit]) if not p.is_empty and p.geom_type == "Point"]
        if not pts:
            if g.distance(Point(tx, ty)) < 1.5: s.door(tx, ty, "v" if horiz else "h", both); return
            raise SystemExit("link %s -> %s: the connector misses the room" % (name, to))
        if horiz:
            px = round(min(pts, key=lambda p: abs(p.x - tx)).x, 1)
            ex = tx + (3 if tx > px else -3)        # (2-3 px into the corridor: the two always join)
            if abs(px - tx) > 1.0: s.stub(name, hall((px, ty), (ex, ty), w=w).difference(g), both)
            s.door(px, ty, "v", both)
        else:
            py = round(min(pts, key=lambda p: abs(p.y - ty)).y, 1)
            ey = ty + (3 if ty > py else -3)
            if abs(py - ty) > 1.0: s.stub(name, hall((tx, py), (tx, ey), w=w).difference(g), both)
            s.door(tx, py, "h", both)
    def stub(s, name, h, both):
        for hh in ([h, s.M(h)] if both else [h]):
            s.H.append(hh)
            for k in list(s.R):
                if k != name and k != s.TW.get(name) and s.R[k].intersection(hh).area > 0.5:
                    q = s.R[k].difference(hh.buffer(0.01)); q = max(getattr(q, "geoms", [q]), key=lambda r: r.area)
                    s.R[k] = dedupe(q)
    def niche(s, name, at, side, lab, both=True):
        s.NICHE.append((name, at, side, lab))
        if both and name in s.TW: s.NICHE.append((s.TW[name], (2 * s.AX - at[0], at[1]), {"e": "w", "w": "e"}.get(side, side), lab))
    def wallniche(s, name, side, off, lab, both=True):
        from shapely.geometry import LineString
        g = s.R[name]; c = g.centroid; x0, y0, x1, y1 = g.bounds
        for o2 in [off, off + 10, off - 10, off + 20, off - 20, off + 30, off - 30]:
            if side in "ns": ray = LineString([(c.x + o2, c.y), (c.x + o2, y0 - 1 if side == "n" else y1 + 1)])
            else: ray = LineString([(c.x, c.y + o2), (x0 - 1 if side == "w" else x1 + 1, c.y + o2)])
            hit = g.exterior.intersection(ray)
            pts = [p for p in getattr(hit, "geoms", [hit]) if p.geom_type == "Point"]
            if not pts: continue
            far = max(pts, key=lambda p: p.distance(c)); x, y = far.x, far.y
            nb = {"n": box(x - 6, y + 2.5, x + 6, y + 9.5), "s": box(x - 6, y - 9.5, x + 6, y - 2.5),
                  "w": box(x + 2.5, y - 6, x + 9.5, y + 6), "e": box(x - 9.5, y - 6, x - 2.5, y + 6)}[side]
            if g.contains(nb) and (name not in s.TW or s.R[s.TW[name]].contains(s.M(nb))):
                s.niche(name, (round(x, 1), round(y, 1)), side, lab, both); return
        print("  (no room for a niche on the %s wall of %s)" % (side, name))
    def hatch(s, at, o, both=True):
        s.HATCH.append((at, o))
        if both and abs(at[0] - s.AX) > 1: s.HATCH.append(((2 * s.AX - at[0], at[1]), o))
