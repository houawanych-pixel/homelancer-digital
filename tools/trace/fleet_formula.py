#!/usr/bin/env python3
"""Owner, Nov 13 2026 - the boarding formula for every fleet ship (each ship laid out differently, the same formula):

  C   the big room near the middle of the ship: the objective (blow the generator, take the captain, free the
      hostage - all three here), behind RED (level 3) doors
  A   a red (mech) room on one side behind YELLOW (level 1) doors: the ORANGE card is in it
      ... and the YELLOW card that opens it is in a blue (pilot) room on the OTHER side (open: go on foot to find it)
  3   the RED card: in a far blue (pilot) room ("all the way at the top"), behind ORANGE (level 2) doors
  B   the way out: a red room far from where you came in, behind ORANGE doors. When the objective is done the clock
      starts and the way you came in is blocked: find this other way out.
  You come aboard in the mech at the ENTRY (a red room at the far end from the way out).

Every choice is checked on the deck (a pilot on foot, doors open only with the cards you hold): each card is reached
with the cards before it and not without, the objective needs the red card, the way out the orange one, and with
all three cards every room is reachable. Among the valid layouts one is picked by the ship's name, so every ship
differs. Writes eng/gameplay.json (the old one kept as eng/gameplay_v1.json once) and eng/formula.jpg.
usage: python3 -I tools/trace/fleet_formula.py <id> [<id> ...]"""
import hashlib, itertools, json, os, shutil, sys
import cv2, numpy as np
from shapely.geometry import shape, Point
from shapely.ops import unary_union
TR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TR)
import planlib
from fleet_ways import kind as room_kind

KEY_COL = {0: (80, 230, 80), 1: (0, 230, 255), 2: (0, 140, 255), 3: (40, 40, 235)}

