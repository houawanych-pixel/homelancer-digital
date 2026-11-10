#!/usr/bin/env python3
"""Any fleet ship: PROPOSED upper / lower decks, lifts, access-coloured doors and key guards (v13.00).

The owner approved the Unity Capital room setup (tools/holodeck/decks_unity_capital.py, laid out by hand) and asked
for the same on every ship. This builds it by rule, from what the blueprint gives: the hull outline, the traced
main deck (trace.py) and the plan's lift squares. Everything it adds is a PROPOSAL, marked so in the game:
  - decks:  Capital, Cruiser, Destroyer, Resupply, TroopTransport get an upper and a lower deck; Frigate and Escort
            get a lower deck; Scout and Bomber stay one deck (too small).
  - lifts:  the plan's own lift squares where it draws them (4: forward pair up, aft pair down; 2: both ways).
            Where the plan draws none, two lift pads are put in the widest clear corridor, a matched pair.
  - layout: each extra deck is a loop passage round a block of rooms with the lift lobby across it, and where the
            hull has room an end room off a side stub. No straight run end to end. Rooms are chamfered or round.
  - access: one yellow, one orange and one red room per extra deck; on the main deck the armory is yellow, the
            engine room (or reactor) orange and the bridge red, wherever the traced walls can actually seal them.
  - guards: the yellow key on a guard in an open room, the orange key behind yellow, the red key behind orange.
Room names on the new decks are working labels, not lore.

  python3 decks.py assets/holodeck/<id>.json assets/holodeck [debug.jpg]
"""
import json, sys, os
import numpy as np, cv2
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import decks_unity_capital as U
from decks_unity_capital import CELL, KEY_NAME, PAD, reach_at, near, travel_axis, outlines, hull_px

CW = 20            # px: passage width (3 m)
THREE = ("Capital", "Cruiser", "Destroyer", "Resupply", "TroopTransport")
TWO = ("Frigate", "Escort")
UPPER_NAMES = ["Ready Room", "Comms Center", "Chart Room", "Signal Office"]; UPPER_END = "Observation Lounge"
LOWER_NAMES = ["Brig", "Machine Shop", "Munitions Store", "Water Reclamation"]; LOWER_END = "Pump Room"
UPPER_FILL = ["Officers' Quarters", "Briefing Room", "Flight Control", "Gunnery Control", "Records Office", "Officers' Mess", "Guest Quarters",
              "Gym", "Library", "Sick Bay", "Signal Store", "Map Room", "Duty Office", "Watch Room", "Stateroom", "Conference Room"]
LOWER_FILL = ["Storage", "Workshop", "Parts Store", "Water Tanks", "Fuel Control", "Waste Processing", "Laundry", "Cold Store", "Crew Mess",
              "Bunk Room", "Tool Crib", "Battery Room", "Air Plant", "Locker Room", "Cable Run", "Filter Room"]
UPPER_HALLS = ["Wardroom", "Observation Lounge", "Assembly Hall", "Mess Hall"]; LOWER_HALLS = ["Pump Room", "Cargo Hall", "Machine Hall", "Tank Hall"]
PX, PY = 124, 112   # px: the room grid's pitch across and along the ship (a passage, a wall, a room, a wall): rooms about 13 x 11 m
LOCK_TRY = {1: ["Armory", "Weapons Locker", "Magazine", "Cargo"], 2: ["Engine Room", "Reactor", "Engineering"], 3: ["Bridge", "Cockpit", "CIC"]}
GUARD_TRY = ["Medbay", "Galley", "Crew Quarters", "Mess"]

def main_floor(d, H, W):
    sh = d["shell"]
    f = np.zeros((H, W), np.uint8)
    cv2.fillPoly(f, [np.round(np.array(p).reshape(-1, 2) * CELL).astype(np.int32) for p in sh["walls"]], 1)
    for p in sh["cover"]: cv2.fillPoly(f, [np.round(np.array(p).reshape(-1, 2) * CELL).astype(np.int32)], 0)
    return f

def room_grid(d, H, W):
    g = np.zeros((d["h"], d["w"]), np.int32)
    for y, row in enumerate(d["room_rows"]):
        x = 0
        for run in row.split(","):
            v, n = run.split("*") if "*" in run else (run, 1)
            g[y, x:x + int(n)] = int(v); x += int(n)
    g = cv2.resize(g.astype(np.float32), (d["w"] * CELL, d["h"] * CELL), interpolation=cv2.INTER_NEAREST).astype(np.int32)
    return np.pad(g, ((0, H - g.shape[0]), (0, W - g.shape[1])))

def pick_lifts(d, floor, doors, start, hull):
    """No lift squares on the plan: a matched pair of pads in the widest clear corridor near midships."""
    H, W = floor.shape
    reach = reach_at(floor, doors, 0, start).astype(np.uint8)
    corr = reach & (room_grid(d, H, W) == 0).astype(np.uint8)
    for dr in doors:
        x0, y0, x1, y1 = [int(round(v)) for v in dr["rect"]]; corr[max(0, y0 - 12):y1 + 12, max(0, x0 - 12):x1 + 12] = 0
    dist = cv2.distanceTransform(corr, cv2.DIST_L2, 5)
    ys, xs = np.nonzero(hull); cx = (xs.min() + xs.max()) / 2.0; ymid = (ys.min() + ys.max()) / 2.0
    best = None
    py, px = np.nonzero(dist >= 8)
    for y, x in zip(py, px):
        if x >= cx - 30 or x < cx - 110: continue
        mx = int(round(2 * cx - x))
        if not (0 <= mx < W) or dist[y, mx] < 8: continue
        sc = min(dist[y, x], dist[y, mx]) - 0.08 * abs(y - ymid) - 0.02 * abs((cx - x) - 60)
        if best is None or sc > best[0]: best = (sc, [[int(x), int(y)], [mx, int(y)]])
    if best: return best[1], "pair"
    if not len(py): return [], "none"
    i = int(np.argmax(dist[py, px] - 0.03 * np.abs(py - ymid)))
    return [[int(px[i]), int(py[i])]], "single"

