#!/usr/bin/env python3
"""PROPOSED walkways for the five Liberty Hub decks (owner, Nov 18 2026: "put in all the walkways ... very unique,
multiple different walkways", example = his Liberty Hub inner map concept v2: atrium ring, rings, radial spokes, a
cross, diagonals, lanes out to the docks). The traced rooms (<deck>_trace.json) stay as they are; walkways go in
the free floor round them, in five kinds:
  PROMENADE  wide RED mech ring right round the room block (concept v2's main ring)
  CAUSEWAY   wide RED mech lane up the middle of every arm / spike, ending in a DOCK pad at the tip
  OUTER LOOP narrow BLUE pilot corridor following the hull, inside it
  SPOKES     narrow BLUE pilot corridors at 45 / 90 deg from the promenade out to the outer loop (concept v2's radials)
  CROSS      wide RED mech cross on the lift axis, out of the room block to the promenade
Output: <deck>_ways.jpg, <deck>_ways.json and ways_sheet.jpg (all five)."""
import json, math, os
import cv2, numpy as np
from shapely.geometry import shape, mapping, LineString, Point, Polygon, box
from shapely.ops import unary_union
from skimage.morphology import skeletonize

HERE = os.path.dirname(os.path.abspath(__file__))
DECKS = ["hangar", "engineering", "main_hub", "habitat", "command"]
MAIN_W, PILOT_W, GAP, INSET = 46.0, 28.0, 4.0, 20.0          # panel x4 px (main ~ a mech lane, pilot ~ a crew corridor)
RED, DRED, BLUE, YEL, LINE = (60, 50, 215), (40, 30, 150), (235, 130, 40), (0, 210, 240), (255, 150, 30)
parts = lambda g: [q for q in getattr(g, "geoms", [g]) if q.geom_type == "Polygon" and not q.is_empty]
lane = lambda a, b, w: LineString([a, b]).buffer(w / 2, cap_style=2, join_style=2)


