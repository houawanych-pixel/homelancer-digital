# HoloDeck PNG -> a walkable grid layout (JSON) for ShipInterior (scripts/ship_interior.gd).
# Reads the owner's official deck plan: the white outer line is the hull, bright cyan lines are walls, green squares
# are doors, white text is room names (not walls). Rooms are flood-filled from the label points in seeds/<id>.json.
# Usage: python3 extract.py <plan.png> <seeds.json> <out.json> [debug.png]
import json, sys
import numpy as np
from PIL import Image, ImageFilter
from collections import deque
CELL = 4            # px per grid cell
WALL_G = 150        # how bright a cyan line must be to count as a wall (dim lines are floor markings)
MIN_WALL = 24
LINK_MAX = 14       # walls: the most wall cells an auto-link may cut through to reach a cut-off room
TUNNEL_MAX = 9      # cells: the thickest wall a door may tunnel through (both sides must reach open floor)
DOOR_GROW = 5       # cells: how far a door opening is widened to cut fully through its wall       # wall pieces smaller than this many cells are decoration (icons, markings)
def rle(row):
    """One grid row of room ids as runs: "0*40,3*12,0*9" (value*count)."""
    out = []; i = 0
    while i < len(row):
        j = i
        while j < len(row) and row[j] == row[i]: j += 1
        out.append("%d*%d" % (row[i], j - i)); i = j
    return ",".join(out)
def rects(mask):
    """Greedy merge of a cell mask into few axis-aligned [x, y, w, h] boxes (one box per wall run, floor patch, ...)."""
    m = mask.copy(); out = []
    gh, gw = m.shape
    for y in range(gh):
        x = 0
        while x < gw:
            if not m[y, x]: x += 1; continue
            x1 = x
            while x1 < gw and m[y, x1]: x1 += 1
            y1 = y + 1
            while y1 < gh and m[y1, x:x1].all(): y1 += 1
            m[y:y1, x:x1] = False
            out.append([x, y, x1 - x, y1 - y]); x = x1
    return out
def blobs(mask):
    """Connected pieces of a mask -> [cx, cy, w, h] (cells)."""
    seen = np.zeros_like(mask); gh, gw = mask.shape; out = []
    for y0 in range(gh):
        for x0 in range(gw):
            if mask[y0, x0] and not seen[y0, x0]:
                q = deque([(y0, x0)]); seen[y0, x0] = True; ys = []; xs = []
                while q:
                    y, x = q.popleft(); ys.append(y); xs.append(x)
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < gh and 0 <= nx < gw and mask[ny, nx] and not seen[ny, nx]: seen[ny, nx] = True; q.append((ny, nx))
                out.append([(min(xs) + max(xs) + 1) / 2, (min(ys) + max(ys) + 1) / 2, max(xs) - min(xs) + 1, max(ys) - min(ys) + 1])
    return out
