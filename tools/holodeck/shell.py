#!/usr/bin/env python3
"""Deck plan grid -> smooth wall outlines for the 3D shell (v13.0x).

The grid in assets/holodeck/<id>.json is made of 0.6 m cells, so walls built cell by cell come out as
stair-steps. This traces the edge of the walkable deck and straightens it, so slanted and round walls
on the plan are slanted and round in 3D. Small things standing inside a room (drawn equipment) become
low COVER instead of full walls.

  python3 shell.py assets/holodeck/<id>.json [debug.png]

Adds to the json:  "shell": {"walls": [[x,y, x,y, ...], ...], "cover": [[...], ...], "eps": .., "check": {...}}
Every outline is closed, in cell units, with the walkable side on its LEFT (so the wall face normal is known).
Nothing is invented: only the plan's own grid is read. The check re-draws the outlines, shrinks the floor by the
player's width and confirms every labelled room can still be walked to from the start.
"""
import json, sys
import numpy as np, cv2

UP = 4            # trace at 4x the grid
EPS = 0.7         # cells: how far a straightened wall may sit from the stepped one
COVER_MAX = 70    # cells: a free-standing solid smaller than this is cover (about 25 m2)
PLAYER_R = 0.6    # cells (0.36 m)

def main(path, dbg=None):
    d = json.load(open(path))
    w, h = d["w"], d["h"]
    g = np.array([[c in ".D" for c in row.ljust(w)[:w]] for row in d["rows"]], np.uint8)
    # reachable floor from the start
    sx, sy = int(d["start"][0]), int(d["start"][1])
    n, lab = cv2.connectedComponents(g, connectivity=4)
    reach = (lab == lab[sy, sx]).astype(np.uint8)
    solid = 1 - reach
    # free-standing solids = cover
    n2, lab2, stats, _ = cv2.connectedComponentsWithStats(solid, connectivity=8)
    outer = lab2[0, 0]
    cover = np.zeros_like(solid)
    for i in range(n2):
        if i == outer or not (lab2 == i).any() or solid[lab2 == i][0] == 0: continue
        if stats[i, cv2.CC_STAT_AREA] <= COVER_MAX: cover[lab2 == i] = 1
    floor = reach | cover          # walls go round this; cover stands on it

    def trace(mask, want_inside):
        big = cv2.resize(mask, (w * UP, h * UP), interpolation=cv2.INTER_NEAREST)
        cs, _ = cv2.findContours(big, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
        out = []
        for c in cs:
            if len(c) < 8: continue
            a = cv2.approxPolyDP(c, EPS * UP, True).reshape(-1, 2).astype(float)
            if len(a) < 3: continue
            a = (a + 0.5) / UP
            # orient: the wanted side (mask==want_inside) on the LEFT of each edge.
            # In image axes (y down) "left" of direction (dx,dy) is (dy,-dx).
            votes = 0
            for k in range(len(a)):
                p, q = a[k], a[(k + 1) % len(a)]
                e = q - p; L = np.hypot(*e)
                if L < 1.0: continue
                m = (p + q) / 2 + np.array([e[1], -e[0]]) / L * 0.75
                x, y = int(m[0]), int(m[1])
                if 0 <= x < w and 0 <= y < h: votes += 1 if mask[y, x] == want_inside else -1
            if votes < 0: a = a[::-1]
            out.append([round(float(v), 2) for v in a.reshape(-1)])
        return out

    walls = trace(floor, 1)        # floor on the left
    covers = trace(cover, 0)       # floor (not cover) on the left
    # check: redraw, shrink by the player, flood from the start
    big = np.zeros((h * UP, w * UP), np.uint8)
    polys = [np.round(np.array(p).reshape(-1, 2) * UP).astype(np.int32) for p in walls]
    cv2.fillPoly(big, polys, 1)    # even-odd: holes stay solid
    for p in covers: cv2.fillPoly(big, [np.round(np.array(p).reshape(-1, 2) * UP).astype(np.int32)], 0)
    r = int(round(PLAYER_R * UP))
    er = cv2.erode(big, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1)))
    _, lab3 = cv2.connectedComponents(er, connectivity=4)
    s = lab3[sy * UP + UP // 2, sx * UP + UP // 2]
    bad = []
    for rm in d["rooms"]:
        x, y = int(rm["at"][0] * UP), int(rm["at"][1] * UP)
        win = lab3[max(0, y - 12):y + 13, max(0, x - 12):x + 13]
        if s == 0 or not (win == s).any(): bad.append(rm["name"])
    d["shell"] = {"walls": walls, "cover": covers, "eps": EPS,
                  "check": {"rooms": len(d["rooms"]), "cut_off": bad, "start_ok": bool(s != 0)}}
    json.dump(d, open(path, "w"), separators=(",", ":"))
    print(json.dumps({"walls": len(walls), "points": sum(len(p) // 2 for p in walls), "cover": len(covers), "cut_off": bad, "start_ok": bool(s != 0)}))
    if dbg:
        im = np.zeros((h * UP, w * UP, 3), np.uint8)
        im[big > 0] = (70, 60, 40)
        for p in polys: cv2.polylines(im, [p], True, (255, 230, 120), 1, cv2.LINE_AA)
        for p in covers: cv2.polylines(im, [np.round(np.array(p).reshape(-1, 2) * UP).astype(np.int32)], True, (80, 200, 255), 1, cv2.LINE_AA)
        cv2.imwrite(dbg, im)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
