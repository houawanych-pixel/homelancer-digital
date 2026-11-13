#!/usr/bin/env python3
"""ONE converter for every fleet ship: an owner-approved clean plan (eng/plan.json, from eng/build_plan.py) plus its
approved gameplay pass (eng/gameplay.json) -> assets/holodeck/<id>.json, the deck the game builds (ShipInterior).

usage: python3 -I tools/trace/to_deck_json.py tools/trace/fleet_<id> [--out assets/holodeck/<id>.json]

What it writes (the keys scripts/ship_interior.gd reads):
  w, h, cell_px, m_per_cell     plan cells (CELL source px each) and their real size (from the plan's px_per_m)
  shell.walls                   every wall face as a closed outline (cells), walkable side on the left
  shell.doors                   a sliding door in every doorway: rect (cells), level = key (0 green .. 3 red), ax
  rooms, room_rows, room_floor  room ids per cell (run-length), names, label points; floor tint rectangles
  start                         where you come aboard (and leave): the gameplay entry
  objectives, key_guards        the mission targets and the guards carrying the cards (gameplay.json)
  wrecks, lifts, patrols        CUTTER wreckage, lift squares, guard routes (gameplay.json)
Nothing is invented here: geometry comes only from plan.json, play only from gameplay.json."""
import argparse, json, os
import numpy as np, cv2
from shapely.geometry import shape, Point, Polygon, box
from shapely.geometry.polygon import orient

CELL = 4.0
# v13.126 (owner: "the ship was too small ... my person couldn't even enter some of the rooms ... everything needs to be
# bigger on the inside"): 2.5x (was 1.6 u per px, rooms 48 / halls 36 u tall, decks 80 u apart)
S_BOARD = 4.0          # boarding units (the mech-sized decks: pilot 13 u tall) per plan px; a 2 m hall = 80 u, a door 64 u
H_ROOM, H_HALL = 100.0, 72.0
DECK_DY = 170.0        # boarding units between deck floors (a room is 100 u tall: slab and service space between)
DECKS = {"main": ("", 0.0), "upper": ("u_", DECK_DY), "lower": ("l_", -DECK_DY)}   # deck -> (room key prefix, floor y)

