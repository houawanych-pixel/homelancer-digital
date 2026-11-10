#!/usr/bin/env python3
"""Deck plan PNG -> wall outlines at full picture detail (v13.00), for the 3D walk-through shell.

extract.py reads the plan on a 4 px (0.6 m) grid, which loses thin and curved walls (the round CIC).
This reads the picture itself: every bright line is a wall, green squares are door openings, small bright
bits (letters, icons) are dropped, mid-size free-standing bits inside a room become low cover.

  python3 trace.py <plan.png> assets/holodeck/<id>.json [debug.png] [seeds/<id>.json]

Writes "shell" into the json (outlines in grid-cell units, walkable side on the left), replacing shell.py's.
Check: the floor is shrunk by the player's width and every labelled room must still be reachable from the start.
"""
import json, sys
import numpy as np, cv2

CELL = 4
EPS = 1.6          # px: straightening tolerance (0.24 m)
WALL_PAD = 1       # px: lines are fattened by this (walls about 0.5 m thick at least)
SMALL = 260        # px area: bright bits smaller than this are letters / icons -> dropped
COVER_MAX = 2600   # px area: a free-standing solid up to this is cover
DOOR_PAD = 7       # px: a door opening reaches this far past the green square (through double walls)
PLAYER_R = 3       # px (0.45 m)
TUN = 44           # px: the thickest wall band a door may tunnel through
FLOOR_RUN = 8      # px of clear floor that counts as the far side
COVER_LEN = 44     # px: cover is compact (under 6.6 m across)
DOOR_W = 20        # px: the narrowest doorway (3.0 m; owner: "the doorway should be a little bit bigger")

