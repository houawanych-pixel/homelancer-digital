#!/usr/bin/env python3
"""lego.py [--seed N] [--rooms 18] [--cell 2.0] [--out DIR]
The Alien room library as LEGO pieces (owner, Nov 18 2026: "connect them together like tetris, or legos, to build
anything ... as a randomizer").

1. KIT: every room in alien_rooms.json is turned into metres (one map grid cell = --cell m, owner to confirm) and
   centred; each door face becomes a CONNECTOR: its middle point, its outward direction snapped to 0/90/180/270 or a
   45-degree diagonal, and its width rounded to a standard size (S 1 cell, M 2, L 3+). -> kit.json
2. RANDOMIZER: start from one room, then again and again pick an open connector, pick a library room with a connector
   of the same size class, turn the new room so the two connectors face each other (only by 45-degree steps, so
   walls stay straight), slide it so the doors meet, and keep it only if it overlaps nothing already placed.
   -> random_<seed>.json (placed rooms + joins) and random_<seed>.png (blue rooms, yellow joined doors, grey unused).
   Rooms may overlap up to --settle of their area: the overlap is cut off the newer room along a clean line (shared wall).
Nothing here touches the game; it shows that the pieces snap."""
import argparse, json, math, os, random
import cv2, numpy as np
from shapely.geometry import Polygon, Point
from shapely import affinity

HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser(); ap.add_argument("--seed", type=int, default=1); ap.add_argument("--rooms", type=int, default=18)
ap.add_argument("--cell", type=float, default=2.0); ap.add_argument("--out", default=HERE)
ap.add_argument("--settle", type=float, default=0.45, help="most of a new room that may overlap others (it is then cut back)")
A = ap.parse_args()

lib = json.load(open(os.path.join(HERE, "alien_rooms.json")))
def size_class(cells): return "S" if cells < 1.5 else ("M" if cells < 2.6 else "L")
kit = []
for r in lib["rooms"]:
    k = A.cell / r["grid_px"]
    outer = [rg for rg in r["rings"] if not rg["hole"]]
    if not outer: continue
    P = Polygon([(x * k, y * k) for x, y in outer[0]["pts"]], [[(x * k, y * k) for x, y in rg["pts"]] for rg in r["rings"] if rg["hole"]]).buffer(0)
    if P.is_empty or P.geom_type != "Polygon" or P.area < 4: continue
    c = P.centroid; P = affinity.translate(P, -c.x, -c.y)
    cons = []
    for d in r["doors"]:
        mx, my = (d["a"][0] + d["b"][0]) / 2 * k - c.x, (d["a"][1] + d["b"][1]) / 2 * k - c.y
        ang = round(math.degrees(math.atan2(d["out"][1], d["out"][0])) / 45.0) * 45 % 360
        cons.append({"at": [round(mx, 2), round(my, 2)], "dir": ang, "width_m": round(d["width_cells"] * A.cell, 2), "size": size_class(d["width_cells"])})
    if not cons: continue
    kit.append({"id": r["id"], "map": r["map"], "area_m2": round(P.area, 1), "poly": [[round(x, 2), round(y, 2)] for x, y in P.exterior.coords],
                "holes": [[[round(x, 2), round(y, 2)] for x, y in h.coords] for h in P.interiors], "connectors": cons})
json.dump({"units": "m", "cell_m": A.cell, "count": len(kit), "note": "size S/M/L = door width class; dir = outward, degrees (0 = +x, 90 = +y)", "pieces": kit},
          open(os.path.join(A.out, "kit.json"), "w"), indent=0)

# ---------------- randomizer
rng = random.Random(A.seed)
def placed_poly(p, rot, tx, ty):
    P = Polygon(p["poly"], p["holes"])
    return affinity.translate(affinity.rotate(P, rot, origin=(0, 0)), tx, ty)
def clean(G):
    """Biggest piece, slivers opened away (< 1 m), edges simplified and snapped to 45-degree steps where close."""
    G = G.buffer(-0.5, join_style=2).buffer(0.5, join_style=2)
    if G.is_empty: return None
    if G.geom_type != "Polygon": G = max(G.geoms, key=lambda g: g.area)
    G = G.simplify(0.15)
    pts = list(G.exterior.coords)[:-1]; n = len(pts); out = []
    for i in range(n):   # snap each vertex onto the 45-degree line of the previous edge when almost on it
        a, b = (out[-1] if out else pts[i - 1]), pts[i]
        dx, dy = b[0] - a[0], b[1] - a[1]; L = math.hypot(dx, dy)
        if L > 0.3:
            t = math.atan2(dy, dx); sn = round(t / (math.pi / 4)) * (math.pi / 4)
            if abs(t - sn) < math.radians(6): b = (a[0] + L * math.cos(sn), a[1] + L * math.sin(sn))
        out.append(b)
    try:
        H = Polygon(out).buffer(0)
        if H.geom_type != "Polygon": H = max(H.geoms, key=lambda g: g.area)
        return H if H.area > 1 else None
    except Exception: return G