def formula(sid):
    here = os.path.join(TR, "fleet_" + sid, "eng")
    P = json.load(open(os.path.join(here, "plan.json")))
    gp = os.path.join(here, "gameplay.json"); g1 = os.path.join(here, "gameplay_v1.json")
    if not os.path.exists(g1): shutil.copy(gp, g1)
    G0 = json.load(open(g1))
    src = os.path.join(TR, "fleet_" + sid, "source.jpg")
    H, W = cv2.imread(src).shape[:2]
    R = {k: shape(v) for k, v in P["rooms"].items()}
    K = {k: room_kind(k) for k in R}
    T = float(P["thickness"]); AX = float(P["mirror_x"])
    doors = [tuple(d) for d in P["doors"]]
    dbox = lambda d: planlib.door_box(d[0], d[1], d[2], T * 2.6)
    halls = unary_union([shape(h) for h in P["halls"]])
    floor = unary_union(list(R.values()) + [halls] + [dbox(d) for d in doors]).buffer(0.5).buffer(-0.5)
    rings = [g.exterior.buffer(T / 2, join_style=2) for g in R.values()]
    for p in getattr(halls, "geoms", [halls]):
        rings.append(p.exterior.buffer(T / 2, join_style=2)); rings += [r.buffer(T / 2, join_style=2) for r in p.interiors]
    walls = unary_union(rings).difference(unary_union([dbox(d) for d in doors]))
    base = (planlib.raster(floor, (H, W)) > 0) & ~(planlib.raster(walls, (H, W)) > 0)
    dmask = {d: planlib.raster(dbox(d), (H, W)) > 0 for d in doors}
    room_doors = {k: [d for d in doors if R[k].distance(Point(d[0], d[1])) < T * 1.6] for k in R}
    pt = {k: (R[k].representative_point() if not R[k].centroid.within(R[k]) else R[k].centroid) for k in R}
    ipt = {k: (int(pt[k].x), int(pt[k].y)) for k in R}

    # (half resolution: the walls are 2 px, the doors 8 px across; 4x faster)
    hs = lambda m: cv2.resize(m.astype(np.uint8), (W // 2, H // 2), interpolation=cv2.INTER_NEAREST).astype(bool)
    base = hs(base) & ~hs(planlib.raster(walls, (H, W)) > 0)
    dmask = {d: hs(m) for d, m in dmask.items()}
    ipt = {k: (v[0] // 2, v[1] // 2) for k, v in ipt.items()}
    def reach(locks, level, start):
        m = base.copy()
        for d, kk in locks.items():
            if kk > level: m[dmask[d]] = False
        n, lab = cv2.connectedComponents(m.astype(np.uint8), connectivity=4)
        s = lab[start[1], start[0]]
        return lambda k: bool(lab[ipt[k][1], ipt[k][0]] == s and s != 0)

    mech = [k for k in R if K[k] == "mech" and room_doors[k]]
    pilot = [k for k in R if K[k] == "pilot" and room_doors[k]]
    side = lambda k: -1 if pt[k].x < AX - 8 else (1 if pt[k].x > AX + 8 else 0)
    cx, cy = np.mean([pt[k].x for k in R]), np.mean([pt[k].y for k in R])
    span = max(1.0, max(pt[k].distance(Point(cx, cy)) for k in R))
    dist = lambda a, b: pt[a].distance(pt[b])
    seed = int(hashlib.md5(sid.encode()).hexdigest(), 16)
    rng = np.random.default_rng(seed % (2 ** 32))
    tries = 0
    for relax in (0, 1, 2):   # (1: a small ship: any room may serve when there aren't enough red rooms; 2: the way out open)
        big = mech if not relax else [k for k in R if K[k] != "lift" and room_doors[k]]
        # C: the big room near the middle (area, weighted toward the centre)
        Cs = sorted(big, key=lambda k: -R[k].area * (1.0 - 0.6 * pt[k].distance(Point(cx, cy)) / span))[:3]
        for C in Cs:
            others = [k for k in big if k != C]
            # entry / way out: two rooms far apart, both away from C
            pairs = sorted(itertools.permutations(others, 2), key=lambda ab: -(dist(*ab) + 0.5 * (dist(ab[0], C) + dist(ab[1], C))))[:12 if relax == 0 else 60]
            head = pairs[:6]; rng.shuffle(head); pairs = head + pairs[6:]
            for entry, exit_ in pairs:
                sA = -side(exit_) if side(exit_) != 0 else int(rng.choice([-1, 1]))   # (A across the ship from the way out)
                lat = lambda k: abs(pt[k].x - AX)
                gateAs = [k for k in others if k not in (entry, exit_) and side(k) == sA]
                gateAs += [k for k in others if k not in (entry, exit_) and k not in gateAs]
                pil = pilot if not relax else [k for k in R if K[k] != "lift" and room_doors[k]]
                card1s = [k for k in pil if side(k) == -sA] + [k for k in pil if side(k) != -sA]
                card3s = sorted(pil, key=lambda k: -dist(k, entry))[:6]
                gateAs = sorted(gateAs[:6], key=lambda k: (side(k) != sA, -lat(k)))
                card1s = sorted(card1s[:10], key=lambda k: (side(k) != -sA, -(dist(k, entry) + 1.5 * lat(k))))
                for gA, c1, c3 in itertools.product(gateAs[:4], card1s[:5], card3s):
                    tries += 1
                    if len({gA, c1, c3, C, entry, exit_}) < 6: continue
                    locks = {}
                    for k, lv in ((C, 3), (c3, 2), (exit_, 2 if relax < 2 else 0), (gA, 1)):
                        for d in room_doors[k]: locks[d] = max(locks.get(d, 0), lv)
                    if any(d in locks for d in room_doors[entry]): continue
                    st = ipt[entry]
                    r0, r1, r2, r3 = (reach(locks, l, st) for l in range(4))
                    ok = (r0(entry) and r0(c1) and not r0(gA) and r1(gA) and not r1(c3) and r2(c3) and not r2(C) and r3(C)
                          and (relax == 2 or (not r1(exit_) and r2(exit_))) and all(r3(k) for k in R))
                    if not ok: continue
                    return write(sid, here, G0, P, R, K, pt, locks, entry, exit_, C, gA, c1, c3, src, H, W, tries)
    print(sid, "NO VALID LAYOUT after", tries, "tries")
    return None

def write(sid, here, G0, P, R, K, pt, locks, entry, exit_, C, gA, c1, c3, src, H, W, tries):
    at = lambda k: [int(pt[k].x), int(pt[k].y)]
    G = {k: v for k, v in G0.items() if k not in ("targets", "guards", "locks", "entry", "exit", "decks", "elevators", "retired_decks")}
    G["formula"] = {"C": C, "A_gate": gA, "card_yellow": c1, "card_red": c3, "entry": entry, "way_out": exit_,
                    "note": "owner's boarding formula (tools/trace/fleet_formula.py)"}
    G["entry"] = {"room": entry, "at": at(entry)}
    G["exit"] = {"room": exit_, "at": at(exit_)}
    G["locks"] = [{"door": [d[0], d[1]], "key": lv, "why": ""} for d, lv in locks.items()]
    for l in G["locks"]:
        d = (l["door"][0], l["door"][1])
        l["why"] = {3: "the objective (%s)" % C, 2: "the red card / the way out", 1: "the orange card's room (%s)" % gA}[l["key"]]
    G["guards"] = [{"key": 1, "room": c1, "at": at(c1)}, {"key": 2, "room": gA, "at": at(gA)}, {"key": 3, "room": c3, "at": at(c3)}]
    G["targets"] = {kd: {"room": C, "at": at(C), "key": 3} for kd in ("sabotage", "capture", "rescue")}
    rg = dict(G0.get("room_guards", {}))
    for k in (C, gA, c3): rg[k] = max(2, int(rg.get(k, 0)))
    G["room_guards"] = rg
    json.dump(G, open(os.path.join(here, "gameplay.json"), "w"), indent=1)
    # the picture (for the owner): the deck, the letters, the locked doors
    im = cv2.imread(src) // 2
    for k, g in R.items():
        col = {"mech": (40, 40, 200), "pilot": (200, 110, 30), "lift": (0, 200, 230)}[K[k]]
        cv2.fillPoly(im, [np.array(g.exterior.coords, np.int32)], col)
    for l in G["locks"]:
        x, y = l["door"]; cv2.circle(im, (int(x), int(y)), 9, KEY_COL[l["key"]], -1)
    for lab, k in (("ENTRY", entry), ("C  OBJECTIVE", C), ("A  (yellow doors) orange card", gA), ("yellow card", c1),
                   ("red card (orange doors)", c3), ("B  WAY OUT (orange doors)", exit_)):
        x, y = at(k)
        cv2.putText(im, lab, (x - 60, y), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 4, cv2.LINE_AA)
        cv2.putText(im, lab, (x - 60, y), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)
    cv2.putText(im, sid.upper() + "  -  BOARDING FORMULA", (16, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2, cv2.LINE_AA)
    cv2.imwrite(os.path.join(here, "formula.jpg"), im, [cv2.IMWRITE_JPEG_QUALITY, 85])
    print(sid, "OK", "C=%s A=%s yellow=%s red=%s entry=%s out=%s (%d tries)" % (C, gA, c1, c3, entry, exit_, tries))
    return G

if __name__ == "__main__":
    for s in sys.argv[1:]: formula(s)