def main(png, jpath, dbg=None, seeds=None):
    d = json.load(open(jpath))
    opens = json.load(open(seeds)).get("open", []) if seeds else []
    im = cv2.imread(png).astype(int)
    H, W = im.shape[:2]
    B, G, R = im[..., 0], im[..., 1], im[..., 2]
    bright = ((G > 150) & (B > 160)).astype(np.uint8)
    green = ((G > 160) & (R < 150) & (B < 150) & (G > B + 30)).astype(np.uint8)
    # inside the hull = the grid's own hull (extract.py), at picture size
    hull = np.array([[c != " " for c in row.ljust(d["w"])[:d["w"]]] for row in d["rows"]], np.uint8)
    hull = cv2.resize(hull, (d["w"] * CELL, d["h"] * CELL), interpolation=cv2.INTER_NEAREST)
    hull = np.pad(hull, ((0, H - hull.shape[0]), (0, W - hull.shape[1])))
    # walls: bright lines, minus small pieces (letters, icons)
    n, lab, st, _ = cv2.connectedComponentsWithStats(bright, connectivity=8)
    wall = np.zeros_like(bright)
    for i in range(1, n):
        if st[i, cv2.CC_STAT_AREA] >= SMALL: wall[lab == i] = 1
    wall = cv2.dilate(wall, np.ones((2 * WALL_PAD + 1,) * 2, np.uint8))
    # door openings
    n, lab, st, _ = cv2.connectedComponentsWithStats(green, connectivity=8)
    door = np.zeros_like(green)
    rects = []   # each green door's opening [x0, y0, x1, y1] px (a locked door's barrier fills it)
    for i in range(1, n):
        x, y, w, h, a = st[i]
        if a < 30 or max(w, h) > 40: continue
        # tunnel across the wall(s): march out from the square, both ways, until real open floor (a clear run of
        # FLOOR_RUN px; the thin gap inside a double line does not count). The shorter axis that works is the doorway.
        free = (hull & (1 - wall)).astype(bool)
        cx, cy = x + w // 2, y + h // 2
        best = None
        for ax in ((0, 1), (1, 0)):
            half = (h if ax[1] else w) // 2
            ends = []
            for sg in (1, -1):
                k = half; run = 0; ok = None
                while k < half + TUN:
                    xx, yy = cx + ax[0] * k * sg, cy + ax[1] * k * sg
                    if not (0 <= xx < W and 0 <= yy < H) or not hull[yy, xx]: break
                    run = run + 1 if free[yy, xx] else 0
                    if run >= FLOOR_RUN: ok = k; break
                    k += 1
                ends.append(ok)
            if None not in ends and (best is None or sum(ends) < best[1]): best = (ax, sum(ends), ends)
        if best is None:
            door[max(0, y - 4):y + h + 4, max(0, x - 4):x + w + 4] = 1
            rects.append([x - 4, y - 4, x + w + 4, y + h + 4])
            continue
        (axx, axy), _, (kp, km) = best
        wd = max(DOOR_W, (w if axy else h)) // 2
        if axy: door[cy - km:cy + kp + 1, cx - wd:cx + wd + 1] = 1; rects.append([cx - wd, cy - km, cx + wd + 1, cy + kp + 1])
        else: door[cy - wd:cy + wd + 1, cx - km:cx + kp + 1] = 1; rects.append([cx - km, cy - wd, cx + kp + 1, cy + wd + 1])
    for (x0, y0, x1, y1) in opens:   # drawn passages with no green square (stairs, ramps): seeds "open"; doorways too
        door[y0:y1, x0:x1] = 1; rects.append([x0, y0, x1, y1])
    floor = (hull & (1 - wall)) | (door & hull)
    sx, sy = int(d["start"][0] * CELL), int(d["start"][1] * CELL)
    _, labf = cv2.connectedComponents(floor.astype(np.uint8), connectivity=4)
    if labf[sy, sx] == 0:
        ys, xs = np.nonzero(labf[sy - 20:sy + 20, sx - 20:sx + 20]); sy, sx = sy - 20 + ys[0], sx - 20 + xs[0]
    reach = (labf == labf[sy, sx]).astype(np.uint8)
    solid = 1 - reach
    n2, lab2, st2, _ = cv2.connectedComponentsWithStats(solid, connectivity=8)
    cover = np.zeros_like(solid)
    for i in range(n2):
        if i == lab2[0, 0] or st2[i, cv2.CC_STAT_AREA] > COVER_MAX: continue
        if max(st2[i, cv2.CC_STAT_WIDTH], st2[i, cv2.CC_STAT_HEIGHT]) > COVER_LEN: continue   # a long piece is a wall between two doors, not cover
        if solid[lab2 == i][0]: cover[lab2 == i] = 1
    area = reach | cover

    def trace(mask, want):
        cs, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
        out = []
        for c in cs:
            if len(c) < 12: continue
            a = cv2.approxPolyDP(c, EPS, True).reshape(-1, 2).astype(float)
            if len(a) < 3: continue
            a += 0.5
            votes = 0
            for k in range(len(a)):
                p, q = a[k], a[(k + 1) % len(a)]
                e = q - p; L = np.hypot(*e)
                if L < 3: continue
                m = (p + q) / 2 + np.array([e[1], -e[0]]) / L * 2.5
                x, y = int(m[0]), int(m[1])
                if 0 <= x < W and 0 <= y < H: votes += 1 if mask[y, x] == want else -1
            if votes < 0: a = a[::-1]
            out.append([round(float(v) / CELL, 3) for v in a.reshape(-1)])
        return out
    walls = trace(area.astype(np.uint8), 1)
    covers = trace(cover, 0)
    big = np.zeros((H, W), np.uint8)
    P = lambda p: np.round(np.array(p).reshape(-1, 2) * CELL).astype(np.int32)
    cv2.fillPoly(big, [P(p) for p in walls], 1)
    for p in covers: cv2.fillPoly(big, [P(p)], 0)
    er = cv2.erode(big, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * PLAYER_R + 1,) * 2))
    _, lab3 = cv2.connectedComponents(er, connectivity=4)
    win = lab3[sy - 6:sy + 7, sx - 6:sx + 7]; s = int(np.bincount(win[win > 0]).argmax()) if (win > 0).any() else 0
    bad = []
    for rm in d["rooms"]:
        x, y = int(rm["at"][0] * CELL), int(rm["at"][1] * CELL)
        if s == 0 or not (lab3[max(0, y - 30):y + 31, max(0, x - 30):x + 31] == s).any(): bad.append(rm["name"])
    d["shell"] = {"walls": walls, "cover": covers, "eps_px": EPS, "from": "trace.py",
                  "doors": [{"rect": [round(v / CELL, 2) for v in r], "level": 0} for r in rects],
                  "check": {"rooms": len(d["rooms"]), "cut_off": bad, "start_ok": bool(s != 0)}}
    json.dump(d, open(jpath, "w"), separators=(",", ":"))
    print(json.dumps({"walls": len(walls), "points": sum(len(p) // 2 for p in walls), "cover": len(covers), "cut_off": bad, "start_ok": bool(s != 0)}))
    if dbg:
        v = np.zeros((H, W, 3), np.uint8)
        v[floor > 0] = (45, 45, 45); v[big > 0] = (90, 70, 40); v[(lab3 == s) & (s != 0)] = (150, 110, 50)
        for p in covers: cv2.fillPoly(v, [P(p)], (60, 150, 230))
        v[door > 0] = (v[door > 0] * 0.5 + np.array((60, 255, 90)) * 0.5).astype(np.uint8)
        cv2.polylines(v, [P(p) for p in walls], True, (255, 240, 160), 1, cv2.LINE_AA)
        cv2.imwrite(dbg, v)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None, sys.argv[4] if len(sys.argv) > 4 else None)