def build(name):
    J = json.load(open(os.path.join(HERE, name + "_trace.json")))
    H = shape(J["hull"]).buffer(0)
    rooms0 = [shape(g) for g in J["mech"] + J["pilot"]]; lifts = [shape(g) for g in J["lifts"]]
    # the rooms on the sheet touch wall to wall: each is drawn in by INSET on every side, so the space between them
    # becomes the inner corridors (parallel walls, the rooms' own shapes)
    rooms = [r.buffer(-INSET, join_style=2) for r in rooms0]
    nmech = len(J["mech"])
    block0 = unary_union(rooms0 + lifts).buffer(70, join_style=2).buffer(-70, join_style=2)
    block0 = max(parts(block0), key=lambda q: q.area) if block0.geom_type != 'Polygon' else block0   # the room block
    block = block0
    inner = H.buffer(-22, join_style=2)                     # inside the hull wall
    W = {}
    # PROMENADE: a ring round the room block; LANES: the corridors between the rooms (inside the block)
    W["promenade"] = block.buffer(MAIN_W, join_style=2).difference(block).intersection(inner)
    RU = unary_union(rooms + lifts)
    W["lanes"] = RU.buffer(GAP + PILOT_W, join_style=2).difference(RU.buffer(GAP, join_style=2)).intersection(block)
    W["lanes"] = unary_union([q for q in parts(W["lanes"]) if q.area > 800])
    # the arms: what a big opening of the hull takes off (spikes, pods, docking arms)
    m = np.zeros((int(H.bounds[3]) + 40, int(H.bounds[2]) + 40), np.uint8)
    cv2.fillPoly(m, [np.array(H.exterior.coords, np.int32)], 1)
    body = cv2.morphologyEx(m, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (161, 161)))
    arms = (m & (1 - body)).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(arms)
    caus, docks = [], []
    cx, cy = block.centroid.x, block.centroid.y
    for i in range(1, n):
        if st[i, 4] < 5000: continue
        sk = skeletonize(lab == i); ys, xs = np.nonzero(sk)
        if len(xs) < 20: continue
        d = np.hypot(xs - cx, ys - cy); tip = (xs[np.argmax(d)], ys[np.argmax(d)])
        # the lane runs from the promenade straight out to the arm tip (one straight line, no wobble)
        b = np.array(tip, float); u = (b - np.array((cx, cy))) / max(np.hypot(*(b - np.array((cx, cy)))), 1)
        root = block.exterior.interpolate(block.exterior.project(Point(*b)))
        a = np.array((root.x, root.y)); u = (b - a) / max(np.hypot(*(b - a)), 1)
        start = a - u * 10
        wd = MAIN_W if st[i, 4] > 20000 else PILOT_W
        L = lane(tuple(start), tuple(b - u * 30), wd).intersection(inner)
        L = [q for q in parts(L) if q.distance(W["promenade"]) < 5]
        if not L: continue
        caus += L
        docks.append(Point(*(b - u * 40)).buffer(wd * 0.9, 4))
    W["causeway"] = unary_union(caus) if caus else Polygon()
    W["dock"] = unary_union(docks).intersection(inner) if docks else Polygon()
    # OUTER LOOP: a pilot corridor following the hull of the body (not out into the arms)
    bodyP = max(parts(H.intersection(H.buffer(-80, join_style=2).buffer(80, join_style=2))), key=lambda q: q.area)
    loop = bodyP.buffer(-28, join_style=2).difference(bodyP.buffer(-28 - PILOT_W, join_style=2))
    W["outer_loop"] = loop.difference(block.buffer(MAIN_W + 2 * GAP, join_style=2))
    # SPOKES: every 45 deg from the block centre, block edge to the outer loop, where the floor between is free
    sp = []
    R = max(H.bounds[2] - H.bounds[0], H.bounds[3] - H.bounds[1])
    for ang in range(0, 360, 45):
        u = (math.cos(math.radians(ang)), math.sin(math.radians(ang)))
        L = lane((cx, cy), (cx + u[0] * R, cy + u[1] * R), PILOT_W).intersection(bodyP.buffer(-30)).difference(block)
        for q in parts(L):
            if q.area > 1500 and q.distance(W["outer_loop"]) < 6: sp.append(q)
    W["spokes"] = unary_union(sp) if sp else Polygon()
    # CROSS: from the room block's middle doors straight out (only the bits outside the rooms)
    cr = []
    for u in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        L = lane((cx, cy), (cx + u[0] * R, cy + u[1] * R), MAIN_W).intersection(inner).difference(block.buffer(-GAP))
        cr += [q for q in parts(L) if q.area > 2000 and not q.within(unary_union(rooms).buffer(4))]
    W["cross"] = unary_union(cr).difference(unary_union(rooms + lifts).buffer(GAP / 2)) if cr else Polygon()
    for k_ in W: W[k_] = W[k_].difference(unary_union(rooms + lifts).buffer(GAP)).buffer(0)
    # one floor, no overlaps: mech ways first, then the pilot ways in what is left
    red = unary_union([W["promenade"], W["cross"], W["causeway"]]).buffer(0)
    W["cross"] = W["cross"].difference(W["promenade"]); W["causeway"] = W["causeway"].difference(W["promenade"]).difference(W["cross"])
    taken = red.union(W["dock"])
    for k_ in ("lanes", "outer_loop", "spokes"):
        W[k_] = W[k_].difference(taken).buffer(-1).buffer(1); taken = taken.union(W[k_])
    # only what joins the promenade network counts (no loose walkway pieces)
    net = unary_union([W[k_] for k_ in W])
    main = max(parts(net), key=lambda q: q.area)
    for k_ in W: W[k_] = unary_union([q for q in parts(W[k_]) if q.intersects(main.buffer(1))]) if parts(W[k_]) else W[k_]
    loose = len(parts(net)) - 1
    # draw on the dimmed panel
    im = cv2.imread(os.path.join(HERE, name + ".png")); out = (im * 0.3).astype(np.uint8); fl = out.copy()
    def fill(g, col):
        for q in parts(g):
            cv2.fillPoly(fl, [np.array(q.exterior.coords, np.int32)], col)
            for h in q.interiors: cv2.fillPoly(fl, [np.array(h.coords, np.int32)], (0, 0, 0))
    for k_, col in (("outer_loop", BLUE), ("spokes", BLUE), ("lanes", BLUE), ("promenade", RED), ("causeway", RED), ("cross", RED), ("dock", YEL)):
        fill(W[k_], col)
    for r in rooms: cv2.fillPoly(fl, [np.array(r.exterior.coords, np.int32)], DRED if rooms.index(r) < nmech else (95, 50, 20))
    for y in lifts: cv2.fillPoly(fl, [np.array(y.exterior.coords, np.int32)], YEL)
    out = cv2.addWeighted(fl, 0.75, out, 0.25, 0)
    for g in [H] + rooms + lifts + [unary_union(list(W.values())).buffer(0)]:
        for q in parts(g):
            for ring in [q.exterior] + list(q.interiors):
                cv2.polylines(out, [np.array(ring.coords, np.int32)], True, LINE, 3, cv2.LINE_AA)
    cv2.putText(out, name.replace("_", " ").upper(), (30, 80), cv2.FONT_HERSHEY_SIMPLEX, 2.4, (255, 255, 255), 5, cv2.LINE_AA)
    cv2.imwrite(os.path.join(HERE, name + "_ways.jpg"), out, [cv2.IMWRITE_JPEG_QUALITY, 88])
    json.dump({k_: mapping(v) for k_, v in W.items()}, open(os.path.join(HERE, name + "_ways.json"), "w"))
    print(name, {k_: round(v.area / 1000) for k_, v in W.items()}, "loose pieces dropped", loose)
    return out


if __name__ == "__main__":
    T = [build(d) for d in DECKS]
    h = 900; T = [cv2.resize(t, (int(t.shape[1] * h / t.shape[0]), h)) for t in T]
    leg = np.zeros((90, sum(t.shape[1] for t in T), 3), np.uint8)
    x = 20
    for col, txt in ((RED, "PROMENADE / CAUSEWAY / CROSS (mech, wide)"), (BLUE, "LANES / OUTER LOOP / SPOKES (pilot, narrow)"), (YEL, "DOCK PADS + LIFTS"), (DRED, "MECH ROOMS"), ((95, 50, 20), "PILOT ROOMS")):
        cv2.rectangle(leg, (x, 30), (x + 40, 60), col, -1); cv2.putText(leg, txt, (x + 55, 56), 0, 0.9, (255, 255, 255), 2, cv2.LINE_AA); x += 160 + 17 * len(txt)
    cv2.imwrite(os.path.join(HERE, "ways_sheet.jpg"), np.vstack([np.hstack(T), leg]), [cv2.IMWRITE_JPEG_QUALITY, 88])
