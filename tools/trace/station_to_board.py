#!/usr/bin/env python3
"""A station's deck plan (tools/trace/station_swtor.py, v3) -> a boarding layout the boarding engine plays
(scripts/boarding.gd, the same engine as the fleet ships): assets/stations_board/<model>.json  {"board": {...}}.

Owner Nov 17 2026: "it's a space station, so it should look just like the boarding levels we've been playing ... I may
be on the Imperium side invading this station to capture or rescue ... make everything universal". So a station is
played like a fleet ship: same characters, moves, HUD, guards, cards, keypads; calm on a visit, the alarm when you
invade it.

The engine wants axis-aligned boxes that only join where their edges touch. So the plan is rasterised (0.5 m cells),
every room and the walkway network are cut into boxes (row runs merged downwards), each room keeps its name on all its
boxes, the way and the rooms stay apart by the plan's wall gap, and every doorway is a short connector box between the
way's box and the room's box (its card level from the plan). The front pod is the docking bay you come aboard by.
usage: python3 -I tools/trace/station_to_board.py [model ...] [--deck "MAIN HUB"]"""
import json, math, os, sys
import numpy as np, cv2
from shapely.geometry import Point
from shapely.ops import unary_union, nearest_points

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import station_swtor as T
import station_plans as SP

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "assets", "stations_board")
PX = T.PX
S_BOARD = 4.0                 # boarding units per plan px (as the fleet ships: tools/trace/to_deck_json.py)
CELL = 10.0                   # plan px per raster cell (1 m)
H_ROOM, H_HALL, H_PILOT = 100.0, 72.0, 12.0
MECH_DOOR, PILOT_DOOR = 3.0 * PX, 1.4 * PX
MIN_ROOM_BOX = 6               # cells (m2): a room's smaller boxes are left out (fewer boxes: lighter on a phone)
SHRINK = 2.5                  # px off every shape (the plan's 5 px wall gap becomes two clear cells)


def slug(n): return "".join(ch if ch.isalnum() else "_" for ch in n.lower()).strip("_")


def rects_of(mask):
    """axis-aligned boxes covering a 0/1 mask, few of them: the biggest rectangle left, again and again"""
    m = mask.copy().astype(np.uint8)
    out = []
    while m.any():
        H, W = m.shape
        hgt = np.zeros(W, np.int32)
        best = (0, None)
        for y in range(H):
            hgt = np.where(m[y] > 0, hgt + 1, 0)
            st = []   # largest rectangle in the histogram
            for x in range(W + 1):
                hcur = hgt[x] if x < W else 0
                start = x
                while st and st[-1][1] >= hcur:
                    sx, sh = st.pop()
                    a = sh * (x - sx)
                    if a > best[0]: best = (a, [sx, y - sh + 1, x, y + 1])
                    start = sx
                st.append((start, hcur))
        x0, y0, x1, y1 = best[1]
        m[y0:y1, x0:x1] = 0
        out.append([x0, y0, x1, y1])
    return out   # [x0, y0, x1, y1] in cells


