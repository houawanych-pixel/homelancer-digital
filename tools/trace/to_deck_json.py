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
    dst = a.out or os.path.join("assets", "holodeck", sid + ".json")
    json.dump(out, open(dst, "w"), separators=(",", ":"))
    print(sid, "->", dst, "%d rooms, %d wall faces, %d doors (%d locked), %.1f KB" % (
        len(rooms), len(faces), len(doors), sum(1 for d in doors if d["level"]), os.path.getsize(dst) / 1024))

if __name__ == "__main__":
    main()
