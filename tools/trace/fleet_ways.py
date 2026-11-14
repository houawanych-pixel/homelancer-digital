#!/usr/bin/env python3
"""Owner, Nov 13 2026: "convert ours into that platform: mech ways a colour with transparency, pilot ways a colour with
transparency (red for mechs, blue for people), yellow the elevators; keys for which doors are locked and which are not;
three key levels, the mech keys the same as the pilot keys."

For one fleet ship (its main deck plan + gameplay):
  - every room is MECH (hangars, holds, bays, engineering, reactor, engines, magazines ...), PILOT (bridge, sensors,
    quarters, medbay, armory, galley, offices ...) or LIFT; the boarding bay counts as mech (you come in by mech)
  - the MECH WAYS are the halls the mech needs: the shortest hall routes from the boarding bay to every mech room;
    every other hall is a PILOT WAY
  - every door is a MECH door (it joins mech space only) or a PILOT door (it opens on a pilot room or a pilot way),
    with its key: 0 open, 1 yellow, 2 orange, 3 red card (the gameplay locks; one card set for mech and pilot doors)
writes eng/ways.json and eng/ways_on_map.jpg.   usage: python3 -I tools/trace/fleet_ways.py <id> [<id> ...]"""
import json, os, sys
from collections import deque
import cv2, numpy as np
from shapely.geometry import shape, Point, box
from shapely.ops import unary_union
TR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TR)
import planlib

MECH_WORDS = ["hangar", "launch bay", "cargo hold", "cargo transfer", "vehicle", "loader", "craft bay", "troop bay",
              "deploy", "engineering", "reactor", "engine room", "maint", "weapon bay", "weapons bay", "magazine",
              "munitions", "power core", "machine room", "workshop", "supply depot", "engine access", "dropship"]
RED, BLUE, YELLOW = (40, 40, 235), (235, 120, 30), (0, 215, 255)          # BGR
KEY_COL = {0: (80, 230, 80), 1: (0, 230, 255), 2: (0, 140, 255), 3: (40, 40, 235)}
KEY_NAME = {0: "OPEN", 1: "YELLOW", 2: "ORANGE", 3: "RED"}

def kind(name):
    n = name.lower()
    if "lift" in n: return "lift"
    return "mech" if any(w in n for w in MECH_WORDS) else "pilot"