def con_world(c, rot, tx, ty):
    a = math.radians(rot); x, y = c["at"]
    return (x * math.cos(a) - y * math.sin(a) + tx, x * math.sin(a) + y * math.cos(a) + ty, (c["dir"] + rot) % 360)
start = rng.choice([p for p in kit if len(p["connectors"]) >= 3])
placed = [{"piece": start, "rot": 0, "tx": 0.0, "ty": 0.0, "poly": placed_poly(start, 0, 0, 0)}]
open_cons = [(0, i) for i in range(len(start["connectors"]))]
used = set(); joins = []
tries = 0
while len(placed) < A.rooms and open_cons and tries < 4000:
    tries += 1
    pi, ci = rng.choice(open_cons)
    pl = placed[pi]; c = pl["piece"]["connectors"][ci]
    wx, wy, wd = con_world(c, pl["rot"], pl["tx"], pl["ty"])
    cand = rng.choice(kit)
    opts = [j for j, cc in enumerate(cand["connectors"]) if cc["size"] == c["size"]]
    if not opts: continue
    j = rng.choice(opts); cc = cand["connectors"][j]
    rot = (wd + 180 - cc["dir"]) % 360                       # face the other door
    a = math.radians(rot); x, y = cc["at"]
    rx, ry = x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)
    tx, ty = wx - rx, wy - ry
    P = placed_poly(cand, rot, tx, ty)
    # SETTLE IN (owner: "when rooms overlap, settle it in, merge it, divide what overlaps, fix it clean"): a new room may
    # overlap others; the overlap stays with the room already there and the new room is cut back along a clean line
    # (shared wall = one line). Too big an overlap, a cut that leaves the room in bits, or a cut that eats its door: skip.
    over = sum(P.intersection(q["poly"]).area for q in placed)
    if over > A.settle * P.area: continue
    if over > 0.05:
        cut = P
        for q in placed: cut = cut.difference(q["poly"])
        cut = clean(cut)
        if cut is None: continue
        for q in placed: cut = cut.difference(q["poly"])   # the snap may nudge a corner back over: cut again, exactly
        if cut.geom_type != "Polygon": cut = max(cut.geoms, key=lambda g: g.area) if not cut.is_empty else None
        if cut is None or cut.area < 0.5 * P.area or cut.exterior.distance(Point(wx, wy)) > 0.3: continue
        P = cut
    placed.append({"piece": cand, "rot": rot, "tx": tx, "ty": ty, "poly": P})
    ni = len(placed) - 1
    joins.append({"a": [pi, ci], "b": [ni, j], "at": [round(wx, 2), round(wy, 2)]})
    open_cons.remove((pi, ci))
    open_cons += [(ni, k2) for k2 in range(len(cand["connectors"])) if k2 != j]
# final check: no two rooms overlap after settling
bad = sum(1 for i in range(len(placed)) for j in range(i + 1, len(placed)) if placed[i]["poly"].intersection(placed[j]["poly"]).area > 0.2)
out = {"overlaps_left": bad, "seed": A.seed, "cell_m": A.cell, "rooms": [{"id": p["piece"]["id"], "rot": p["rot"], "at": [round(p["tx"], 2), round(p["ty"], 2)],
       "poly": [[round(x, 2), round(y, 2)] for x, y in p["poly"].exterior.coords]} for p in placed],
       "joins": joins, "open_doors": len(open_cons)}
json.dump(out, open(os.path.join(A.out, "random_%d.json" % A.seed), "w"), indent=1)
# picture
allb = np.array([q["poly"].bounds for q in placed]); x0, y0 = allb[:, 0].min() - 4, allb[:, 1].min() - 4; x1, y1 = allb[:, 2].max() + 4, allb[:, 3].max() + 4
S = min(1400 / (x1 - x0), 1400 / (y1 - y0))
img = np.zeros((int((y1 - y0) * S), int((x1 - x0) * S), 3), np.uint8)
def tf(x, y): return (int((x - x0) * S), int((y - y0) * S))
for q in placed:
    for ring in [q["poly"].exterior] + list(q["poly"].interiors):
        cv2.polylines(img, [np.array([tf(x, y) for x, y in ring.coords], np.int32)], True, (255, 150, 30), 2, cv2.LINE_AA)
for (pi, ci) in open_cons:
    p = placed[pi]; x, y, _ = con_world(p["piece"]["connectors"][ci], p["rot"], p["tx"], p["ty"])
    cv2.circle(img, tf(x, y), 3, (120, 120, 120), -1)
for jn in joins: cv2.circle(img, tf(*jn["at"]), 6, (40, 220, 255), -1)
cv2.putText(img, "random level seed %d: %d library rooms, %d doors joined" % (A.seed, len(placed), len(joins)), (12, 26), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (230, 230, 230), 2)
cv2.imwrite(os.path.join(A.out, "random_%d.png" % A.seed), img)
print("overlaps left", bad, "| kit", len(kit), "| placed", len(placed), "joins", len(joins), "open", len(open_cons))