def board_layout(plan, play, src_w, src_h, pre="", y0=0.0):
    """The same deck as a Boarding layout (scripts/boarding.gd schema): axis-aligned rects (rooms keep their real
    shape as a 'poly' outline), every hallway cut into rects that join with no door, and a short connector at every
    plan door. Played by the regular boarding / breakout engine: HUD, controls, guards, CUTTER, doors."""
    from shapely.geometry import box as sbox
    from shapely.ops import unary_union
    T, D = float(plan["thickness"]), float(plan["door"])
    g = T / 2.0
    AX, CY = float(plan["mirror_x"]), float(plan.get("center_y", src_h / 2.0))
    W = lambda x: round((x - AX) * S_BOARD, 2)
    Z = lambda y: round((y - CY) * S_BOARD, 2)
    DY = float(y0)
    rooms, shapes = {}, {}          # key -> boarding room; key -> (plan polygon, rect px)
    slug = lambda n: "".join(ch if ch.isalnum() else "_" for ch in n.lower()).strip("_")
    entry = play["entry"]["room"] if not pre else None
    guards = {k: int(v) for k, v in play.get("room_guards", {}).items()}
    for nm, gj in plan["rooms"].items():
        poly = shape(gj).buffer(-g, join_style=2)
        x0, y0, x1, y1 = poly.bounds
        key = "sbay" if nm == entry else pre + "r_" + slug(nm)
        shapes[key] = [poly, [x0, y0, x1, y1], nm]
        rooms[key] = {"r": [W(x0), W(x1), Z(y0), Z(y1)], "y": [DY, DY], "axis": "x" if x1 - x0 >= y1 - y0 else "z", "h": H_ROOM,
                      "label": nm.upper(), "guards": guards.get(nm, 0), "hex": False, "shape": "rect"}
    # hallways: one network, shrunk off the walls, cut into rects on every vertex line (and at the wreck points)
    halls = unary_union([shape(h) for h in plan["halls"]]).buffer(-g, join_style=2)
    # the engine's rooms are their boxes: hallways stop short of every room's box (a round room's corners are wall)
    halls = halls.difference(unary_union([sbox(*v[1]).buffer(2 * g, join_style=2) for v in shapes.values()]))
    halls = unary_union([p for p in getattr(halls, "geoms", [halls]) if p.area > 30])
    xs, ys = set(), set()
    for p in getattr(halls, "geoms", [halls]):
        for ring in [p.exterior] + list(p.interiors):
            for x, y in ring.coords: xs.add(round(x, 2)); ys.add(round(y, 2))
    cut_y, cut_x = set(), set()
    for w in play.get("wreck", []):   # (a wreck sits on a joint between two hall rects: never merged across)
        if w["across"] == "h": ys.add(float(w["at"][1])); cut_y.add(float(w["at"][1]))
        else: xs.add(float(w["at"][0])); cut_x.add(float(w["at"][0]))
    xs, ys = sorted(xs), sorted(ys)
    cells = {}
    for j in range(len(ys) - 1):
        for i in range(len(xs) - 1):
            c = sbox(xs[i], ys[j], xs[i + 1], ys[j + 1])
            if c.area > 0.5 and halls.contains(c.centroid) and halls.intersection(c).area > c.area * 0.98: cells[(i, j)] = True
    runs = []   # horizontal runs per band, then joined downwards when the same x span repeats
    for j in range(len(ys) - 1):
        i = 0
        while i < len(xs) - 1:
            if (i, j) in cells:
                k = i
                while (k + 1, j) in cells and xs[k + 1] not in cut_x: k += 1
                runs.append([xs[i], xs[k + 1], ys[j], ys[j + 1]]); i = k + 1
            else: i += 1
    merged = []
    for r in runs:
        for m in merged:
            if m[0] == r[0] and m[1] == r[1] and abs(m[3] - r[2]) < 1e-6 and r[2] not in cut_y: m[3] = r[3]; break
        else: merged.append(list(r))
    for n, (x0, x1, y0, y1) in enumerate(merged, 1):
        key = pre + "h%d" % n
        shapes[key] = [sbox(x0, y0, x1, y1), [x0, y0, x1, y1], "corridor"]
        rooms[key] = {"r": [W(x0), W(x1), Z(y0), Z(y1)], "y": [DY, DY], "axis": "x" if x1 - x0 >= y1 - y0 else "z", "h": H_HALL,
                      "label": "CORRIDOR", "guards": 0, "hex": False, "shape": "rect", "flow": True}
    def at(px, py):
        for k, (poly, r, _) in shapes.items():
            if r[0] - 0.01 <= px <= r[2] + 0.01 and r[1] - 0.01 <= py <= r[3] + 0.01 and (not rooms[k].get("flow") or poly.buffer(0.5).contains(Point(px, py))): return k
        return None
    def side(px, py, dx, dy, first):
        """the first thing (other than `first`) met stepping from the door point along (dx, dy)"""
        for st_ in range(2, 60):
            k = at(px + dx * st_, py + dy * st_)
            if k is not None and k != first: return k
        return None
    # a connector at every door, from one side's rect edge to the other's; locks by key level
    locks = {tuple(l["door"]): int(l["key"]) for l in play.get("locks", [])}
    conns, lock_list, problems = 0, [], []
    for x, y, o in plan["doors"]:
        if o == "h": a, b = at(x, y - 2 * T - 2), at(x, y + 2 * T + 2)
        else: a, b = at(x - 2 * T - 2, y), at(x + 2 * T + 2, y)
        if a is not None and a == b and not rooms[a].get("flow"):   # the door sits inside a shaped room's box: look past it
            if o == "h": a2, b2 = side(x, y, 0, -1, a), side(x, y, 0, 1, a)
            else: a2, b2 = side(x, y, -1, 0, a), side(x, y, 1, 0, a)
            if b2 is not None and (a2 is None or abs((shapes[b2][1][1] if o == "h" else shapes[b2][1][0]) - (y if o == "h" else x)) < abs((shapes[a2][1][3] if o == "h" else shapes[a2][1][2]) - (y if o == "h" else x))): b = b2
            elif a2 is not None: a = a2
        if a is None: a = side(x, y, 0, -1, b) if o == "h" else side(x, y, -1, 0, b)
        if b is None: b = side(x, y, 0, 1, a) if o == "h" else side(x, y, 1, 0, a)
        if a is not None and a == b and rooms[a].get("flow"): continue   # (a door square between two hallway runs: open)
        if a is not None and b is not None and rooms[a].get("flow") and rooms[b].get("flow"): continue
        if a is None or b is None or a == b: problems.append([x, y, o, a, b]); continue
        # the hallway side: the hall rect right across the gap from the room's edge (not one further in)
        if rooms[b].get("flow") and not rooms[a].get("flow"):
            ra0 = shapes[a][1]
            for st_ in range(1, 16):
                hit = at(x, ra0[3] + st_) if o == "h" else at(ra0[2] + st_, y)
                if hit and rooms[hit].get("flow"): b = hit; break
        elif rooms[a].get("flow") and not rooms[b].get("flow"):
            rb0 = shapes[b][1]
            for st_ in range(1, 16):
                hit = at(x, rb0[1] - st_) if o == "h" else at(rb0[0] - st_, y)
                if hit and rooms[hit].get("flow"): a = hit; break
        ra, rb = shapes[a][1], shapes[b][1]
        if o == "h": c = [x - D / 2, ra[3], x + D / 2, rb[1]]
        else: c = [ra[2], y - D / 2, rb[0], y + D / 2]
        if c[2] - c[0] <= 0.05 or c[3] - c[1] <= 0.05: problems.append([x, y, o, a, b, "no gap"]); continue
        conns += 1
        key = pre + "d%d" % conns
        door_to = a if not rooms[a].get("flow") else b      # the sliding door is on the room's side
        rooms[key] = {"r": [W(c[0]), W(c[2]), Z(c[1]), Z(c[3])], "y": [DY, DY], "axis": "z" if o == "h" else "x", "h": H_HALL,
                      "label": "DOOR", "guards": 0, "hex": False, "shape": "rect", "conn": True, "door_to": door_to}
        for k2 in (a, b):   # a shaped room reaches its rect edge across the doorway, so the doorway is clear
            poly, r, nm = shapes[k2]
            if rooms[k2].get("flow"): continue
            span = sbox(c[0], r[1], c[2], r[3]) if o == "h" else sbox(r[0], c[1], r[2], c[3])
            shapes[k2][0] = unary_union([poly, span.intersection(sbox(*r)).intersection(sbox(c[0] - 1, c[1] - 40, c[2] + 1, c[3] + 40) if o == "h" else sbox(c[0] - 40, c[1] - 1, c[2] + 40, c[3] + 1))])
        if (x, y) in locks: lock_list.append({"rooms": [key, door_to], "key": locks[(x, y)]})
    # shaped rooms: their outline in -1..1 of their rect (scripts/boarding.gd 'poly')
    for k, (poly, r, nm) in shapes.items():
        if rooms[k].get("flow"): continue
        rect = sbox(*r)
        if poly.area > rect.area * 0.985: continue
        poly = poly.simplify(0.6)
        if poly.geom_type != "Polygon": poly = max(poly.geoms, key=lambda q: q.area)
        cx, cy, hx, hy = (r[0] + r[2]) / 2, (r[1] + r[3]) / 2, (r[2] - r[0]) / 2, (r[3] - r[1]) / 2
        pts = list(orient(poly, 1.0).exterior.coords)[:-1]
        rooms[k]["poly"] = [[round((px - cx) / hx, 4), round((py - cy) / hy, 4)] for px, py in pts]
        rooms[k]["shape"] = "poly"
    # rects must not overlap (Boarding.room_at takes the first)
    keys = list(rooms.keys()); overlaps = []
    for i, k1 in enumerate(keys):
        a1 = rooms[k1]["r"]
        for k2 in keys[i + 1:]:
            a2 = rooms[k2]["r"]
            if min(a1[1], a2[1]) - max(a1[0], a2[0]) > 0.5 and min(a1[3], a2[3]) - max(a1[2], a2[2]) > 0.5: overlaps.append([k1, k2])
    wreck = []
    for w in play.get("wreck", []):
        wx, wy = w["at"]
        a, b = (at(wx, wy - 3), at(wx, wy + 3)) if w["across"] == "h" else (at(wx - 3, wy), at(wx + 3, wy))
        if a and b and a != b: wreck.append([a, b])
        else: problems.append(["wreck", wx, wy, a, b])
    # every room linked to the boarding bay through the engine's joints (touching rect edges, > 4 u of overlap)
    def joint(A, B):
        for p1, p2 in ((A[1], B[0]), (A[0], B[1])):
            if abs(p1 - p2) < 0.5 and min(A[3], B[3]) - max(A[2], B[2]) > 4.0: return True
        for p1, p2 in ((A[3], B[2]), (A[2], B[3])):
            if abs(p1 - p2) < 0.5 and min(A[1], B[1]) - max(A[0], B[0]) > 4.0: return True
        return False
    rep = {"connectors": conns, "halls": len(merged), "problems": problems, "overlaps": overlaps, "at": at, "shapes": shapes, "joint": joint}
    if pre:
        return {"rooms": rooms, "locks": lock_list, "wreck": wreck}, rep
    seen, todo = {"sbay"}, ["sbay"]   # (multi-deck ships: checked again in main() across the lifts)
    while todo:
        k0 = todo.pop()
        for k1 in rooms:
            if k1 not in seen and joint(rooms[k0]["r"], rooms[k1]["r"]): seen.add(k1); todo.append(k1)
    cut_off = [rooms[k]["label"] for k in rooms if k not in seen and not rooms[k].get("flow") and not rooms[k].get("conn")]
    dk = lambda t: DECKS[t.get("deck", "main")]
    tw = lambda pt, t: [W(pt[0]), dk(t)[1], Z(pt[1])]
    rk = lambda t: "sbay" if t["room"] == entry and t.get("deck", "main") == "main" else dk(t)[0] + "r_" + slug(t["room"])
    ent = shapes["sbay"][1]
    targets = {k: {"room": rk(t), "at": tw(t["at"], t), "key": int(t["key"])} for k, t in play["targets"].items()}
    cards = [{"room": rk(gd), "key": int(gd["key"]), "at": tw(gd["at"], gd)} for gd in play["guards"]]
    lay = {"scale": S_BOARD, "ax": AX, "cy": CY, "src_w": src_w, "src_h": src_h, "rooms": rooms,
           "start": [W((ent[0] + ent[2]) / 2), 0.0, Z((ent[1] + ent[3]) / 2)], "exit_x": W(ent[2]) + 6.0, "entry_x": -1.0e6,
           "core": targets.get("sabotage", {"at": [0, 0, 0]})["at"], "boss": targets.get("sabotage", {"at": [0, 0, 0]})["at"],
           "seal": ["none", "none"], "escape": ["none", "none"], "route_in": [], "route_out": [],
           "info": {"kind": "fleet", "blocked": wreck},
           "fleet": {"locks": lock_list, "cards": cards, "targets": targets, "entry": "sbay"}}
    rep["cut_off"] = cut_off
    return lay, rep

