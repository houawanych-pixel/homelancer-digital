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
import json, os
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
    return g.buffer(0)

def settle(R, HALLS, whole=(), grow=4.0):
    """Owner: "no room may overlap another room, a corridor, a lift or the hull". Rooms in `whole` (round rooms,
    octagons, lift cars, cells: rooms whose shape is their job) are placed first and never cut; check() fails if one
    touches anything it shouldn't. Every other room grows by `grow` px (so neighbours meet on ONE shared wall, no
    double lines) and then loses whatever a hallway, a whole room or an earlier room already holds: it wraps them."""
    from shapely.ops import unary_union
    blocked = [unary_union(HALLS)] + [R[k] for k in R if k in whole]
    out = {}
    for k, g in R.items():
        if k in whole: out[k] = g; continue
        g = g.buffer(grow, join_style=2).simplify(0.5).difference(unary_union(blocked))
        g = max(getattr(g, "geoms", [g]), key=lambda q: q.area)
        out[k] = g; blocked.append(g)
    return {k: out[k] for k in R}

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

def check(R, HALLS, DOORS, hullp, features, labels, floor, walls, start, whole=()):
    """The owner's automatic check, run on every plan: 1 rooms don't overlap rooms, 2 rooms inside the hull (shrunk by
    the wall), 3 every room reachable through the doors from the lift, 4 furniture 0.3 m inside its room, 5 labels
    inside their room; plus: no room over a corridor, whole rooms (round / lift / cells) not cut, no sliver gaps."""
    from shapely.ops import unary_union
    HU = unary_union(HALLS); fails = {1: [], 2: [], 3: [], 4: [], 5: [], 6: []}
    ks = list(R)
    for i, a in enumerate(ks):
        for b in ks[i + 1:]:
            if R[a].intersection(R[b]).area > 0.5: fails[1].append("%s / %s" % (a, b))
            elif 0.05 < R[a].distance(R[b]) < T - 0.1: fails[6].append("sliver gap %s / %s" % (a, b))
        if R[a].intersection(HU).area > 0.5: fails[1].append("%s / a corridor" % a)
        elif k_whole(a, whole) and 0.05 < R[a].distance(HU) < T - 0.1: fails[6].append("sliver gap %s / a corridor" % a)
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
    names = {1: "rooms overlap", 2: "outside the hull", 3: "not reachable through doors", 4: "furniture through a wall",
             5: "label across a wall", 6: "other"}
    n = sum(len(v) for v in fails.values())
    print("CHECK: %d failure(s)" % n)
    for i in range(1, 7):
        print("  %d %-28s %s" % (i, names[i], "OK" if not fails[i] else "FAIL: " + "; ".join(fails[i])))
    return [names[i] + ": " + f for i in fails for f in fails[i]]
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
        for nb, lab in NICHE:
            c = nb.centroid
            for im in (plan, ov):
                cv2.rectangle(im, (int(nb.bounds[0]) + 2, int(nb.bounds[1]) + 2), (int(nb.bounds[2]) - 2, int(nb.bounds[3]) - 2), (90, 200, 120), -1)
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
        cv2.putText(im, "PROPOSED  red = hull  dark grey = service space  green = wall niches  orange = maintenance hatches  gold = lifts  CHECK: %d failures" % nfail, (24, src.shape[0] - 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.42, (180, 180, 180), 1, cv2.LINE_AA)
    cv2.imwrite(png, plan); cv2.imwrite(jpg, ov, [cv2.IMWRITE_JPEG_QUALITY, 86])

def run(sid, here, src, ax, name, level, R, HALLS, DOORS, lifts, start=None, proposed=(), fin=14, title=None,
        features=None, short=None, whole=(), anchor=None, service=(), niches=(), hatches=(), source=None, coverage=(0.55, 0.65)):
    """Build one composed deck, run the owner's automatic check on it and draw it (the check result is printed and
    written on the picture). features: {room: [polygons / lines]}; short: {room: label}. Returns the failures."""
    hullp = hull(src, ax, fin)
    # niches: small recesses cut into the thick service walls, opening into their room (consoles, lockers, panels)
    R = dict(R); NICHE = []
    for rk, (x, y), side, lab in niches:
        w, d = (14, 6) if side in "ns" else (6, 14)
        nb = {"n": box(x - 7, y - 6, x + 7, y + 3), "s": box(x - 7, y - 3, x + 7, y + 6), "w": box(x - 6, y - 7, x + 3, y + 7), "e": box(x - 3, y - 7, x + 6, y + 7)}[side]
        g = unary_union([R[rk], nb]).buffer(0)
        R[rk] = max(getattr(g, "geoms", [g]), key=lambda q: q.area); NICHE.append((nb, lab))
    S = Ship(sid + "_" + name, here, src, ax, R, HALLS, DOORS, start or lifts[0], proposed)
    floor, walls = build(S)
    # the deck's structure: everything round and between the rooms inside the deck's outline is SERVICE SPACE
    used = unary_union(list(R.values()) + list(HALLS))
    outline = used.buffer(10, join_style=2).buffer(8).buffer(-8).intersection(hullp.buffer(-T / 2))
    outline = max(getattr(outline, "geoms", [outline]), key=lambda q: q.area)
    outline = Polygon(outline.exterior)            # (no holes: the space between the rooms is structure too)
    svc = outline.difference(used.buffer(T / 2, join_style=2))
    cover = unary_union(list(R.values())).area / outline.area
    features = features or {}; short = short or {}
    labels = {k: label_box(g, short.get(k, k).upper(), (anchor or {}).get(k)) for k, g in R.items()}
    SRC_FOR_CHECK[0] = src
    bad = check(R, HALLS, DOORS, hullp, features, labels, floor, walls, S.START, whole)
    print("  7 rooms / deck area            %.0f%% %s" % (cover * 100, "OK" if coverage[0] <= cover <= coverage[1] else "FAIL (want %d-%d%%)" % (coverage[0] * 100, coverage[1] * 100)))
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
