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
        sc = min(dist[y, x], dist[y, mx]) - 0.03 * abs(y - ymid) - 0.02 * abs((cx - x) - 60)
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
    lifts_for = {}
    if want:
        if len(plan_lifts) >= 4:
            plan_lifts.sort(key=lambda l: l[1])
            lifts_for = {"upper": sorted(plan_lifts[:2]), "lower": sorted(plan_lifts[-2:])}; report["lifts"] = "the plan's four"
        elif len(plan_lifts) >= 2:
            pair = next(([a, b] for a in plan_lifts for b in plan_lifts if a[0] < b[0] and abs(a[1] - b[1]) <= 10), plan_lifts[:1])
            lifts_for = {"upper": sorted(pair), "lower": sorted(pair)}; report["lifts"] = "the plan's own (%d used)" % len(pair)
        elif len(plan_lifts) == 1:
            lifts_for = {"upper": plan_lifts, "lower": plan_lifts}; report["lifts"] = "the plan's one"
        else:
            got, how = pick_lifts(d, floor, doors, start, hull)
            lifts_for = {"upper": got, "lower": got}; report["lifts"] = "added (%s): none usable on the plan" % how
    locked, notes = lock_main(d, floor, doors, start, at)
    world = {"main": (floor, doors, start, at)}
    decks = []; used_lifts = []
    dh = cv2.erode(hull, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (45, 45)))
    for did in want:
        lifts = lifts_for.get(did, [])
        if not lifts: notes.append(did + " deck: no lift position found, not built"); continue
        bias = -1 if did == "upper" else 1
        got = layout(dh, lifts, bias, UPPER_NAMES if did == "upper" else LOWER_NAMES, UPPER_END if did == "upper" else LOWER_END)
        if got is None: notes.append(did + " deck: the hull is too narrow round the lifts, not built"); continue
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
                                "doors": [{"rect": [round(v / CELL, 2) for v in q["rect"]], "level": q["level"], "ax": travel_axis(k.f, q["rect"])} for q in k.doors]},
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