def build_deck(st, D, pre="", dy=0.0):
    L = D["_L"]
    ways_all = L["ways"]
    pods = [p for p in L.get("pods", [])] or []
    ox, oy, x1b, y1b = L["outline"].bounds
    ox, oy = ox - 4 * CELL, oy - 4 * CELL
    W = int((x1b - ox) / CELL) + 8; H = int((y1b - oy) / CELL) + 8
    def raster(g):
        m = np.zeros((H, W), np.uint8)
        for p in T.parts(g):
            cv2.fillPoly(m, [np.round((np.array(p.exterior.coords) - (ox, oy)) / CELL).astype(np.int32)], 1)
            for h in p.interiors: cv2.fillPoly(m, [np.round((np.array(h.coords) - (ox, oy)) / CELL).astype(np.int32)], 0)
        return m
    # the docking bay: the pod at the front (the end of the bridge furthest +y, as station_to_int's start)
    front = max(pods, key=lambda q: q.centroid.y) if pods else None
    if front is None:   # (the finished plan keeps its pods inside the ways: the round end of the front bridge)
        yb = ways_all.intersection(T.box(-1.6 * PX, -1e5, 1.6 * PX, 1e5)).bounds[3]
        front = Point(0, yb - 4.2 * PX).buffer(4.2 * PX, 16).intersection(ways_all)
    bay = front.buffer(-SHRINK, join_style=2) if front is not None else None
    ways = ways_all.difference(front.buffer(WALLGAP, join_style=2)) if front is not None else ways_all
    ways = max(T.parts(T._sp(ways)), key=lambda q: q.area) if T.parts(T._sp(ways)) else ways
    shapes = [("ways", ways.buffer(-SHRINK, join_style=2), "CORRIDOR", "mech", 0)]
    if bay is not None: shapes.append(("sbay", bay, "DOCKING BAY", "mech", 0))
    for r in D["rooms"]: shapes.append(("r_" + slug(r["name"]), r["poly"].buffer(-SHRINK, join_style=2), r["name"].upper(), r["kind"], int(r["key"])))
    # (the lift stands in the hub, part of the way, until the five decks are stacked)
    # lift: carved out of the ways (it stands in the hub)
    lab = np.zeros((H, W), np.int32)
    for i, (k, g, _, _, _) in enumerate(shapes, 1):
        m = raster(g)
        if k == "lift_main": lab[m > 0] = i
        else: lab[(m > 0) & (lab == 0)] = i
    # different neighbours never touch (the engine would open a passage): clear the cells where they would
    for _ in range(2):
        for dxy in ((1, 0), (0, 1)):
            a = lab[:H - dxy[1], :W - dxy[0]]; b = lab[dxy[1]:, dxy[0]:]
            clash = (a > 0) & (b > 0) & (a != b)
            ys, xs = np.nonzero(clash)
            for y, x in zip(ys, xs):   # clear the room's cell (keep the way whole)
                ya, xa, yb, xb = y, x, y + dxy[1], x + dxy[0]
                if shapes[lab[ya, xa] - 1][0] == "ways": lab[yb, xb] = 0
                else: lab[ya, xa] = 0
    S = S_BOARD
    U = lambda cx: round((ox + cx * CELL) * S, 2)
    V = lambda cy: round((oy + cy * CELL) * S, 2)
    rooms, boxes = {}, {}
    hall_n = 0
    for i, (k, g, label, kind, key) in enumerate(shapes, 1):
        rs = rects_of((lab == i).astype(np.uint8))
        rs.sort(key=lambda r: -(r[2] - r[0]) * (r[3] - r[1]))
        if k != "ways": rs = rs[:1] + [r for r in rs[1:] if (r[2] - r[0]) * (r[3] - r[1]) >= MIN_ROOM_BOX and min(r[2] - r[0], r[3] - r[1]) >= 2]   # a room's slivers along a slanted wall go: its walls step instead
        for j, (x0, y0, x1, y1) in enumerate(rs):
            if k == "ways": hall_n += 1; kk = pre + "h%d" % hall_n
            elif k in ("sbay", "lift_main"): kk = pre + k if j == 0 else "%s%s_%d" % (pre, k, j)
            else: kk = pre + k if j == 0 else "%s%s_%d" % (pre, k, j)
            R = {"r": [U(x0), U(x1), V(y0), V(y1)], "y": [dy, dy], "axis": "x" if x1 - x0 >= y1 - y0 else "z",
                 "h": H_HALL if k == "ways" else H_ROOM, "label": label, "guards": 0, "hex": False, "shape": "rect", "kind": kind}
            if k == "ways": R["flow"] = True
            if kind == "pilot": R.update({"pilot": True, "h": H_PILOT})
            if k == "lift_main": R["kind"] = "lift"
            rooms[kk] = R
            boxes[kk] = (k, [x0, y0, x1, y1])
    # doors: a connector from the way's box to the room's box at the plan's door point
    def box_at(name, cx, cy):
        best, bd = None, 1e9
        for kk, (k, b) in boxes.items():
            if k != name: continue
            ddx = max(b[0] - cx, 0, cx - b[2]); ddy = max(b[1] - cy, 0, cy - b[3])
            dd = math.hypot(ddx, ddy)
            if dd < bd: bd, best = dd, kk
        return best
    conns, locks, problems = 0, [], []
    door_list = [(k, g, label, kind, key) for (k, g, label, kind, key) in shapes if k not in ("ways", "lift_main")]
    for k, g, label, kind, key in door_list:
        src = shapes[0][1]
        a, b = nearest_points(src, g)
        ca = ((a.x - ox) / CELL, (a.y - oy) / CELL); cb = ((b.x - ox) / CELL, (b.y - oy) / CELL)
        w = (MECH_DOOR if kind == "mech" else PILOT_DOOR) / CELL
        # every way box and room box that face each other across a short gap, the one nearest the plan's door point
        best, bd = None, 1e9
        hbs = [(kk, b) for kk, (n0, b) in boxes.items() if n0 == "ways"]
        rbs = [(kk, b) for kk, (n0, b) in boxes.items() if n0 == k]
        for rk_, rb in rbs:
            for hk_, hb in hbs:
                for ax in ("x", "y"):
                    i0, i1 = (0, 2) if ax == "x" else (1, 3)
                    j0, j1 = (1, 3) if ax == "x" else (0, 2)
                    if hb[i1] <= rb[i0]: g0, g1 = hb[i1], rb[i0]
                    elif rb[i1] <= hb[i0]: g0, g1 = rb[i1], hb[i0]
                    else: continue
                    if g1 - g0 < 1 or g1 - g0 > 8: continue
                    lo, hi = max(hb[j0], rb[j0]), min(hb[j1], rb[j1])
                    need = min(w, 2.0) if kind == "pilot" else min(w, 3.0)
                    if hi - lo < need: continue
                    ww = min(w, hi - lo)
                    cc = min(max(cb[1] if ax == "x" else cb[0], lo + ww / 2), hi - ww / 2)
                    rect = [g0, cc - ww / 2, g1, cc + ww / 2] if ax == "x" else [cc - ww / 2, g0, cc + ww / 2, g1]
                    mid = ((rect[0] + rect[2]) / 2, (rect[1] + rect[3]) / 2)
                    dd = math.hypot(mid[0] - cb[0], mid[1] - cb[1])
                    if dd < bd: bd, best = dd, (ax, rect, rk_)
        if best is None: problems.append([label, "no doorway"]); continue
        made = (best[0], best[1]); rk = best[2]
        ax, c4 = made
        conns += 1
        kk = pre + "d%d" % conns
        R = {"r": [U(c4[0]), U(c4[2]), V(c4[1]), V(c4[3])], "y": [dy, dy], "axis": "x" if ax == "x" else "z", "h": H_HALL,
             "label": "DOOR", "guards": 0, "hex": False, "shape": "rect", "conn": True, "door_to": rk, "kind": kind}
        if kind == "pilot": R.update({"pilot": True, "h": H_PILOT, "label": "PILOT DOOR"})
        rooms[kk] = R
        if key > 0: locks.append({"rooms": [kk, rk], "key": min(3, key)})
    return rooms, locks, problems