def fit_rect(D, lifts, bias):
    """The biggest box inside this deck's hull that holds the lift row. bias -1 reaches toward the bow, +1 the stern."""
    H, W = D.shape
    cx = int(round(sum(l[0] for l in lifts) / len(lifts))); ly = int(lifts[0][1])
    need = max(abs(l[0] - cx) for l in lifts) + 30
    hw = np.zeros(H, int)
    for y in range(H):
        row = D[y]
        if not row[cx]: continue
        l = cx
        while l > 0 and row[l - 1]: l -= 1
        r = cx
        while r < W - 1 and row[r + 1]: r += 1
        hw[y] = min(cx - l, r - cx)
    best = None
    for ya in range(ly - 36, max(0, ly - 330), -6):
        for yb in range(ly + 36, min(H, ly + 330), 6):
            if yb - ya > 330: break
            w = int(hw[ya:yb].min())
            if w < max(48, need): break
            w = min(w, max(170, need))
            lean = ((ly - ya) - (yb - ly)) / float(yb - ya) * -bias     # >0 when it leans the wanted way
            sc = 2 * w * (yb - ya) * (1.0 + 0.6 * lean)
            if best is None or sc > best[0]: best = (sc, (cx - w, ya, cx + w, yb))
    return (best[1], cx, ly) if best else (None, cx, ly)