def main(png, seeds_path, out_path, dbg=None):
    im = np.asarray(Image.open(png).convert("RGB")).astype(int)
    H, W = im.shape[:2]
    R, G, B = im[..., 0], im[..., 1], im[..., 2]
    bright = (G > 150) & (B > 160)
    white = bright & (R > 150)
    cyan_wall = (G > WALL_G) & (B > WALL_G + 10) & (R < 130)
    green = (G > 160) & (R < 150) & (B < 150) & (G > B + 30)
    # hull: everything the outside (flooded from the image edges through dark pixels) cannot reach
    seeds = json.load(open(seeds_path))
    barrier = np.array(Image.fromarray((bright * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) > 0
    title_box = seeds.get("ignore", [])
    for (x0, y0, x1, y1) in title_box: barrier[y0:y1, x0:x1] = False
    outside = np.zeros((H, W), bool)
    q = deque()
    for x in range(W):
        for y in (0, H - 1):
            if not barrier[y, x] and not outside[y, x]: outside[y, x] = True; q.append((y, x))
    for y in range(H):
        for x in (0, W - 1):
            if not barrier[y, x] and not outside[y, x]: outside[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < H and 0 <= nx < W and not outside[ny, nx] and not barrier[ny, nx]:
                outside[ny, nx] = True; q.append((ny, nx))
    hull = ~outside
    hull = np.array(Image.fromarray((hull * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))) > 0
    # cells
    gh, gw = H // CELL, W // CELL
    def cellfrac(m): return m[:gh * CELL, :gw * CELL].reshape(gh, CELL, gw, CELL).mean(axis=(1, 3))
    in_hull = cellfrac(hull) > 0.6
    wall = (cellfrac(cyan_wall) > 0.22) & in_hull
    door = (cellfrac(green) > 0.2) & in_hull
    door_marks = blobs(door)   # the green squares themselves, before the openings are widened
    # a door square is smaller than the wall is thick: open a gap right through the wall around it
    door = np.array(Image.fromarray((door * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(DOOR_GROW))) > 0
    door &= in_hull
    wall &= ~door
    # drop tiny wall islands (icons, deck markings): a real wall is a long connected line
    lab = np.zeros((gh, gw), np.int32); nlab = 0
    for y0 in range(gh):
        for x0 in range(gw):
            if wall[y0, x0] and lab[y0, x0] == 0:
                nlab += 1; lab[y0, x0] = nlab; qq = deque([(y0, x0)]); cells = [(y0, x0)]
                while qq:
                    y, x = qq.popleft()
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = y + dy, x + dx
                            if 0 <= ny < gh and 0 <= nx < gw and wall[ny, nx] and lab[ny, nx] == 0:
                                lab[ny, nx] = nlab; qq.append((ny, nx)); cells.append((ny, nx))
                if len(cells) < MIN_WALL:
                    for c in cells: wall[c] = False
    # the hull's own edge is a wall all the way round
    edge = in_hull & ~(np.array(Image.fromarray((in_hull * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))) > 0)
    wall |= edge & ~door
    for (x0, y0, x1, y1) in seeds.get("open", []): wall[y0 // CELL:y1 // CELL, x0 // CELL:x1 // CELL] = False
    # a door on a thick (or double) wall: tunnel straight through it, across the wall, to open floor on both sides
    for (dcx, dcy, dw, dh) in door_marks:
        cx, cy = int(dcx), int(dcy); best = None
        for ax in ((1, 0), (0, 1)):
            ends = []
            for sgn in (1, -1):
                k = 1
                while k <= TUNNEL_MAX:
                    x, y = cx + ax[0] * k * sgn, cy + ax[1] * k * sgn
                    if not (0 <= x < gw and 0 <= y < gh) or not in_hull[y, x]: k = None; break
                    if not wall[y, x] and not door[y, x]: break
                    k += 1
                ends.append(k if k and k <= TUNNEL_MAX else None)
            if None not in ends and (best is None or sum(ends) < best[1]): best = (ax, sum(ends), ends)
        if best is None: continue
        (axx, axy), _, (kp, km) = best
        for k in range(-km, kp + 1):
            for wdt in (-1, 0, 1):
                x, y = cx + axx * k + axy * wdt, cy + axy * k + axx * wdt
                if 0 <= x < gw and 0 <= y < gh and in_hull[y, x]: wall[y, x] = False; door[y, x] = True
    floor = in_hull & ~wall
    # rooms: flood from each label point through floor (doors stop the flood: they belong to no room)
    room = np.zeros((gh, gw), np.int32)
    rooms = []
    for i, s in enumerate(seeds["rooms"]):
        rid = i + 1
        cx, cy = s["at"][0] // CELL, s["at"][1] // CELL
        # nearest floor cell to the label point
        best = None
        cb = s.get("box"); bx0, by0, bx1, by1 = (cb[0] // CELL, cb[1] // CELL, cb[2] // CELL, cb[3] // CELL) if cb else (0, 0, gw, gh)
        for r in range(0, 20 if cb else 8):   # the nearest open floor to the label (the label's own letters can sit on a console)
            for yy in range(cy - r, cy + r + 1):
                for xx in range(cx - r, cx + r + 1):
                    if by0 <= yy < by1 and bx0 <= xx < bx1 and 0 <= yy < gh and 0 <= xx < gw and floor[yy, xx] and room[yy, xx] == 0 and not door[yy, xx]: best = (yy, xx); break
                if best: break
            if best: break
        if not best: rooms.append({**s, "id": rid, "cells": 0}); continue
        q = deque([best]); room[best] = rid; n = 1
        while q:
            y, x = q.popleft()
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if by0 <= ny < by1 and bx0 <= nx < bx1 and floor[ny, nx] and not door[ny, nx] and room[ny, nx] == 0:
                    room[ny, nx] = rid; q.append((ny, nx)); n += 1
        rooms.append({**s, "id": rid, "cells": n})
    # what the player can reach from the start (floor + doors)
    start = seeds["start"]; sy, sx = start[1] // CELL, start[0] // CELL
    def compute_reach():
        walk = floor | door
        reach = np.zeros_like(walk); q = deque()
        for r in range(0, 10):
            hit = [(yy, xx) for yy in range(sy - r, sy + r + 1) for xx in range(sx - r, sx + r + 1) if 0 <= yy < gh and 0 <= xx < gw and walk[yy, xx]]
            if hit: reach[hit[0]] = True; q.append(hit[0]); break
        while q:
            y, x = q.popleft()
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < gh and 0 <= nx < gw and walk[ny, nx] and not reach[ny, nx]: reach[ny, nx] = True; q.append((ny, nx))
        return walk, reach
    walk, reach = compute_reach()
    # AUTO-LINK: a labelled room the walls cut off (equipment outlines drawn as solid lines, a door on a wall too thick
    # to read) gets the shortest way in through the fewest wall cells, from the room itself. Each link is listed in the output ("links") so it can be checked against the plan.
    links = []
    if seeds.get("autolink", True):
        for _ in range(len(rooms)):
            changed = False
            for r in rooms:
                rm = room == r["id"]
                if not r["cells"] or (rm & reach).any(): continue
                src = list(zip(*np.nonzero(rm)))
                dist = {c: 0 for c in src}; prev = {}; dq = deque(src); goal = None
                while dq:
                    c = dq.popleft(); y, x = c
                    if reach[y, x]: goal = c; break
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = y + dy, x + dx
                        if not (0 <= ny < gh and 0 <= nx < gw) or not in_hull[ny, nx]: continue
                        w = 1 if wall[ny, nx] else 0
                        nd = dist[c] + w
                        if nd > LINK_MAX or nd >= dist.get((ny, nx), 1 << 30): continue
                        dist[(ny, nx)] = nd; prev[(ny, nx)] = c
                        if w: dq.append((ny, nx))
                        else: dq.appendleft((ny, nx))
                if goal is None: continue
                c = goal; carved = 0
                while c in prev:
                    y, x = c
                    for dy, dx in ((0, 0), (1, 0), (0, 1)):
                        yy, xx = y + dy, x + dx
                        if 0 <= yy < gh and 0 <= xx < gw and in_hull[yy, xx] and wall[yy, xx]: wall[yy, xx] = False; floor[yy, xx] = True; carved += 1
                    c = prev[c]
                if not carved: continue
                links.append({"room": r["name"], "carved_cells": carved}); changed = True
                walk, reach = compute_reach()
            if not changed: break
    # rows of the grid as strings: '#' wall, '.' floor, 'D' door, ' ' outside; plus the room id per floor cell
    rows = []
    for y in range(gh):
        rows.append("".join("D" if door[y, x] else "#" if wall[y, x] else "." if floor[y, x] else " " for x in range(gw)))
    out = {"source": png.split("/")[-1], "cell_px": CELL, "w": gw, "h": gh, "rows": rows, "room_rows": [rle(room[y]) for y in range(gh)],
           "rooms": [{"id": r["id"], "name": r["name"], "cells": r["cells"], "box": [v / CELL for v in r.get("box", [0, 0, 0, 0])], "at": [r["at"][0] / CELL, r["at"][1] / CELL], "reachable": bool(r["cells"] and reach[min(gh - 1, r["at"][1] // CELL), min(gw - 1, r["at"][0] // CELL)] or any(reach[room == r["id"]])) } for r in rooms],
           "lifts": [[l[0] / CELL, l[1] / CELL] for l in seeds.get("lifts", [])], "start": [start[0] / CELL, start[1] / CELL],
           "walls": rects(wall), "corridor": rects(floor & (room == 0) & reach), "sealed": rects(walk & ~reach),
           "room_floor": {str(r["id"]): rects(room == r["id"]) for r in rooms}, "doors": door_marks, "door_open": rects(door),
           "links": links, "walk_cells": int(walk.sum()), "reach_cells": int(reach.sum())}
    json.dump(out, open(out_path, "w"))
    if dbg:
        rgb = np.zeros((gh, gw, 3), np.uint8)
        rng = np.random.default_rng(3); cols = rng.integers(60, 230, (len(rooms) + 2, 3))
        rgb[floor] = (40, 40, 50)
        for r in rooms: rgb[room == r["id"]] = cols[r["id"]]
        rgb[floor & (room == 0)] = (90, 90, 90)
        rgb[wall] = (230, 230, 230); rgb[door] = (0, 255, 0)
        rgb[walk & ~reach] = (255, 0, 0)
        Image.fromarray(rgb).resize((gw * 3, gh * 3), Image.NEAREST).save(dbg)
    print(json.dumps({"links": links, "rooms": [(r["name"], r["cells"]) for r in rooms], "walk": int(walk.sum()), "reach": int(reach.sum()), "grid": [gw, gh]}))
if __name__ == "__main__":
    main(*sys.argv[1:])
