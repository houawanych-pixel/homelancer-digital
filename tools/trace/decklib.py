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

def _draw(S, floor, walls, hullp, main_floor, lifts, title, png, jpg, features, labels, nfail):
    src = cv2.imread(S.src)
    plan = np.zeros_like(src); ov = (src * 0.35).astype(np.uint8)
    mf = raster(main_floor, src.shape[:2]) > 0
    plan[mf] = (40, 40, 40); ov[mf] = (ov[mf] * 0.6 + np.array([40, 40, 40]) * 0.4).astype(np.uint8)
    hp = np.array(hullp.exterior.coords, np.int32)
    for im in (plan, ov): cv2.polylines(im, [hp], True, (60, 60, 220), 2, cv2.LINE_AA)
    fl = raster(floor, src.shape[:2]) > 0
    ov[fl] = (ov[fl] * 0.5).astype(np.uint8)
    plan[fl] = (70, 38, 12)                         # this deck's floor: dark blue (the main deck under it: grey)
    wm = raster(walls, src.shape[:2]) > 0
    plan[wm] = (255, 255, 255); ov[wm] = (255, 255, 255)
    for f in [f for fs in features.values() for f in fs]:   # furniture / function lines: not walls
        for g in getattr(f, "geoms", [f]):
            ring = g.exterior if g.geom_type == "Polygon" else g
            for im in (plan, ov): cv2.polylines(im, [np.array(ring.coords, np.int32)], g.geom_type == "Polygon", (70, 170, 210), 1, cv2.LINE_AA)
    for (x, y) in lifts:
        for im in (plan, ov):
            cv2.rectangle(im, (int(x - 9), int(y - 9)), (int(x + 9), int(y + 9)), (0, 200, 255), 2)
    for x, y in S.PROPOSED_DOORS:
        for im in (plan, ov): cv2.circle(im, (int(x), int(y)), 14, (0, 200, 255), 2, cv2.LINE_AA)
    for k, lab in labels.items():
        for im in (plan, ov): _label(im, lab, (255, 220, 120))
    for im in (plan, ov):
        cv2.putText(im, title, (24, src.shape[0] - 30), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 255, 255), 2, cv2.LINE_AA)
        cv2.putText(im, "PROPOSED (no blueprint)  red = hull   grey = main deck   gold = lifts   CHECK: %d failures" % nfail, (24, src.shape[0] - 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.42, (180, 180, 180), 1, cv2.LINE_AA)
    cv2.imwrite(png, plan); cv2.imwrite(jpg, ov, [cv2.IMWRITE_JPEG_QUALITY, 86])

def run(sid, here, src, ax, name, level, R, HALLS, DOORS, lifts, start=None, proposed=(), fin=14, title=None,
        features=None, short=None, whole=(), anchor=None):
    """Build one composed deck, run the owner's automatic check on it and draw it (the check result is printed and
    written on the picture). features: {room: [polygons / lines]}; short: {room: label}. Returns the failures."""
    S = Ship(sid + "_" + name, here, src, ax, R, HALLS, DOORS, start or lifts[0], proposed)
    floor, walls = build(S)
    hullp = hull(src, ax, fin)
    features = features or {}; short = short or {}
    labels = {k: label_box(g, short.get(k, k).upper(), (anchor or {}).get(k)) for k, g in R.items()}
    SRC_FOR_CHECK[0] = src
    bad = check(R, HALLS, DOORS, hullp, features, labels, floor, walls, S.START, whole)
    for x, y in lifts:
        if not floor.contains(box(x - 3, y - 3, x + 3, y + 3)): bad.append("no floor at lift %s" % ((x, y),))
    P = json.load(open(os.path.join(here, "plan.json")))
    main_floor = shape(P["floor"])
    _draw(S, floor, walls, hullp, main_floor, lifts, title or name.upper() + " DECK",
          os.path.join(here, "deck_%s.png" % name), os.path.join(here, "deck_%s_on_map.jpg" % name), features, labels, len(bad))
    json.dump({"ship": sid, "deck": name, "level": level, "proposed": True, "units": "source px", "px_per_m": PX_PER_M,
               "thickness": T, "door": DOOR, "mirror_x": ax, "start": S.START, "lifts": [list(l) for l in lifts],
               "features": {k: [mapping(f) for f in fs] for k, fs in features.items()},
               "rooms": {k: mapping(g) for k, g in R.items()}, "halls": [mapping(h) for h in HALLS],
               "center_y": S.center_y, "doors": DOORS, "proposed_doors": list(proposed), "floor": mapping(floor),
               "walls": mapping(walls), "hull": mapping(hullp), "check_failures": bad},
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