WALLGAP = T.WALL


def joint(A, B):
    for p1, p2 in ((A[1], B[0]), (A[0], B[1])):
        if abs(p1 - p2) < 0.5 and min(A[3], B[3]) - max(A[2], B[2]) > 4.0: return True
    for p1, p2 in ((A[3], B[2]), (A[2], B[3])):
        if abs(p1 - p2) < 0.5 and min(A[1], B[1]) - max(A[0], B[0]) > 4.0: return True
    return False


def convert(st, deck_role="MAIN HUB"):
    T.KEEP = {}
    T.build(st)
    K = T.KEEP[st["model"]]
    D = next(d for d in K["decks"] if d["role"] == deck_role)
    rooms, locks, problems = build_deck(st, D)
    # reachable from the bay (touching edges)
    seen, todo = {"sbay"}, ["sbay"]
    while todo:
        k0 = todo.pop()
        for k1, R in rooms.items():
            if k1 not in seen and joint(rooms[k0]["r"], R["r"]): seen.add(k1); todo.append(k1)
    cut = sorted({rooms[k]["label"] for k in rooms if k not in seen and not rooms[k].get("conn")})
    gone = [k for k in rooms if k not in seen]   # boxes no way reaches: left out (solid), and said so
    for k in gone: del rooms[k]
    locks = [l for l in locks if l["rooms"][0] in rooms and l["rooms"][1] in rooms]
    sb = rooms["sbay"]["r"]
    start = [round((sb[0] + sb[1]) / 2, 2), 0.0, round((sb[2] + sb[3]) / 2, 2)]
    levels = {k: int(next((r["key"] for r in D["rooms"] if "r_" + slug(r["name"]) == k.split("_", 0)[0]), 0)) for k in rooms if k.startswith("r_")}
    cards = []
    for r in D["rooms"]:
        if r.get("card"):
            c = r["poly"].representative_point()
            cards.append({"room": "r_" + slug(r["name"]), "key": min(3, int(r["card"])), "at": [round(c.x * S_BOARD, 2), 0.0, round(c.y * S_BOARD, 2)]})
    lay = {"scale": S_BOARD, "ax": 0.0, "cy": 0.0, "src_w": 0, "src_h": 0, "rooms": rooms, "start": start,
           "exit_x": 1.0e6, "entry_x": -1.0e6, "core": [0, 0, 0], "boss": [0, 0, 0], "seal": ["none", "none"], "escape": ["none", "none"],
           "route_in": [], "route_out": [], "info": {"kind": "fleet", "blocked": [], "station": True},
           "fleet": {"locks": locks, "cards": cards, "targets": {}, "entry": "sbay", "levels": {k: v for k, v in levels.items() if v > 0}}}
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, st["model"] + ".json")
    json.dump({"source": st["model"], "name": st["name"], "deck": deck_role, "board": lay}, open(dst, "w"), separators=(",", ":"))
    n_room = len({R["label"] for R in rooms.values() if not R.get("flow") and not R.get("conn")})
    print(st["model"], "%s: %d boxes (%d rooms, %d doors, %d locked) -> %s" % (deck_role, len(rooms), n_room, sum(1 for R in rooms.values() if R.get("conn")), len(locks), os.path.relpath(dst, REPO)))
    if problems: print("  doors not made:", problems)
    if cut: print("  left out (no way in):", cut)
    return lay, problems, cut


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    S = json.load(open(os.path.join(SP.OUT, "stations.json")))
    for st in S:
        if args and st["model"] not in args: continue
        convert(st)