def layout(D, lifts, bias, names, end_name):
    H, W = D.shape
    rect, cx, ly = fit_rect(D, lifts, bias)
    if rect is None: return None
    x0, y0, x1, y1 = rect
    k = U.Deck(H, W); k.CX = cx
    k.box(x0, y0, x1, y0 + CW); k.box(x0, y1 - CW, x1, y1); k.box(x0, y0, x0 + CW, y1); k.box(x1 - CW, y0, x1, y1)
    k.box(x0, ly - CW // 2, x1, ly + CW // 2)
    for lx, _ in lifts: k.box(lx - 16, ly - 16, lx + 16, ly + 16, 4)
    ix0, ix1 = x0 + CW + 10, x1 - CW - 10
    cells = [(y0 + CW + 10, ly - CW // 2 - 10, "top"), (ly + CW // 2 + 10, y1 - CW - 10, "bot")]
    rooms = []   # (x0, y0, x1, y1, door rect)
    for (ca, cb, where) in cells:
        if cb - ca < 44: continue
        cols = [(ix0, cx - 12), (cx + 12, ix1)] if ix1 - ix0 >= 150 else [(ix0, ix1)]
        for ci, (ra, rb) in enumerate(cols):
            my, mx = (ca + cb) // 2, (ra + rb) // 2
            kind = (where, ci, len(cols))
            if where == "top" and ci == 0: door = (mx - 11, y0 + CW - 2, mx + 11, ca + 2)            # up onto the forward passage
            elif where == "top": door = (mx - 11, cb - 2, mx + 11, ly - CW // 2 + 2)                 # down onto the lift lobby
            elif ci == 0 and len(cols) == 2: door = (x0 + CW - 2, my - 11, ra + 2, my + 11)          # out onto the port passage
            else: door = (mx - 11, cb - 2, mx + 11, y1 - CW + 2)                                     # down onto the aft passage
            rooms.append((ra, ca, rb, cb, door))
    # the end room, off a side stub, where the hull has the space
    end = None
    edge = y0 if bias < 0 else y1
    for r in range(46, 25, -4):
        yc = edge + bias * (r + 30)
        if not (r + 2 <= yc < H - r - 2): continue
        m = np.zeros_like(D); cv2.circle(m, (cx, int(yc)), r + 4, 1, -1)
        if (m & (1 - D)).sum() == 0: end = (cx, int(yc), r); break
    lv_of = {}
    order = list(range(len(rooms)))
    if rooms: lv_of[order[0]] = 1
    if len(rooms) > 1: lv_of[order[1]] = 2
    if end is None and len(rooms) > 2: lv_of[order[-1]] = 3
    for i, (ra, ca, rb, cb, door) in enumerate(rooms):
        k.box(ra, ca, rb, cb, 12); k.door(door[0], door[1], door[2], door[3], lv_of.get(i, 0))
        k.room(names[i % len(names)], (ra + rb) // 2, (ca + cb) // 2)
    if end:
        ex, ey, r = end
        k.disc(ex, ey, r)
        sx = ex + int(r * 0.55)                               # the stub comes off the passage to one side of the room
        ya, yb = (ey, edge) if bias < 0 else (edge, ey)
        k.box(sx - 10, min(ya, yb), sx + 10, max(ya, yb))
        dy = edge + bias * 12
        k.door(sx - 11, min(dy, edge) - 2, sx + 11, max(dy, edge) + 2, 3)
        k.room(end_name, ex, ey)
    k.f &= D
    return k, rect

def _oct(cx, cy, apo):
    """A regular octagon with flat sides facing bow, stern, port, starboard and the four diagonals."""
    r = apo / np.cos(np.pi / 8)
    return [(cx + r * np.cos(np.pi / 8 + k * np.pi / 4), cy + r * np.sin(np.pi / 8 + k * np.pi / 4)) for k in range(8)]

def choose_ring(d, floor, doors, start, D, plan_lifts):
    """v13.00 (owner: "they all need to be centre mass ... in the centre of the silhouette"): the extra decks are
    centred on the middle of the hull's own outline, and the lifts go where the deck's ring passage is.
    Returns (cx, cy, ring radius, lifts, how). The plan's own lift pair is used when the ring can pass through it;
    otherwise a matched pair of pads is put on the ring where the main deck below has clear floor."""
    H, W = D.shape
    ys, xs = np.nonzero(D)
    cx, cy = int(round(xs.mean())), int(round(ys.mean()))
    R = float(cv2.distanceTransform(D, cv2.DIST_L2, 5)[cy, cx])
    for a in plan_lifts:
        for b in plan_lifts:
            if a[0] < b[0] and abs(a[1] - b[1]) <= 10 and abs((a[0] + b[0]) / 2.0 - cx) <= 12:
                rr = (np.hypot(a[0] - cx, a[1] - cy) + np.hypot(b[0] - cx, b[1] - cy)) / 2.0
                if 46 <= rr <= 110 and rr + CW / 2 + 8 + 36 <= R: return cx, cy, float(rr), [a, b], "the plan's own pair"
    reach = reach_at(floor, doors, 0, start).astype(np.uint8)
    corr = (room_grid(d, H, W) == 0)
    ok = reach.copy()
    for dr in doors:
        x0, y0, x1, y1 = [int(round(v)) for v in dr["rect"]]; ok[max(0, y0 - 12):y1 + 12, max(0, x0 - 12):x1 + 12] = 0
    clear = cv2.distanceTransform(ok, cv2.DIST_L2, 5)
    best = None
    for rr in range(46, max(47, min(110, int(R - CW / 2 - 8 - 36)) + 1), 4):
        for th in range(-50, 51, 5):
            px = rr * np.cos(np.radians(th)); py = rr * np.sin(np.radians(th))
            a = (int(round(cx - px)), int(round(cy + py))); b = (int(round(cx + px)), int(round(cy + py)))
            if not all(0 <= q[0] < W and 0 <= q[1] < H for q in (a, b)): continue
            c = min(clear[a[1], a[0]], clear[b[1], b[0]])
            if c < 7: continue
            sc = min(c, 14) + 6 * (corr[a[1], a[0]] and corr[b[1], b[0]]) - 0.1 * abs(th) - 0.05 * abs(rr - 70)
            if best is None or sc > best[0]: best = (sc, float(rr), [list(a), list(b)])
    if best: return cx, cy, best[1], best[2], "added pair, on the ring"
    return cx, cy, 0.0, [], "none"

def radial(D, cx, yc, rr, lifts, variant, names, hub_name, end_names):
    """v13.00 (owner: "upper and lower rooms need to be more towards the centre ... triple-A style"): a deck built
    round the middle of the ship. A central hub room, a ring passage round it with the lifts on the ring, four wedge
    rooms fanning off the ring on the diagonals, and a spoke to an end room toward the bow and one toward the stern.
    variant "oct": an eight-sided hub you walk through (doors bow and stern side). variant "round": a round core
    room, shut behind orange doors, that you go round. Returns None when the hull is too narrow here for it."""
    H, W = D.shape
    dist = cv2.distanceTransform(D, cv2.DIST_L2, 5)
    R = float(dist[yc, cx])
    if rr < 46 or R < rr + CW / 2 + 8 + 36: return None
    rh = rr - CW / 2 - 8                  # hub
    Ro = min(R - 3, rr + CW / 2 + 8 + 96)  # outer reach of the wedge rooms
    k = U.Deck(H, W); k.CX = cx
    ring = np.zeros((H, W), np.uint8); hole = np.zeros((H, W), np.uint8)
    # the ring is round on both decks (so a lift anywhere on it lines up deck to deck); the hub's shape differs
    cv2.circle(ring, (cx, yc), int(rr + CW / 2), 1, -1); cv2.circle(hole, (cx, yc), int(rr - CW / 2), 1, -1)
    if variant == "oct": k.poly(_oct(cx, yc, rh * np.cos(np.pi / 8) + 2))
    else: k.disc(cx, yc, rh)
    if rh > 70:   # a big hub is a hall: four pillars stand in it (cover), on the diagonals for the eight-sided one
        for q in range(4):
            a = np.radians(45 + 90 * q if variant == "oct" else 90 * q)
            px, py = cx + 0.55 * rh * np.cos(a), yc + 0.55 * rh * np.sin(a)
            cv2.fillPoly(k.f, [np.round(np.array(_oct(px, py, max(9.0, rh * 0.11)))).astype(np.int32)], 0)
    k.f |= ring & (1 - hole)
    for lx, ly_ in lifts: k.box(lx - 15, ly_ - 15, lx + 15, ly_ + 15, 4)
    hub_lv = 0 if variant == "oct" else 2
    if variant == "oct":                  # through the hub bow to stern
        k.door(cx - 11, int(yc - rr + CW / 2) - 2, cx + 11, int(yc - rh * np.cos(np.pi / 8)) + 4, hub_lv)
        k.door(cx - 11, int(yc + rh * np.cos(np.pi / 8)) - 4, cx + 11, int(yc + rr - CW / 2) + 2, hub_lv)
    else:                                 # the core opens port and starboard
        k.door(int(cx - rr + CW / 2) - 2, yc - 11, int(cx - rh) + 2, yc + 11, hub_lv)
        k.door(int(cx + rh) - 2, yc - 11, int(cx + rr - CW / 2) + 2, yc + 11, hub_lv)
    k.room(hub_name, cx, yc)
    # the four wedge rooms on the diagonals
    ai = rr + CW / 2 + 8; ao = (Ro - 2) * np.cos(np.radians(21)); n = 0
    lv = {0: 1, 1: (2 if variant == "oct" else 0)}
    if ao - ai >= 30:
        for qi, ang in enumerate((225, 315, 135, 45)):          # port-bow, starboard-bow, port-stern, starboard-stern
            u = np.array([np.cos(np.radians(ang)), np.sin(np.radians(ang))]); v = np.array([-u[1], u[0]])
            hi = ai * np.tan(np.radians(22.5)) - 5; ho = ao * np.tan(np.radians(21)); ch = 9
            c = np.array([cx, yc], float)
            pts = [c + ai * u - hi * v, c + ai * u + hi * v, c + (ao - ch) * u + ho * v, c + ao * u + (ho - ch) * v,
                   c + ao * u - (ho - ch) * v, c + (ao - ch) * u - ho * v]
            m = np.zeros((H, W), np.uint8); cv2.fillPoly(m, [np.round(np.array(pts)).astype(np.int32)], 1)
            if (m & (1 - D)).sum(): continue
            k.f |= m
            # its door: across the 8 px wall, square to the diagonal
            dc = c + (ai - 4) * u; hw_ = 11; hl = 7
            dp = [dc + a * v + b * u for a, b in ((-hw_, -hl), (hw_, -hl), (hw_, hl), (-hw_, hl))]
            dm = np.zeros((H, W), np.uint8); cv2.fillPoly(dm, [np.round(np.array(dp)).astype(np.int32)], 1); k.f |= dm
            xs = [p[0] for p in dp]; ys = [p[1] for p in dp]
            k.doors.append({"rect": [int(min(xs)), int(min(ys)), int(max(xs)) + 1, int(max(ys)) + 1], "level": lv.get(n, 0),
                            "rot": round(float(np.degrees(np.arctan2(-v[1], v[0]))), 1), "w": 2 * hw_, "l": 2 * hl})
            mid = c + (ai + ao) / 2 * u
            k.room(names[qi % len(names)], int(mid[0]), int(mid[1])); n += 1
    # v13.00 (owner: "more full, more bigger, more things ... you got a big silhouette to work with"): the rest of the
    # hull is filled. A grid of passages runs out from the hub, bow to stern and side to side, with a room in every
    # cell that fits inside the hull. Every second row the centre passage stops at a wide hall you walk through, so
    # there is no straight run end to end. Rooms take their door on the side toward the centre line.
    xl = lambda kk: cx + kk * PX
    yl = lambda r: yc - PY // 2 + r * PY
    built = cv2.dilate(k.f, np.ones((21, 21), np.uint8))   # the hub, ring and wedge rooms, with a wall's width round them
    def far(x0, y0, x1, y1, _lim):   # clear of everything built so far
        return not built[int(y0):int(y1), int(x0):int(x1)].any()
    def inside(x0, y0, x1, y1, pad):
        x0, y0, x1, y1 = int(x0 - pad), int(y0 - pad), int(x1 + pad), int(y1 + pad)
        return x0 >= 0 and y0 >= 0 and x1 < W and y1 < H and bool(D[y0:y1, x0:x1].all())
    KS = range(-9, 9); RS = range(-12, 12)
    cell = {}
    for kk in KS:
        for r in RS:
            box = (xl(kk) + 18, yl(r) + 18, xl(kk + 1) - 18, yl(r + 1) - 18)
            if inside(*box, 10) and far(*box, Ro + 14): cell[(kk, r)] = box
    hall = {r: (xl(-1) + 18, yl(r) + 18, xl(1) - 18, yl(r + 1) - 18) for r in RS if r % 2 == 0 and (-1, r) in cell and (0, r) in cell}
    vseg = {}; hseg = {}
    for kk in KS:
        for r in RS:
            if ((kk - 1, r) in cell or (kk, r) in cell) and not (kk == 0 and r in hall):
                box = (xl(kk) - 10, yl(r) - 10, xl(kk) + 10, yl(r + 1) + 10)
                if inside(*box, 2) and far(*box, Ro + 12): vseg[(kk, r)] = box
            if (kk, r - 1) in cell or (kk, r) in cell:
                box = (xl(kk) - 10, yl(r) - 10, xl(kk + 1) + 10, yl(r) + 10)
                if inside(*box, 2) and far(*box, Ro + 12): hseg[(kk, r)] = box
    for box in list(vseg.values()) + list(hseg.values()): k.box(*box)
    fill = list(UPPER_FILL if variant == "oct" else LOWER_FILL); halls = list(UPPER_HALLS if variant == "oct" else LOWER_HALLS)
    used = {}
    def label(nm):
        used[nm] = used.get(nm, 0) + 1
        return nm if used[nm] == 1 else "%s %d" % (nm, used[nm])
    extra = []   # (name, at, box, [door indices])
    for r in sorted(hall, key=abs):
        x0, y0, x1, y1 = hall[r]; ds = []
        for (line, dy0, dy1) in ((yl(r), yl(r) + 8, yl(r) + 20), (yl(r + 1), yl(r + 1) - 20, yl(r + 1) - 8)):
            if (-1, r if line == yl(r) else r + 1) in hseg or (0, r if line == yl(r) else r + 1) in hseg:
                k.door(cx - 11, int(dy0), cx + 11, int(dy1), 0); ds.append(len(k.doors) - 1)
        if not ds: continue
        k.box(x0, y0, x1, y1, 16)
        nm = label(halls[(abs(r) // 2 - 1) % len(halls)]); k.room(nm, cx, (y0 + y1) // 2); extra.append((nm, r, (x0, y0, x1, y1), ds))
    order = sorted([c for c in cell if not (c[1] in hall and c[0] in (-1, 0))], key=lambda c: (abs(c[1]), abs(c[0] + 0.5), c[0]))
    for i, (kk, r) in enumerate(order):
        x0, y0, x1, y1 = cell[(kk, r)]; my = (y0 + y1) // 2; mx = (x0 + x1) // 2
        inner = (kk, r) if kk >= 0 else (kk + 1, r)          # the passage on the side toward the centre line
        toward = (kk, r) if r > 0 else (kk, r + 1)            # the cross passage on the side toward the hub
        away = (kk, r + 1) if r > 0 else (kk, r)
        if inner in vseg:
            dr = (x0 - 10, my - 11, x0 + 2, my + 11) if kk >= 0 else (x1 - 2, my - 11, x1 + 10, my + 11)
        elif toward in hseg:
            dr = (mx - 11, y0 - 10, mx + 11, y0 + 2) if r > 0 else (mx - 11, y1 - 2, mx + 11, y1 + 10)
        elif away in hseg:
            dr = (mx - 11, y1 - 2, mx + 11, y1 + 10) if r > 0 else (mx - 11, y0 - 10, mx + 11, y0 + 2)
        else: continue
        k.box(x0, y0, x1, y1, 12); k.door(int(dr[0]), int(dr[1]), int(dr[2]), int(dr[3]), 0)
        nm = label(fill[(abs(kk) + abs(r) * 3 + (0 if kk >= 0 else 1)) % len(fill)]); k.room(nm, mx, my); extra.append((nm, r, (x0, y0, x1, y1), [len(k.doors) - 1]))
    # the spokes: from the ring bow-ward and stern-ward along the centre line, and out to each side, to the first
    # passage of the grid; where the grid has nothing that way, to an end room as before
    for si, sgn in enumerate((-1, 1)):
        lines = [yl(r) for (kk, r) in hseg if kk in (-1, 0) and (yl(r) - yc) * sgn > rr + CW]
        if lines:
            y_to = min(lines, key=lambda y: abs(y - yc)); y_ring = int(yc + sgn * (rr - 2))
            k.box(cx - CW // 2, min(y_ring, y_to), cx + CW // 2, max(y_ring, y_to)); continue
        got = None
        for hr in (96, 80, 64, 48):
            for wr in (64, 52, 40):
                ya = int(yc + sgn * (Ro + 14)) if sgn > 0 else int(yc - Ro - 14 - hr)
                if ya < 2 or ya + hr >= H - 2: continue
                if D[ya - 3:ya + hr + 3, cx - wr - 3:cx + wr + 3].all(): got = (ya, hr, wr); break
            if got: break
        if not got: continue
        ya, hr, wr = got
        k.box(cx - wr, ya, cx + wr, ya + hr, 14)
        y_ring = int(yc + sgn * (rr + CW / 2 - 2)); y_room = ya if sgn > 0 else ya + hr
        k.box(cx - CW // 2, min(y_ring, y_room), cx + CW // 2, max(y_ring, y_room))
        dy0 = y_room - 12 if sgn > 0 else y_room - 2
        k.door(cx - 11, dy0, cx + 11, dy0 + 14, 0)
        nm = label(end_names[si]); k.room(nm, cx, ya + hr // 2); extra.append((nm, sgn * 99, (cx - wr, ya, cx + wr, ya + hr), [len(k.doors) - 1]))
    for sgn in (-1, 1):
        lines = [xl(kk) for (kk, r) in vseg if yl(r) <= yc <= yl(r + 1) and (xl(kk) - cx) * sgn > rr + CW]
        if lines:
            x_to = min(lines, key=lambda x: abs(x - cx)); x_ring = int(cx + sgn * (rr - 2))
            k.box(min(x_ring, x_to), yc - CW // 2, max(x_ring, x_to), yc + CW // 2)
    k.f &= D
    # keep only what can be walked to from the ring; drop the rest
    er = cv2.erode(k.f, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))
    _, lab = cv2.connectedComponents(er, connectivity=4)
    s0 = lab[int(lifts[0][1]), int(lifts[0][0])]
    live = cv2.dilate((lab == s0).astype(np.uint8), np.ones((9, 9), np.uint8)) if s0 else k.f
    k.f &= live
    alive = {r["name"] for r in k.rooms if live[int(r["at"][1]), int(r["at"][0])]}
    dead_doors = {di for (nm, _, _, ds) in extra if nm not in alive for di in ds}
    k.rooms = [r for r in k.rooms if r["name"] in alive]
    extra = [e for e in extra if e[0] in alive]
    # access: the furthest room toward the bow (upper deck) or the stern (lower deck) is red; one more yellow and
    # one more orange among the filled rooms (the wedge rooms and the round core already carry some)
    if extra:
        want_sgn = -1 if variant == "oct" else 1
        red = max(extra, key=lambda e: (e[1] * want_sgn, -abs(e[2][0] + e[2][2] - 2 * cx)))
        for di in red[3]: k.doors[di]["level"] = 3
        rest = [e for e in extra if e is not red and len(e[3]) == 1]
        rest.sort(key=lambda e: (-e[1] * want_sgn, abs(e[2][0] + e[2][2] - 2 * cx)))
        if len(rest) >= 2: k.doors[rest[0][3][0]]["level"] = 2
        if len(rest) >= 4: k.doors[rest[len(rest) // 2][3][0]]["level"] = 1
    k.doors = [q for i, q in enumerate(k.doors) if i not in dead_doors]
    return k, (int(cx - Ro), int(yc - Ro), int(cx + Ro), int(yc + Ro))

def hullplan(D, cx, cy, rr, lifts, variant):
    """v13.00 (owner, showing the Unity Capital blueprint: "look at this for example"): an extra deck laid out the way
    the blueprints are. The whole silhouette is used and the rooms take the hull's own shape:
      - a passage runs right round the deck, following the hull line a room's depth inside it
      - between that passage and the hull, a row of rooms all the way round, their outer walls the hull's curve
      - inside the passage: a big central hub at the ship's centre of mass with the two lifts in it, cross passages,
        and rows that alternate between a wide hall you walk through and a pair of rooms either side of a short spine
    Nothing here is on a blueprint: it is a PROPOSAL. variant "oct" (upper deck) or "round" (lower deck)."""
    H, W = D.shape
    dist = cv2.distanceTransform(D, cv2.DIST_L2, 5)
    Rmax = float(dist.max())
    t1 = int(min(96, max(48, 0.30 * Rmax)))          # depth of the hull-side rooms
    c_in = t1 + 8                                      # the round-ship passage: dist in (c_in, c_in + CW]
    I = (dist > c_in + CW + 8).astype(np.uint8)        # inside the passage (a wall's width in from it)
    if I.sum() < 9000: return None
    k = U.Deck(H, W); k.CX = cx
    k.f |= ((dist > c_in) & (dist <= c_in + CW)).astype(np.uint8)
    rooms = []        # {"name", "mask", "doors": [idx], "kind", "y"}
    def add_room(mask, kind, doors):
        mask = mask.astype(np.uint8)
        n, lab, st, _ = cv2.connectedComponentsWithStats(mask, connectivity=4)
        if n < 2: return None
        i = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
        if st[i, cv2.CC_STAT_AREA] < 1500: return None
        m = (lab == i).astype(np.uint8)
        dm = cv2.distanceTransform(m, cv2.DIST_L2, 5); y, x = np.unravel_index(int(np.argmax(dm)), dm.shape)
        k.f |= m
        rooms.append({"mask": m, "kind": kind, "doors": doors, "at": (int(x), int(y))}); return rooms[-1]
    def rot_door(c, wdir, ndir, w=22, l=16, level=0):
        c = np.array(c, float); wdir = np.array(wdir, float); ndir = np.array(ndir, float)
        pts = [c + a * wdir * w / 2 + b * ndir * l / 2 for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        cv2.fillPoly(k.f, [np.round(np.array(pts)).astype(np.int32)], 1)
        xs = [q[0] for q in pts]; ys = [q[1] for q in pts]
        k.doors.append({"rect": [int(min(xs)), int(min(ys)), int(max(xs)) + 1, int(max(ys)) + 1], "level": level,
                        "rot": round(float(np.degrees(np.arctan2(-wdir[1], wdir[0]))), 1), "w": w, "l": l})
        return len(k.doors) - 1
    # --- the hull-side rooms, cut along the passage's length
    mid = (dist > c_in + CW / 2).astype(np.uint8)
    cs, _ = cv2.findContours(mid, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    C = max(cs, key=len).reshape(-1, 2)
    N = len(C)
    z = np.full((H, W), 255, np.uint8); z[C[:, 1], C[:, 0]] = 0
    dC, lab = cv2.distanceTransformWithLabels(z, cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
    start_i = int(np.argmin(np.abs(C[:, 0] - cx) * 4 + C[:, 1]))        # the bow point of the passage
    idx_of = np.zeros(int(lab.max()) + 1, np.int32); idx_of[lab[C[:, 1], C[:, 0]]] = (np.arange(N) - start_i) % N
    nseg = max(4, 2 * int(round(N / 2.0 / 150)))
    half = N / (2.0 * nseg)
    seg = (((idx_of[lab] + half) % N) * nseg / N).astype(np.int32) % nseg
    O = (dist > 5) & (dist <= t1) & (dC <= t1 + 8 + CW / 2 + 6)
    gy, gx = np.gradient(cv2.GaussianBlur(dist, (0, 0), 3))
    Cs = np.roll(C, -start_i, axis=0)
    ker = np.ones((9, 9), np.uint8)
    outer = {}
    for sgi in range(nseg):
        m = (O & (seg == sgi)).astype(np.uint8)
        if m.sum() < 1500: continue
        other = (O & (seg != sgi)).astype(np.uint8)
        m &= 1 - cv2.dilate(other, ker)
        pi = int(round(sgi * N / nseg)) % N
        px, py = Cs[pi]
        nrm = -np.array([gx[py, px], gy[py, px]]); L = np.hypot(*nrm)
        if L < 1e-6: continue
        nrm /= L; tan = np.array([-nrm[1], nrm[0]])
        probe = np.array([px, py]) + nrm * (CW / 2 + 8 + 10)
        qx, qy = int(round(probe[0])), int(round(probe[1]))
        if not (0 <= qx < W and 0 <= qy < H) or not m[max(0, qy - 3):qy + 4, max(0, qx - 3):qx + 4].any(): continue
        nd = len(k.doors)
        r = add_room(m, "outer", [nd])
        if r is None: continue
        rot_door(np.array([px, py]) + nrm * (CW / 2 + 4), tan, nrm)
        r["seg"] = sgi; outer[sgi] = r
    # --- inside the passage: the hub, cross passages, and rows of halls and room pairs
    rh = int(rr + 26)
    ys_, xs_ = np.nonzero(I); ytop, ybot = int(ys_.min()), int(ys_.max())
    RH = 116
    def strip(y0, y1): 
        m = np.zeros((H, W), np.uint8); m[max(0, y0):max(0, y1)] = 1; return m
    wide = (dist > c_in).astype(np.uint8)              # cross passages run out through the wall to the round passage
    bands = []                                          # (y0, y1, index from the hub, side)
    for sgn in (-1, 1):
        y = cy + sgn * (rh + 8)
        i = 0
        while True:
            c0, c1 = (y - CW, y) if sgn < 0 else (y, y + CW)
            if (strip(c0, c1) & I).sum() < 200: break
            k.f |= strip(c0, c1) & wide
            b0, b1 = (c0 - RH, c0) if sgn < 0 else (c1, c1 + RH)
            if (strip(b0 + 8, b1 - 8) & I).sum() < 1500: break
            bands.append((b0, b1, i, sgn)); i += 1
            y = b0 if sgn < 0 else b1
    first_hall = 1 if variant == "oct" else 0
    for (b0, b1, i, sgn) in bands:
        band = strip(b0 + 8, b1 - 8) & I
        xs_b = np.nonzero(band.any(axis=0))[0]; width = int(xs_b.max() - xs_b.min()) if len(xs_b) else 0
        near_edge, far_edge = (b1, b0) if sgn < 0 else (b0, b1)
        if i % 2 == first_hall or width < 190:
            nd = len(k.doors)
            r = add_room(band, "hall", [])
            if r is None: continue
            k.door(cx - 11, b1 - 10, cx + 11, b1 + 2, 0) if (strip(b1, b1 + CW) & k.f)[:, cx].any() else None
            k.door(cx - 11, b0 - 2, cx + 11, b0 + 10, 0) if (strip(b0 - CW, b0) & k.f)[:, cx].any() else None
            r["doors"] = list(range(nd, len(k.doors))); r["y"] = sgn * (i + 1)
        else:
            sp = strip(b0, b1); sp[:, :cx - CW // 2] = 0; sp[:, cx + CW // 2:] = 0
            k.f |= sp & wide
            for side in (-1, 1):
                m = band.copy()
                if side < 0: m[:, cx - CW // 2 - 8:] = 0
                else: m[:, :cx + CW // 2 + 8] = 0
                nd = len(k.doors)
                r = add_room(m, "side", [nd])
                if r is None: continue
                my = (b0 + b1) // 2
                if side < 0: k.door(cx - CW // 2 - 10, my - 11, cx - CW // 2 + 2, my + 11, 0)
                else: k.door(cx + CW // 2 - 2, my - 11, cx + CW // 2 + 10, my + 11, 0)
                r["y"] = sgn * (i + 1); r["side"] = side
    # the hub: cleared round, then built; the lifts stand in it
    clear = np.zeros((H, W), np.uint8); cv2.circle(clear, (cx, cy), rh + 8, 1, -1)
    hubrow = strip(cy - rh, cy + rh) & I & (1 - clear)
    k.f &= 1 - (clear & strip(cy - rh - 8, cy + rh + 8))
    hub = np.zeros((H, W), np.uint8)
    if variant == "oct": cv2.fillPoly(hub, [np.round(np.array(_oct(cx, cy, rh * np.cos(np.pi / 8) + 2))).astype(np.int32)], 1)
    else: cv2.circle(hub, (cx, cy), rh, 1, -1)
    hub &= D
    for sy in (-1, 1):                                  # hub doors: bow side and stern side
        ya_, yb_ = sorted((cy + sy * (rh - 18), cy + sy * (rh + 14)))   # (reaches in past the eight-sided hub's flat side)
        k.door(cx - 14, ya_, cx + 14, yb_, 0)
    nd0 = len(k.doors)
    k.f |= hub
    rooms.append({"mask": hub, "kind": "hub", "doors": [nd0 - 2, nd0 - 1], "at": (cx, cy), "y": 0})
    for side in (-1, 1):                                # the rooms beside the hub
        m = hubrow.copy()
        if side < 0: m[:, cx:] = 0
        else: m[:, :cx] = 0
        cols = np.nonzero(m[cy - rh:cy - rh + 12].any(axis=0))[0]
        if not len(cols): continue
        xm = int(np.median(cols)); nd = len(k.doors)
        r = add_room(m, "side", [nd])
        if r is None: continue
        k.door(xm - 11, cy - rh - 10, xm + 11, cy - rh + 4, 0); r["y"] = 0; r["side"] = side
    k.f &= D
    # keep what can be walked to from the lifts
    er = cv2.erode(k.f, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))
    _, labc = cv2.connectedComponents(er, connectivity=4)
    s0 = labc[int(lifts[0][1]), int(lifts[0][0])]
    if s0 == 0: return None
    live = cv2.dilate((labc == s0).astype(np.uint8), np.ones((9, 9), np.uint8))
    k.f &= live
    keep = [r for r in rooms if live[r["at"][1], r["at"][0]]]
    kept = {id(r) for r in keep}
    dead = {di for r in rooms if id(r) not in kept for di in r["doors"]}
    # names
    up = variant == "oct"
    side_names = (UPPER_NAMES + UPPER_FILL) if up else (LOWER_NAMES + LOWER_FILL)
    hall_names = UPPER_HALLS if up else LOWER_HALLS
    n_side = n_hall = n_out = 0
    for r in sorted(keep, key=lambda r: (abs(r.get("y", 0)), r.get("y", 0), r.get("side", 0), r.get("seg", 0))):
        if r["kind"] == "hub": nm = "Operations Hub" if up else "Life Support"
        elif r["kind"] == "hall":
            nm = hall_names[n_hall % len(hall_names)] + ("" if n_hall < len(hall_names) else " %d" % (n_hall // len(hall_names) + 1)); n_hall += 1
        elif r["kind"] == "side":
            nm = side_names[n_side % len(side_names)] + ("" if n_side < len(side_names) else " %d" % (n_side // len(side_names) + 1)); n_side += 1
        else:
            n_out += 1; nm = ("Cabin %d" if up else "Storage Bay %d") % n_out
        r["name"] = nm; k.room(nm, r["at"][0], r["at"][1])
    # access: red at the bow end (upper) or the stern end (lower); orange and yellow among the single-door rooms
    one = [r for r in keep if len(r["doors"]) == 1]
    def ypos(r): return r["at"][1]
    if one:
        red = (min if up else max)(one, key=lambda r: (ypos(r) if up else ypos(r), abs(r["at"][0] - cx)) if up else (ypos(r), -abs(r["at"][0] - cx)))
        k.doors[red["doors"][0]]["level"] = 3
        rest = [r for r in one if r is not red]
        sides = sorted([r for r in rest if r["kind"] == "side"], key=lambda r: (-ypos(r) if up else ypos(r)))
        outs = sorted([r for r in rest if r["kind"] == "outer"], key=lambda r: r["seg"])
        if sides: k.doors[sides[0]["doors"][0]]["level"] = 2
        if len(outs) >= 3: k.doors[outs[len(outs) // 3]["doors"][0]]["level"] = 2
        if len(sides) >= 2: k.doors[sides[-1]["doors"][0]]["level"] = 1
        if len(outs) >= 3: k.doors[outs[(2 * len(outs)) // 3]["doors"][0]]["level"] = 1
    k.doors = [q for i, q in enumerate(k.doors) if i not in dead]
    return k, (0, 0, W, H)

def lock_main(d, floor, doors, start, at):
    shut = floor.copy()
    for dr in doors:
        x0, y0, x1, y1 = [int(round(v)) for v in dr["rect"]]; shut[max(0, y0 - PAD):y1 + PAD, max(0, x0 - PAD):x1 + PAD] = 0
    _, lab = cv2.connectedComponents(shut, connectivity=4)
    s0 = lab[int(start[1]), int(start[0])]
    notes = []; locked = {}
    for lv in (1, 2, 3):
        done = False
        for pat in LOCK_TRY[lv]:
            for name in [n for n in at if n.startswith(pat)]:
                x, y = int(at[name][0]), int(at[name][1])
                win = lab[max(0, y - 10):y + 11, max(0, x - 10):x + 11]; ids = win[win > 0]
                if not len(ids): continue
                rid = int(np.bincount(ids).argmax())
                if rid == s0: continue
                patch = cv2.dilate((lab == rid).astype(np.uint8), np.ones((9, 9), np.uint8))
                mine = [dr for dr in doors if patch[max(0, int(dr["rect"][1]) - PAD):int(dr["rect"][3]) + PAD, max(0, int(dr["rect"][0]) - PAD):int(dr["rect"][2]) + PAD].any()]
                if not mine or len(mine) > 4 or any(dr["level"] for dr in mine): continue
                for dr in mine: dr["level"] = lv
                locked[name] = lv; notes.append("%s: %d door(s) %s" % (name, len(mine), KEY_NAME[lv])); done = True
            if done: break
        if not done: notes.append("no %s room on the main deck (none could be sealed)" % KEY_NAME[lv])
    return locked, notes

def main(jpath, outdir, dbg=None):
    d = json.load(open(jpath))
    ship = os.path.basename(jpath)[:-5]
    cls = next((c for c in THREE + TWO + ("Scout", "Bomber") if ship.endswith("_" + c.lower())), "")
    H, W = d["h"] * CELL, d["w"] * CELL
    hull = hull_px(d, H, W)
    floor = main_floor(d, H, W)
    sh = d["shell"]
    doors = [{"rect": [v * CELL for v in dr["rect"]], "level": 0} for dr in sh["doors"]]
    start = [d["start"][0] * CELL, d["start"][1] * CELL]
    at = {r["name"]: (r["at"][0] * CELL, r["at"][1] * CELL) for r in d["rooms"]}
    report = {"ship": ship, "class": cls}
    want = ["upper", "lower"] if cls in THREE else (["lower"] if cls in TWO else [])
    # lifts
    plan_lifts = [[int(l[0] * CELL), int(l[1] * CELL)] for l in d.get("plan_lifts", d.get("lifts", []))]
    d["plan_lifts"] = [[l[0] / CELL, l[1] / CELL] for l in plan_lifts]
    r0 = reach_at(floor, doors, 0, start)
    plan_lifts = [l for l in plan_lifts if near(r0, l[0], l[1], 14)]
    dh = cv2.erode(hull, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (45, 45)))
    ring = None
    if want:
        ring = choose_ring(d, floor, doors, start, dh, plan_lifts)
        report["lifts"] = ring[4]; report["centre"] = [ring[0], ring[1]]
    locked, notes = lock_main(d, floor, doors, start, at)
    world = {"main": (floor, doors, start, at)}
    decks = []; used_lifts = []
    for did in want:
        cx_, cy_, rr_, lifts, _how = ring
        if not lifts: notes.append(did + " deck: no clear floor for a lift pair round the centre, not built"); continue
        got = hullplan(dh, cx_, cy_, rr_, lifts, "oct" if did == "upper" else "round")
        if got is None:
            got = radial(dh, cx_, cy_, rr_, lifts, "oct" if did == "upper" else "round", UPPER_NAMES if did == "upper" else LOWER_NAMES,
                         "Operations Hub" if did == "upper" else "Life Support", (UPPER_END, "Wardroom") if did == "upper" else ("Stores", LOWER_END))
        if got is None: notes.append(did + " deck: the hull is too narrow at its centre for the hub layout, not built"); continue
        k, rect = got
        er = cv2.erode(k.f, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))
        _, lab = cv2.connectedComponents(er, connectivity=4)
        s = lab[lifts[0][1], lifts[0][0]]
        bad = [r["name"] for r in k.rooms if s == 0 or lab[int(r["at"][1]), int(r["at"][0])] != s]
        bad += ["lift %d" % i for i, l in enumerate(lifts) if s == 0 or lab[l[1], l[0]] != s]
        dist = cv2.distanceTransform(k.f, cv2.DIST_L2, 5)
        name = "UPPER DECK" if did == "upper" else "LOWER DECK"
        mp = "%s_%s.jpg" % (ship, did)
        U.draw_map(k, dh, lifts, "%s  -  %s" % (ship.replace("_", " ").upper(), name), outdir + "/" + mp)
        world[did] = (k.f, k.doors, lifts[0], {r["name"]: tuple(r["at"]) for r in k.rooms})
        used_lifts += [l for l in lifts if l not in used_lifts]
        decks.append({"id": did, "level": 1 if did == "upper" else -1, "name": name, "proposed": True,
                      "shell": {"walls": outlines(k.f), "cover": [],
                                "doors": [dict({"rect": [round(v / CELL, 2) for v in q["rect"]], "level": q["level"], "ax": travel_axis(k.f, q["rect"])},
                                               **({"rot": q["rot"], "w": q["w"] / CELL, "l": q["l"] / CELL} if "rot" in q else {})) for q in k.doors]},
                      "rooms": [{"name": r["name"], "at": [round(r["at"][0] / CELL, 2), round(r["at"][1] / CELL, 2)],
                                 "rad": round(float(dist[int(r["at"][1]), int(r["at"][0])]) * 1.45 / CELL, 2)} for r in k.rooms],
                      "lifts": [[l[0] / CELL, l[1] / CELL] for l in lifts], "start": [lifts[0][0] / CELL, lifts[0][1] / CELL],
                      "map": mp, "check": {"cut_off": bad}})
        if bad: notes.append("%s deck: cut off: %s" % (did, ", ".join(bad)))
    for i, dr in enumerate(doors): sh["doors"][i]["level"] = dr["level"]; sh["doors"][i]["ax"] = travel_axis(floor, dr["rect"])
    # the key chain
    def opens(a):
        got = set()
        for did, (fl, drs, st, rat) in world.items():
            m = reach_at(fl, drs, a, st)
            got |= {"%s/%s" % (did, n) for n, p in rat.items() if near(m, *p)}
        return got
    op = [opens(a) for a in range(4)]
    guards = []
    def place(lv, pool):
        for key in pool:
            did, room = key.split("/", 1)
            p = world[did][3][room]
            guards.append({"deck": did, "room": room, "key": lv, "at": [round((p[0] + 12) / CELL, 2), round((p[1] + 8) / CELL, 2)]}); return True
        return False
    has = [bool(op[a] - op[a - 1]) for a in (1, 2, 3)]            # is anything behind yellow / orange / red at all
    open_rooms = [k for k in sorted(op[0]) if k.startswith("main/") and near(reach_at(floor, doors, 0, start), *at[k[5:]]) and k[5:] != "Hangar Bay"]
    pref = [k for g in GUARD_TRY for k in open_rooms if k[5:].startswith(g)] + open_rooms
    if has[0]: place(1, pref)
    if has[1]: place(2, sorted(op[1] - op[0]))
    if has[2]: place(3, sorted(op[2] - op[1]))
    total = sum(len(w[3]) for w in world.values())
    report.update({"decks": ["main"] + [x["id"] for x in decks], "rooms": total,
                   "behind": {KEY_NAME[a]: len(op[a] - op[a - 1]) for a in (1, 2, 3)},
                   "guards": ["%s key: %s/%s" % (KEY_NAME[g["key"]], g["deck"], g["room"]) for g in guards],
                   "all_reachable_with_red": len(op[3]) == total, "notes": notes})
    d["lifts"] = [[l[0] / CELL, l[1] / CELL] for l in used_lifts]
    d["decks"] = decks; d["key_guards"] = guards
    d["gameplay_note"] = "PROPOSED: extra decks, added lifts, door colours and key guards are a proposal, not on the blueprint"
    json.dump(d, open(jpath, "w"), separators=(",", ":"))
    print(json.dumps(report))
    return report

if __name__ == "__main__":
    main(*sys.argv[1:4])