def ways(sid):
    here = os.path.join(TR, "fleet_" + sid, "eng")
    P = json.load(open(os.path.join(here, "plan.json"))); G = json.load(open(os.path.join(here, "gameplay.json")))
    src = os.path.join(TR, "fleet_" + sid, "source.jpg")
    im = cv2.imread(src); H, W = im.shape[:2]
    R = {k: shape(v) for k, v in P["rooms"].items()}
    K = {k: kind(k) for k in R}
    entry = G["entry"]["room"]
    halls = unary_union([shape(h) for h in P["halls"]])
    T = float(P["thickness"])
    doors = [tuple(d) for d in P["doors"]]
    dbox = lambda d: planlib.door_box(d[0], d[1], d[2], T * 2.6)
    # the walkable grid: floor minus walls (doors cut open)
    floor = unary_union(list(R.values()) + [halls] + [dbox(d) for d in doors]).buffer(0.5).buffer(-0.5)
    rings = [g.exterior.buffer(T / 2, join_style=2) for g in R.values()]
    for p in getattr(halls, "geoms", [halls]):
        rings.append(p.exterior.buffer(T / 2, join_style=2)); rings += [r.buffer(T / 2, join_style=2) for r in p.interiors]
    walls = unary_union(rings).difference(unary_union([dbox(d) for d in doors]))
    walk = planlib.raster(floor, (H, W)).astype(bool) & ~planlib.raster(walls, (H, W)).astype(bool)
    hallm = planlib.raster(halls, (H, W)).astype(bool)
    roomm = {k: planlib.raster(g, (H, W)).astype(bool) for k, g in R.items()}
    mechm = np.zeros((H, W), bool)
    for k, m in roomm.items():
        if K[k] in ("mech", "lift"): mechm |= m
    # the mech may move through halls, mech rooms and the doorways between them
    s = 4   # (a 4 px grid is fine for routes)
    anyroom = np.logical_or.reduce([m for m in roomm.values()])
    def grid():
        al = walk & (hallm | mechm | ~anyroom)
        return cv2.resize(al.astype(np.uint8), (W // s, H // s), interpolation=cv2.INTER_NEAREST).astype(bool)
    A = grid()
    # v13.132 (owner: "a red room by itself with no red way to it: how does the mech get there?"): a red room the mech
    # can't drive to from the main red network (only through pilot rooms) is a PILOT room
    n_, lab_ = cv2.connectedComponents(A.astype(np.uint8), connectivity=4)
    area = {}
    for k in R:
        if K[k] != "mech": continue
        p_ = R[k].representative_point(); l_ = lab_[int(p_.y) // s, int(p_.x) // s]
        area[l_] = area.get(l_, 0.0) + R[k].area
    main = max(area, key=area.get) if area else 0
    cut = []
    for k in R:
        if K[k] != "mech": continue
        p_ = R[k].representative_point()
        if lab_[int(p_.y) // s, int(p_.x) // s] != main or main == 0: K[k] = "pilot"; cut.append(k)
    if cut:
        mechm = np.zeros((H, W), bool)
        for k, m in roomm.items():
            if K[k] in ("mech", "lift"): mechm |= m
        A = grid()
    K_base = dict(K)
    if entry in K and K[entry] != "mech":
        K[entry] = "mech"; mechm |= roomm[entry]; A = grid()
    st = R[entry].representative_point(); start = (int(st.y) // s, int(st.x) // s)
    par = {start: None}; q = deque([start])
    while q:
        c = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (c[0] + dy, c[1] + dx)
            if 0 <= n[0] < A.shape[0] and 0 <= n[1] < A.shape[1] and A[n] and n not in par:
                par[n] = c; q.append(n)
    path = np.zeros((H, W), np.uint8); unreached = []
    for k in R:
        if K[k] not in ("mech", "lift") or k == entry: continue
        pt = R[k].representative_point(); t = (int(pt.y) // s, int(pt.x) // s)
        if t not in par: unreached.append(k); continue
        while t is not None:
            cv2.circle(path, (t[1] * s, t[0] * s), 2, 1, -1); t = par[t]
    # a mech way is the whole width of a hall the route runs down
    near = cv2.dilate(path, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (31, 31))).astype(bool)
    n, lab = cv2.connectedComponents((hallm & walk).astype(np.uint8), connectivity=4)
    mech_hall = hallm & near
    pilot_hall = hallm & ~mech_hall
    # doors: what they join
    lock = {(round(l["door"][0]), round(l["door"][1])): int(l["key"]) for l in G["locks"]}
    D = []
    for d in doors:
        pt = Point(d[0], d[1])
        touch = [k for k, g in R.items() if g.distance(pt) < T * 1.6]
        x, y = int(round(d[0])), int(round(d[1]))
        on_pilot_hall = pilot_hall[max(0, y - 8):y + 9, max(0, x - 8):x + 9].any() and not mech_hall[max(0, y - 8):y + 9, max(0, x - 8):x + 9].any()
        typ = "pilot" if any(K[k] == "pilot" for k in touch) or on_pilot_hall else "mech"
        D.append({"at": [d[0], d[1]], "o": d[2], "rooms": touch, "type": typ, "key": lock.get((round(d[0]), round(d[1])), 0)})
    out = {"ship": sid, "rooms": K, "rooms_base": K_base, "cut_off_red": cut, "doors": D, "entry": entry, "mech_rooms_unreached": unreached,
           "counts": {"mech_rooms": sum(v == "mech" for v in K.values()), "pilot_rooms": sum(v == "pilot" for v in K.values()),
                      "mech_doors": sum(d["type"] == "mech" for d in D), "pilot_doors": sum(d["type"] == "pilot" for d in D),
                      "locked": {KEY_NAME[k]: sum(d["key"] == k for d in D) for k in KEY_NAME}}}
    json.dump(out, open(os.path.join(here, "ways.json"), "w"), indent=1)
    cv2.imwrite(os.path.join(here, "ways_mech_halls.png"), mech_hall.astype(np.uint8) * 255)   # (to_deck_json: which halls the mech may use)
    # the picture: the HoloDeck / token art, red mech ways, blue pilot ways, yellow lifts, doors by key
    pic = im.copy()
    over = pic.copy()
    mech_area = mech_hall.copy(); pilot_area = pilot_hall.copy(); lift_area = np.zeros((H, W), bool)
    for k, m in roomm.items():
        {"mech": mech_area, "pilot": pilot_area, "lift": lift_area}[K[k]][m] = True
    over[mech_area] = RED; over[pilot_area] = BLUE; over[lift_area] = YELLOW
    pic = cv2.addWeighted(over, 0.5, pic, 0.5, 0)   # (the art's own room names show through)
    pic[planlib.raster(walls, (H, W)) > 0] = (255, 255, 255)
    for d in D:
        x, y = d["at"]; o = d["o"]; dw = float(P["door"]) / 2 + 3
        r = (int(x - dw), int(y - 6), int(x + dw), int(y + 6)) if o == "h" else (int(x - 6), int(y - dw), int(x + 6), int(y + dw))
        cv2.rectangle(pic, r[:2], r[2:], KEY_COL[d["key"]], -1)
        cv2.rectangle(pic, r[:2], r[2:], RED if d["type"] == "mech" else BLUE, 2)
    # key
    ky = H - 190
    rows = [(RED, "MECH WAY / ROOM (red)"), (BLUE, "PILOT WAY / ROOM (blue)"), (YELLOW, "ELEVATOR (yellow)"),
            (KEY_COL[0], "door OPEN"), (KEY_COL[1], "door YELLOW card"), (KEY_COL[2], "door ORANGE card"), (KEY_COL[3], "door RED card")]
    for i, (col, txt) in enumerate(rows):
        cv2.rectangle(pic, (16, ky + i * 24), (34, ky + i * 24 + 16), col, -1)
        cv2.putText(pic, txt, (42, ky + i * 24 + 14), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (240, 240, 240), 1, cv2.LINE_AA)
    cv2.putText(pic, "door outline: red = mech door (4-5 mechs wide), blue = pilot door (3-4 people wide)", (16, ky - 12),
                cv2.FONT_HERSHEY_SIMPLEX, 0.45, (240, 240, 240), 1, cv2.LINE_AA)
    cv2.putText(pic, "%s  -  MECH / PILOT WAYS (PROPOSED)" % sid.replace("_", " ").upper(), (16, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2, cv2.LINE_AA)
    cv2.imwrite(os.path.join(here, "ways_on_map.jpg"), pic, [cv2.IMWRITE_JPEG_QUALITY, 88])
    fm = G.get("formula")
    if fm:   # v13.132: the boarding formula's places on the red / blue ways (the picture for the owner)
        f2 = pic.copy()
        for lab, k in (("ENTRY", fm["entry"]), ("C  OBJECTIVE (red doors)", fm["C"]), ("A  yellow doors: ORANGE card", fm["A_gate"]),
                       ("YELLOW card", fm["card_yellow"]), ("RED card (orange doors)", fm["card_red"]), ("B  WAY OUT (orange doors)", fm["way_out"])):
            if k not in R: continue
            c = R[k].representative_point(); x, y = int(c.x) - 70, int(c.y)
            cv2.putText(f2, lab, (x, y), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 4, cv2.LINE_AA)
            cv2.putText(f2, lab, (x, y), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)
        cv2.putText(f2, "%s  -  BOARDING FORMULA" % sid.replace("_", " ").upper(), (16, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2, cv2.LINE_AA)
        cv2.imwrite(os.path.join(here, "formula.jpg"), f2, [cv2.IMWRITE_JPEG_QUALITY, 85])
    print(sid, out["counts"], "mech rooms the mech cannot reach:", unreached)
    return out

if __name__ == "__main__":
    for sid in sys.argv[1:]: ways(sid)
