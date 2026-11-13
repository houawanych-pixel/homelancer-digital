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

def _draw(S, floor, walls, hullp, main_floor, lifts, title, png, jpg, features=()):
    src = cv2.imread(S.src)
    plan = np.zeros_like(src); ov = (src * 0.35).astype(np.uint8)
    mf = raster(main_floor, src.shape[:2]) > 0
    plan[mf] = (40, 40, 40); ov[mf] = (ov[mf] * 0.6 + np.array([40, 40, 40]) * 0.4).astype(np.uint8)
    hp = np.array(hullp.exterior.coords, np.int32)
    for im in (plan, ov): cv2.polylines(im, [hp], True, (60, 60, 220), 2, cv2.LINE_AA)
    fl = raster(floor, src.shape[:2]) > 0
    ov[fl] = (ov[fl] * 0.5).astype(np.uint8)
    wm = raster(walls, src.shape[:2]) > 0
    plan[wm] = (255, 255, 255); ov[wm] = (255, 255, 255)
    for f in features:   # furniture / function lines (railing rings, holo-tables, cell bars, pods): not walls
        for g in getattr(f, "geoms", [f]):
            ring = g.exterior if g.geom_type == "Polygon" else g
            for im in (plan, ov): cv2.polylines(im, [np.array(ring.coords, np.int32)], g.geom_type == "Polygon", (70, 170, 210), 1, cv2.LINE_AA)
    for (x, y) in lifts:
        for im in (plan, ov):
            cv2.rectangle(im, (int(x - 9), int(y - 9)), (int(x + 9), int(y + 9)), (0, 200, 255), 2)
            cv2.putText(im, "LIFT", (int(x - 13), int(y + 22)), cv2.FONT_HERSHEY_SIMPLEX, 0.32, (0, 200, 255), 1, cv2.LINE_AA)
    for x, y in S.PROPOSED_DOORS:
        for im in (plan, ov): cv2.circle(im, (int(x), int(y)), 14, (0, 200, 255), 2, cv2.LINE_AA)
    for k, g in S.R.items():
        c = g.representative_point(); t = k.upper()
        (w, h), _ = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, 0.32, 1)
        for im in (plan, ov):
            cv2.putText(im, t, (int(c.x - w / 2), int(c.y + h / 2)), cv2.FONT_HERSHEY_SIMPLEX, 0.32, (255, 220, 120), 1, cv2.LINE_AA)
    for im in (plan, ov):
        cv2.putText(im, title, (24, src.shape[0] - 30), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 255, 255), 2, cv2.LINE_AA)
        cv2.putText(im, "PROPOSED (no blueprint)  red = hull   grey = main deck   gold = lifts", (24, src.shape[0] - 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.42, (180, 180, 180), 1, cv2.LINE_AA)
    cv2.imwrite(png, plan); cv2.imwrite(jpg, ov, [cv2.IMWRITE_JPEG_QUALITY, 86])

def run(sid, here, src, ax, name, level, R, HALLS, DOORS, lifts, start=None, proposed=(), fin=14, title=None, features=()):
    """Build one composed deck; check it (every room reachable from the first lift, inside the hull, a lift at each
    main-deck shaft) and draw it. Returns the list of problems (empty = good)."""
    S = Ship(sid + "_" + name, here, src, ax, R, HALLS, DOORS, start or lifts[0], proposed)
    floor, walls = build(S)
    rc = reach(S, floor, walls, S.START)
    bad = ["unreachable: " + k for k, v in rc.items() if not v]
    hullp = hull(src, ax, fin)
    out = floor.difference(hullp.buffer(-T))
    if out.area > 30: bad.append("outside the hull: %.0f px2 near %s" % (out.area, [round(v) for v in out.bounds]))
    for x, y in lifts:
        if not floor.contains(box(x - 3, y - 3, x + 3, y + 3)): bad.append("no floor at lift %s" % ((x, y),))
    P = json.load(open(os.path.join(here, "plan.json")))
    main_floor = shape(P["floor"])
    _draw(S, floor, walls, hullp, main_floor, lifts, title or name.upper() + " DECK",
          os.path.join(here, "deck_%s.png" % name), os.path.join(here, "deck_%s_on_map.jpg" % name), features)
    json.dump({"ship": sid, "deck": name, "level": level, "proposed": True, "units": "source px", "px_per_m": PX_PER_M,
               "thickness": T, "door": DOOR, "mirror_x": ax, "start": S.START, "lifts": [list(l) for l in lifts], "features": [mapping(f) for f in features],
               "rooms": {k: mapping(g) for k, g in R.items()}, "halls": [mapping(h) for h in HALLS],
               "center_y": S.center_y, "doors": DOORS, "proposed_doors": list(proposed), "floor": mapping(floor),
               "walls": mapping(walls), "hull": mapping(hullp)},
              open(os.path.join(here, "deck_%s.json" % name), "w"))
    print(sid, name, "rooms", len(R), "doors", len(DOORS), "problems:", bad or "none")
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