def raster(g, H, W, scale):
    out = np.zeros((H, W), np.uint8)
    for p in getattr(g, "geoms", [g]):
        m = np.zeros((H, W), np.uint8)
        cv2.fillPoly(m, [np.round(np.array(p.exterior.coords) / scale).astype(np.int32)], 1)
        for r in p.interiors: cv2.fillPoly(m, [np.round(np.array(r.coords) / scale).astype(np.int32)], 0)
        out |= m
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--out")
    ap.add_argument("--decks", action="store_true", help="also merge the composed upper / lower decks (eng/deck_*.json) - only once the owner approved them")
    a = ap.parse_args()
    eng = os.path.join(a.folder, "eng")
    plan = json.load(open(os.path.join(eng, "plan.json")))
    play = json.load(open(os.path.join(eng, "gameplay.json")))
    sid = plan["ship"]
    src = cv2.imread(os.path.join(a.folder, "source.jpg"))
    SH, SW = src.shape[:2]
    W, H = int(np.ceil(SW / CELL)), int(np.ceil(SH / CELL))
    c = lambda x, y: [round(x / CELL, 3), round(y / CELL, 3)]
    floor, walls = shape(plan["floor"]), shape(plan["walls"])
    T, DOOR = float(plan["thickness"]), float(plan["door"])

    # wall faces: every ring of the wall polygons, turned so the floor is on its left (ship_interior's normal rule)
    walk = floor.difference(walls)
    faces = []
    for p in getattr(walls, "geoms", [walls]):
        p = orient(p, 1.0)
        for ring in [p.exterior] + list(p.interiors):
            pts = list(ring.coords)[:-1]
            if len(pts) < 3: continue
            # pick the direction whose left side is walkable floor (test the longest edge)
            k = max(range(len(pts)), key=lambda i: np.hypot(pts[(i + 1) % len(pts)][0] - pts[i][0], pts[(i + 1) % len(pts)][1] - pts[i][1]))
            (x0, y0), (x1, y1) = pts[k], pts[(k + 1) % len(pts)]
            ex, ey = x1 - x0, y1 - y0; L = np.hypot(ex, ey)
            nx, ny = ey / L, -ex / L          # ship_interior: nrm = (e.z, 0, -e.x) with world z = plan y
            mx, my = (x0 + x1) / 2 + nx * 1.5, (y0 + y1) / 2 + ny * 1.5
            if not walk.buffer(0.3).contains(Point(mx, my)): pts = pts[::-1]
            flat = []
            for x, y in pts: flat += c(x, y)
            faces.append(flat)

    # sliding doors: one per doorway, the opening's rect in cells; the key from the gameplay pass
    locks = {tuple(l["door"]): int(l["key"]) for l in play.get("locks", [])}
    doors = []
    for x, y, o in plan["doors"]:
        if o == "h": r = [x - DOOR / 2, y - T * 1.5, x + DOOR / 2, y + T * 1.5]
        else: r = [x - T * 1.5, y - DOOR / 2, x + T * 1.5, y + DOOR / 2]
        doors.append({"rect": c(r[0], r[1]) + c(r[2], r[3]), "level": locks.get((x, y), 0), "ax": "y" if o == "h" else "x"})

    # rooms on the cell grid
    names = list(plan["rooms"].keys())
    grid = np.zeros((H, W), np.int32)
    rooms, room_floor = [], {}
    for i, nm in enumerate(names, 1):
        g = shape(plan["rooms"][nm])
        m = raster(g.buffer(-T / 2), H, W, CELL)
        grid[(m > 0) & (grid == 0)] = i
        at = g.representative_point() if not g.centroid.within(g) else g.centroid
        rooms.append({"id": i, "name": nm, "cells": int(m.sum()), "at": c(at.x, at.y), "reachable": True})
        rects = []
        for yy in range(H):   # floor tint: one rectangle per run of cells, joined downwards when the run repeats
            xs = np.where(m[yy] > 0)[0]
            if xs.size == 0: continue
            runs = np.split(xs, np.where(np.diff(xs) > 1)[0] + 1)
            for run in runs:
                x0r, x1r = int(run[0]), int(run[-1]) + 1
                for rc in rects:
                    if rc[0] == x0r and rc[2] == x1r - x0r and rc[1] + rc[3] == yy: rc[3] += 1; break
                else: rects.append([x0r, yy, x1r - x0r, 1])
        room_floor[str(i)] = rects
    room_rows = []
    for yy in range(H):
        row, x = [], 0
        while x < W:
            v = grid[yy, x]; n = 1
            while x + n < W and grid[yy, x + n] == v: n += 1
            row.append("%d*%d" % (v, n) if n > 1 else str(v)); x += n
        room_rows.append(",".join(row))
    hull = raster(floor, H, W, CELL)
    rows = ["".join("#" if v else " " for v in hull[yy]) for yy in range(H)]

    out = {
        "source": os.path.basename(a.folder), "from": "tools/trace/to_deck_json.py", "approved_plan": True,
        "cell_px": int(CELL), "m_per_cell": round(CELL / float(plan["px_per_m"]), 4), "w": W, "h": H,
        "rows": rows, "room_rows": room_rows, "rooms": rooms, "room_floor": room_floor,
        "doors": [], "walls": [], "corridor": [], "sealed": [], "door_open": [],
        "lifts": [c(*l["at"]) for l in play.get("lifts", [])],
        "start": c(*play["entry"]["at"]),
        "shell": {"walls": faces, "cover": [], "doors": doors, "from": "trace"},
        "objectives": {k: {"deck": "main", "room": t["room"], "at": c(*t["at"]), "need": int(t["key"])} for k, t in play["targets"].items()},
        "key_guards": [{"deck": "main", "room": g["room"], "key": int(g["key"]), "at": c(*g["at"])} for g in play["guards"]],
        "wrecks": [{"at": c(*w["at"]), "across": w["across"]} for w in play.get("wreck", [])],
        "patrols": [{"room": p["room"], "path": [c(*q) for q in p["path"]]} for p in play.get("patrols", [])],
    }
    lay, rep = board_layout(plan, play, SW, SH)
    # v13.96 (owner: "compose it, do top and bottom floor"): the composed upper / lower decks (eng/deck_<name>.json),
    # stacked over / under the main deck, joined by the lifts (gameplay "elevators": a car on each of its two decks)
    decks_done = {"main": rep}
    for dname in ("upper", "lower"):
        dpath = os.path.join(eng, "deck_%s.json" % dname)
        if not a.decks or not os.path.exists(dpath): continue
        dplan = json.load(open(dpath))
        dplay = dict(play.get("decks", {}).get(dname, {}))
        dplay.setdefault("entry", {"room": None}); dplay.setdefault("targets", {}); dplay.setdefault("guards", [])
        pre, dy = DECKS[dname]
        part, drep = board_layout(dplan, dplay, SW, SH, pre, dy)
        lay["rooms"].update(part["rooms"]); lay["fleet"]["locks"] += part["locks"]; lay["info"]["blocked"] += part["wreck"]
        rep["problems"] += [[dname] + list(q) for q in drep["problems"]]; rep["overlaps"] += drep["overlaps"]
        decks_done[dname] = drep
        # the in-game map picture for this deck (same frame as the HoloDeck picture, so the map's dot lines up)
        mp = np.zeros((SH, SW, 3), np.uint8); mp[:] = (40, 18, 6)
        hp = shape(dplan["hull"]); cv2.polylines(mp, [np.array(hp.exterior.coords, np.int32)], True, (150, 110, 40), 2, cv2.LINE_AA)
        mp[raster(shape(dplan["floor"]), SH, SW, 1.0) > 0] = (90, 50, 18)
        mp[raster(shape(dplan["walls"]), SH, SW, 1.0) > 0] = (255, 245, 225)
        for lx, ly in dplan.get("lifts", []): cv2.rectangle(mp, (int(lx - 9), int(ly - 9)), (int(lx + 9), int(ly + 9)), (60, 200, 255), 2)
        for nm, gj in dplan["rooms"].items():
            cpt = shape(gj).representative_point(); t = nm.upper()
            (tw_, th_), _ = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, 0.36, 1)
            cv2.putText(mp, t, (int(cpt.x - tw_ / 2), int(cpt.y + th_ / 2)), cv2.FONT_HERSHEY_SIMPLEX, 0.36, (255, 230, 170), 1, cv2.LINE_AA)
        cv2.imwrite(os.path.join("assets", "holodeck", "%s_%s.jpg" % (sid, dname)), mp, [cv2.IMWRITE_JPEG_QUALITY, 80])
    if len(decks_done) > 1:
        elev = []
        for e in play.get("elevators", []):
            ks = []
            for dname in e["decks"]:
                k = decks_done[dname]["at"](*e["at"]) if dname in decks_done else None
                if k is None or lay["rooms"][k].get("flow") or lay["rooms"][k].get("conn"): rep["problems"].append(["elevator", e["at"], dname, k]); k = None
                ks.append(k)
            if None not in ks: elev.append({"rooms": ks, "label": e.get("label", "LIFT")})
        lay["fleet"]["elev"] = elev
        lay["fleet"]["decks"] = {d: DECKS[d][1] for d in decks_done}
        R = lay["rooms"]
        flo = lambda k: float(R[k]["y"][0])
        jt = rep["joint"]
        seen, todo = {"sbay"}, ["sbay"]
        links = {}
        for e in elev: links.setdefault(e["rooms"][0], []).append(e["rooms"][1]); links.setdefault(e["rooms"][1], []).append(e["rooms"][0])
        while todo:
            k0 = todo.pop()
            for k1 in list(R.keys()):
                if k1 not in seen and abs(flo(k0) - flo(k1)) < 1 and jt(R[k0]["r"], R[k1]["r"]): seen.add(k1); todo.append(k1)
            for k1 in links.get(k0, []):
                if k1 not in seen: seen.add(k1); todo.append(k1)
        rep["cut_off"] = [R[k]["label"] + " (" + k + ")" for k in R if k not in seen and not R[k].get("flow") and not R[k].get("conn")]
        print("decks:", list(decks_done), "elevators:", [e["rooms"] for e in elev])
    out["board"] = lay
    print("board layout: %d rooms+halls+doors, %d hall rects, %d door connectors, %d locked" % (len(lay["rooms"]), rep["halls"], rep["connectors"], len(lay["fleet"]["locks"])))
    if rep["problems"]: print("PROBLEMS:", rep["problems"])
    if rep["cut_off"]: print("CUT OFF FROM THE BAY:", rep["cut_off"])
    if rep["overlaps"]: print("OVERLAPPING RECTS:", [[k1, lay["rooms"][k1]["r"], k2, lay["rooms"][k2]["r"]] for k1, k2 in rep["overlaps"]])
    dst = a.out or os.path.join("assets", "holodeck", sid + ".json")
    json.dump(out, open(dst, "w"), separators=(",", ":"))
    print(sid, "->", dst, "%d rooms, %d wall faces, %d doors (%d locked), %.1f KB" % (
        len(rooms), len(faces), len(doors), sum(1 for d in doors if d["level"]), os.path.getsize(dst) / 1024))

if __name__ == "__main__":
    main()
