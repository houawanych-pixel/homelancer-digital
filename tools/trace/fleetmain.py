#!/usr/bin/env python3
"""Main decks for ships with no HoloDeck sheet (Solarion, Savagers), composed inside the token silhouette
(token_source.py -> source.jpg + source_mask.png) from the class rules in docs/HANDOFF_SHIP_INTERIORS.md section 7.

The deck is a chain of bands from nose to tail along one spine corridor on the axis, the way the traced ships are
built (Fury / Tianjin / Covenant Destroyer): centre rooms (bridge, CIC, reactor ...) sit on the axis, side bands put
a pair of rooms either side of the spine, one band holds the lift pair, one big room is the bay you board in. Every
size is fitted to the hull at that height (1.6 m of structure kept inside the hull). Then the boarding game:
key cards fore and aft of the bay, the key guards, the three targets, the lifts.   PROPOSED: all of it."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from planlib import Ship, run, circle, mirror
import decklib
from shapely.geometry import LineString, Polygon, box

AX = 512.0
SW = 10                      # spine half width (2 m spine)

# class recipes: (kind, names, height m [, flag]); kinds: C centre room, O round centre room, S side pair, L lift pair,
# B the bay you board in. A "*" marks the rescue room. flag "opt" = dropped first when the hull is short.
RECIPES = {
    "capital": [("C", "Bridge", 8), ("S", ("Sensors", "Comms"), 7), ("O", "CIC", 11), ("S", ("Captain's Quarters", "Officers' Quarters"), 8),
                ("L", "Lift", 2.8), ("S", ("Crew Quarters A", "Crew Quarters B"), 8), ("S", ("Barracks A", "Barracks B"), 8, "opt"),
                ("S", ("Brig*", "Medbay"), 8), ("B", "Hangar", 18), ("S", ("Cargo Hold A", "Cargo Hold B"), 10),
                ("C", "Engineering", 8), ("O", "Reactor Core", 10), ("C", "Engine Room", 7)],
    "cruiser": [("C", "Bridge", 7), ("S", ("Sensors", "Gunnery"), 7), ("O", "CIC", 9), ("S", ("Captain's Quarters", "Officers' Quarters"), 7),
                ("L", "Lift", 2.8), ("S", ("Crew Quarters", "Galley & Mess"), 8), ("S", ("Brig*", "Medbay"), 7), ("B", "Hangar", 14),
                ("S", ("Cargo Hold A", "Cargo Hold B"), 9), ("C", "Engineering", 8), ("O", "Reactor Core", 9), ("C", "Engine Room", 6)],
    "destroyer": [("C", "Bridge", 7), ("S", ("Sensors", "Weapons Locker"), 7), ("O", "CIC", 8), ("S", ("Captain's Quarters", "Armory"), 7),
                  ("L", "Lift", 2.8), ("S", ("Crew Quarters", "Galley & Mess"), 8), ("S", ("Weapons Bay A", "Weapons Bay B"), 9, "opt"),
                  ("B", "Launch Bay", 12), ("S", ("Missile Magazine", "Brig*"), 8), ("C", "Engineering", 8), ("O", "Reactor Core", 9),
                  ("C", "Engine Room", 6)],
    "resupply": [("C", "Bridge", 7), ("S", ("Sensors", "Comms"), 6), ("O", "Ops Center", 8), ("S", ("Crew Quarters", "Galley"), 8), ("L", "Lift", 2.8),
                 ("S", ("Brig*", "Medbay"), 7), ("B", "Loading Bay", 14), ("S", ("Cargo Hold A", "Cargo Hold B"), 14),
                 ("S", ("Fuel Store", "Cargo Hold C"), 10, "opt"), ("C", "Engineering", 8), ("O", "Reactor Core", 9), ("C", "Engine Room", 6)],
    "trooptransport": [("C", "Bridge", 7), ("S", ("Sensors", "Briefing Room"), 7), ("O", "Command", 8), ("L", "Lift", 2.8),
                       ("S", ("Barracks A", "Barracks B"), 8), ("S", ("Barracks C", "Barracks D"), 8, "opt"), ("S", ("Armory", "Medbay*"), 8),
                       ("B", "Drop Bay", 16), ("S", ("Lockers & Gear", "Ready Room"), 7, "opt"), ("C", "Engineering", 8),
                       ("O", "Reactor Core", 9), ("C", "Engine Room", 6)],
    "frigate": [("C", "Bridge", 7), ("S", ("Sensors", "Comms"), 6), ("O", "CIC", 8), ("L", "Lift", 2.8),
                ("S", ("Crew Quarters", "Galley & Mess"), 8), ("S", ("Medbay*", "Armory"), 7), ("B", "Airlock Bay", 12),
                ("S", ("Gun Deck A", "Gun Deck B"), 8), ("C", "Engineering", 8), ("O", "Reactor Core", 8), ("C", "Engine Room", 6)],
    "escort": [("C", "Bridge", 6), ("S", ("Sensors", "Gun Room"), 7), ("S", ("Crew Bunks", "Galley / Med*"), 8), ("L", "Lift", 2.8),
               ("B", "Airlock Bay", 10), ("S", ("Armory", "Stores"), 7, "opt"), ("C", "Engineering", 8), ("O", "Reactor Core", 8),
               ("C", "Engine Room", 6)],
    "scout": [("C", "Cockpit", 6), ("O", "Sensors Suite", 8), ("S", ("Bunk", "Med / Galley*"), 7),   # (one deck: no lift)
              ("B", "Airlock", 8), ("C", "Engineering", 7), ("C", "Engine Room", 6)],
}
CARDS = {"capital": 3, "cruiser": 3, "destroyer": 3, "resupply": 3, "trooptransport": 3, "frigate": 2, "escort": 1, "scout": 1}
CAP = {"C": 160, "O": 120, "B": 240, "S": 130}
WIDE = {"resupply": 1.7, "trooptransport": 1.7, "cruiser": 1.4, "capital": 1.4}   # (v13.120: floor grows with the class)
WIDE_SHIP = {"solarion_cruiser": 2.0, "savagers_resupply": 1.1, "savagers_trooptransport": 2.4}   # (per hull, to keep resupply < troop transport)


def compose(sid, here, cls, src=None):
    """returns (Ship, gameplay dict); writes nothing"""
    src = src or os.path.join(here, "..", "source.jpg")
    H = decklib.hull(src, AX).buffer(-16)
    def seg(y):
        s = H.intersection(LineString([(0, y), (2000, y)]))
        for g in getattr(s, "geoms", [s]):
            if not g.is_empty and g.bounds[0] <= AX <= g.bounds[2]: return g.bounds[0], g.bounds[2]
        return AX, AX
    def hw(a, b):
        return min(min(AX - seg(y)[0], seg(y)[1] - AX) for y in range(int(a), int(b) + 1, 2))
    y0, y1 = int(H.bounds[1]), int(H.bounds[3])
    top = next(y for y in range(y0, y1, 2) if hw(y, y + 40) >= 34)
    bot = next(y for y in range(y1, y0, -2) if hw(y - 40, y) >= 30)
    bands = [list(b) for b in RECIPES[cls]]
    def need(bs): return sum(b[2] * 10 for b in bs)
    while need(bands) > (bot - top) * 1.18 and any(len(b) > 3 for b in bands):
        bands.remove(next(b for b in bands if len(b) > 3))
    k = min(1.15, (bot - top) / need(bands))
    R, HALLS, DOORS, info = {}, [], [], []
    y = top
    for i, b in enumerate(bands):
        kind, nm, h = b[0], b[1], b[2]
        hh = 28 if kind == "L" else max(30, round(h * 10 * k / 2) * 2)
        a, z = y, y + hh
        w = hw(a, z)
        e = {"kind": kind, "a": a, "b": z, "rooms": []}
        if kind in ("C", "B"):
            half = min(w, CAP[kind] * WIDE_SHIP.get(sid, WIDE.get(cls, 1.0)) / 2)
            half = max(half, 18)
            if i == 0:          # the bridge: a chamfered nose
                c = min(half, hh / 2) * 0.45
                g = Polygon([(AX - half + c, a), (AX + half - c, a), (AX + half, a + c), (AX + half, z), (AX - half, z), (AX - half, a + c)])
            elif i == len(bands) - 1:
                c = min(half, hh / 2) * 0.35
                g = Polygon([(AX - half, a), (AX + half, a), (AX + half, z - c), (AX + half - c, z), (AX - half + c, z), (AX - half, z - c)])
            else:
                g = box(AX - half, a, AX + half, z)
            R[nm] = g; e["rooms"].append(nm); e["edge"] = (a, z)
        elif kind == "O":
            r = min(w, CAP["O"] / 2, hh / 2)
            cy = (a + z) / 2
            R[nm] = circle(AX, cy, r); e["rooms"].append(nm); e["edge"] = (round(cy - r), round(cy + r))
            if cy - r > a + 1: HALLS.append(box(AX - 8, a, AX + 8, cy - r + 3))
            if cy + r < z - 1: HALLS.append(box(AX - 8, cy + r - 3, AX + 8, z))
        elif kind in ("S", "L"):
            HALLS.append(box(AX - SW, a, AX + SW, z))
            if kind == "L":
                R["Lift (port)"] = box(AX - SW - 28, a, AX - SW, z); R["Lift (starboard)"] = box(AX + SW, a, AX + SW + 28, z)
                DOORS += [(AX - SW, (a + z) // 2, "v"), (AX + SW, (a + z) // 2, "v")]
                e["rooms"] += ["Lift (port)", "Lift (starboard)"]
            else:
                wide = min(w - SW, CAP["S"] * WIDE_SHIP.get(sid, WIDE.get(cls, 1.0)))
                if wide >= 32:
                    for side, n in ((-1, nm[0]), (1, nm[1])):
                        n2 = n.rstrip("*")
                        g = box(AX - SW - wide, a, AX - SW, z) if side < 0 else box(AX + SW, a, AX + SW + wide, z)
                        R[n2] = g; e["rooms"].append(n2)
                        if n.endswith("*"): e["rescue"] = n2
                        DOORS.append((AX + side * SW, (a + z) // 2, "v"))
        info.append(e)
        y = z
    # doors between bands, on the axis, wherever a room's wall stands between them
    for p, q in zip(info, info[1:]):
        yb = p["b"]
        if p["kind"] in ("C", "B") or q["kind"] in ("C", "B"):
            DOORS.append((AX, yb, "h"))
    for e in info:
        if e["kind"] == "O":
            ia = info.index(e)
            if ia > 0: DOORS.append((AX, e["edge"][0], "h"))
            if ia < len(info) - 1: DOORS.append((AX, e["edge"][1], "h"))
    DOORS = [(int(round(x)), int(round(y)), o) for x, y, o in DOORS]
    DOORS = list(dict.fromkeys(DOORS))
    bay = next(e for e in info if e["kind"] == "B")
    entry = (int(AX), int((bay["a"] + bay["b"]) / 2))
    S = Ship(sid, here, src, AX, R, HALLS, DOORS, start=entry, proposed=[d[:2] for d in DOORS])
    S.bands = info
    return S, gameplay(cls, info, R, DOORS, bay, entry)


def gameplay(cls, info, R, DOORS, bay, entry):
    K = CARDS[cls]
    def pt(n):
        c = R[n].representative_point(); return [int(c.x), int(c.y)]
    def fore_door(e):   # the axis door at a band's fore edge (or its round room's fore edge)
        y = e["edge"][0] if e["kind"] == "O" else e["a"]
        return [d for d in DOORS if d[0] == int(AX) and d[1] == int(round(y))]
    def side_door(n):
        g = R[n]; x = int(AX - SW) if g.bounds[2] <= AX else int(AX + SW)
        return [d for d in DOORS if d[0] == x and g.bounds[1] < d[1] < g.bounds[3]]
    ib = info.index(bay)
    fore = [e for e in info[:ib] if e["kind"] == "S" and e["rooms"]]
    aft = info[ib + 1:]
    rescue = next((e["rescue"] for e in info if "rescue" in e and e["rescue"] in R), None)
    centre = lambda kinds, es: [e for e in es if e["kind"] in kinds]
    reactor = next((e for e in aft if "Reactor" in e["rooms"][0]), None) if aft else None
    eng = next((e for e in aft if e["rooms"] and "Engineering" in e["rooms"][0]), None)
    last = aft[-1]
    cic = next((e for e in info[1:ib] if e["kind"] == "O"), None)
    bridge = info[0]
    locks, guards = [], []
    def lock(ds, key, why):
        for d in ds: locks.append({"door": [d[0], d[1]], "key": key, "why": why})
    g1 = fore[-1]["rooms"][0] if fore else bay["rooms"][0]
    if g1 == rescue and fore and len(fore[-1]["rooms"]) > 1: g1 = fore[-1]["rooms"][1]
    guards.append({"key": 1, "room": g1, "at": pt(g1)})
    if K >= 2:
        lock(fore_door(aft[0]) if aft[0]["kind"] != "S" else [(int(AX), bay["b"], "h")], 1, "aft of the bay")
        guards.append({"key": 2, "room": eng["rooms"][0], "at": pt(eng["rooms"][0])})
    if K >= 3:
        lock([d for d in DOORS if d[0] == int(AX) and d[1] == int(round(cic["edge"][1]))], 2, "the command section")
        guards.append({"key": 3, "room": cic["rooms"][0], "at": pt(cic["rooms"][0])})
    lock([d for d in DOORS if d[0] == int(AX) and d[1] == bridge["b"]], K, "the bridge")
    tgt_sab = reactor or last
    lock(fore_door(tgt_sab), K, "the " + tgt_sab["rooms"][0].lower())
    targets = {"sabotage": {"room": tgt_sab["rooms"][0], "at": pt(tgt_sab["rooms"][0]), "key": K},
               "capture": {"room": bridge["rooms"][0], "at": pt(bridge["rooms"][0]), "key": K}}
    if rescue:
        lock(side_door(rescue), K, "the " + rescue.lower())
        targets["rescue"] = {"room": rescue, "at": pt(rescue), "key": K}
    lifts = [{"room": n, "at": pt(n)} for n in ("Lift (port)", "Lift (starboard)") if n in R]
    rg = {n: (2 if R[n].area > 9000 else 1) for n in R if "Lift" not in n and n != bay["rooms"][0]}
    return {"entry": {"room": bay["rooms"][0], "at": list(entry)}, "locks": locks, "guards": guards, "targets": targets,
            "wreck": [], "lifts": lifts, "patrols": [], "room_guards": rg}


def main(sid, here, cls):
    S, G = compose(sid, here, cls)
    bad = run(S)
    json.dump(G, open(os.path.join(here, "gameplay.json"), "w"), indent=1)
    lp = [g for n, g in S.R.items() if n == "Lift (port)"]
    print("bands:", " | ".join("%s %s %d-%d" % (e["kind"], "/".join(e["rooms"]) or "-", e["a"], e["b"]) for e in S.bands))
    if lp: print("lift (port):", [round(v) for v in lp[0].bounds])
    return bad
