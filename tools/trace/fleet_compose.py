#!/usr/bin/env python3
"""v13.106 (owner: "build the Imperium, Elyza, Orion and Liberator fleet decks nonstop, copy the Covenant Capital
example"): the owner-preferred "pass 2a" upper (COMMAND) and lower (HOLD) decks as ONE template, built in the
Covenant Capital's frame (axis 527, lift shaft (481, 490)) with exactly its hand-picked traced rooms, then moved onto
any ship: translated so the axis and the lift line up, the lift car re-seated on the ship's own main-deck shaft,
the room NAMES set per class (Data: CLASS_NAMES), and the decks run through decklib.check() against that ship's own
hull. Does not change decklib (shared with the other session).

    from fleet_compose import compose
    compose(sid, here, src, ax, shaft, cls)   # -> failures (list); writes deck_upper/lower .json/.png, decks_plan.jpg,
                                              #    decks_on_map.jpg, decks_sources.jpg in `here`"""
import json, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapely import affinity
from shapely.geometry import Polygon, LineString, box, shape as _shape
import decklib
from decklib import lib, Deck
from planlib import hall, circle

FX, FLIFT = 527.0, (481.0, 490.0)
SERVICE = ["conduit", "duct", "power trunk", "coolant loop", "crawlspace", "machinery", "structure", "wiring run", "fuse bay"]
def ring(cx, cy, r): return circle(cx, cy, r).exterior
def junction(cx, cy, d=4.6): return lib("tianjin_10", cx, cy, w=d, h=d)
def arc(cx, cy, r, a0, a1, n=24):
    return LineString([(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)])
def sector(cx, cy, r0, r1, a0, a1):
    return Polygon(list(arc(cx, cy, r1, a0, a1).coords) + list(arc(cx, cy, r0, a1, a0).coords))

def _upper():
    AX = FX
    LIFT = box(467, 476, 495, 504)
    # ===================================================================== UPPER DECK - FLAG / COMMAND
    U = Deck(AX); M = U.M
    U.room("Observation Dome", lib("malgus_11", 527, 290, w=11.0), "malgus_11 command hub, railing ring", feat=[ring(527, 290, 32), ring(527, 290, 14)])
    U.room("Lift", LIFT, "lift car (the main deck's Lift (port) shaft)")
    U.room("Flag Briefing", lib("tianjin_09", 425, 365, w=9.7, h=4.1, rot=90), "tianjin_09 long room", twin="Holo Chart Room")
    U.room("Security Office", lib("fury_08", 424, 438, w=6.2, h=5.3), "fury_08 secondary quarters (angled)", twin="Weapons Locker")
    U.room("Admiral's Quarters", lib("fury_04", 410, 515, w=8.9, h=6.1, flip=True), "fury_04 captain's quarters", twin="Captain's Quarters")
    U.room("War Room", lib("kasparov_a_09", 462, 612, w=11.3, h=6.1), "kasparov_a_09 central hall (chamfered)", twin="Fleet Ops")
    U.room("Flag Holo Room", lib("tianjin_14", 462, 700, w=10.0, h=9.0), "tianjin_14 round CIC", twin="Comms Center")
    U.room("Officers' Mess", lib("kasparov_b_06", 462, 845, w=10.5, h=10.5), "kasparov_b_06 dining area (round)", twin="Wardroom")
    U.room("Lounge P", lib("fury_06", 345, 650, w=7.1, h=18.5, rot=90), "fury_06 lounge + holoterminal", twin="Lounge S")
    U.room("Cabins A", lib("kasparov_b_03", 340, 810, w=9.0, h=15.5, rot=90), "kasparov_b_03 passenger quarters", twin="Cabins B")
    U.room("Galley", lib("tianjin_01", 348, 945, w=10.6, h=11.2, flip=True), "tianjin_01 galley (quarter round)", twin="Ready Room")
    U.room("Gunnery Control", lib("tianjin_26", 527, 990, w=11.1, h=9.9, rot=90), "tianjin_26 gunnery (tapered)")
    U.H += [hall((527, 345), (527, 940), w=24), junction(527, 400), junction(527, 560), junction(527, 760), junction(527, 930), box(495, 482, 515, 498)]
    U.hall(hall((527, 400), (420, 400), w=16)); U.hall(hall((527, 560), (400, 560), w=18)); U.hall(hall((400, 560), (400, 930), w=18))
    U.hall(hall((400, 760), (527, 760), w=18)); U.hall(hall((400, 930), (527, 930), w=18))
    U.R = decklib.settle(U.R, U.H, whole={"Observation Dome", "Lift", "Flag Holo Room", "Comms Center", "Officers' Mess", "Wardroom"},
                         twins=U.TW, mirror_fn=M, mode="close")
    U.door(527, 345, "h", both=False); U.door(495, 490, "v", both=False)
    U.link("Flag Briefing", (425, 400)); U.link("Security Office", (430, 400)); U.link("Admiral's Quarters", (410, 560))
    U.link("War Room", (409, 612)); U.link("War Room", (515, 612)); U.link("Flag Holo Room", (515, 700)); U.link("Officers' Mess", (515, 845))
    U.link("Officers' Mess", (409, 845)); U.link("Lounge P", (391, 650)); U.link("Cabins A", (391, 810)); U.link("Galley", (391, 925))
    U.link("Gunnery Control", (505, 939), both=False)
    U.D = list(dict.fromkeys(U.D))
    for nm, f in [("Flag Briefing", lambda x, y: [ring(x, y, 9)]), ("War Room", lambda x, y: [ring(x, y, 11)]),
                  ("Flag Holo Room", lambda x, y: [ring(x, y, 22), ring(x, y, 9)]), ("Officers' Mess", lambda x, y: [ring(x, y, 16)]),
                  ("Admiral's Quarters", lambda x, y: [box(x - 16, y - 8, x + 16, y + 8)]), ("Lounge P", lambda x, y: [ring(x, y, 10)]),
                  ("Galley", lambda x, y: [LineString([(x - 16, y + 10), (x + 16, y + 10)])])]:
        U.feat(nm, f(*U.ctr(nm)))
    U.R = decklib.finalize(U.R, U.H, list(U.R), U.TW, M, keep={"Observation Dome", "Lift", "Flag Holo Room", "Comms Center", "Officers' Mess", "Wardroom"})
    for nm, sd, off, lab in [("Admiral's Quarters", "w", 0, "locker"), ("War Room", "s", 0, "console"), ("Security Office", "w", 0, "weapon rack"),
                             ("Cabins A", "w", -30, "locker"), ("Cabins A", "w", 30, "locker"), ("Lounge P", "w", 0, "med station"),
                             ("Galley", "w", 0, "fuse box")]:
        U.wallniche(nm, sd, off, lab)
    U.hatch((400, 690), "v"); U.hatch((527, 700), "v"); U.hatch((470, 930), "h")
    SHORT = {"Observation Dome": "Observation", "Admiral's Quarters": "Admiral", "Captain's Quarters": "Captain",
             "Security Office": "Security", "Weapons Locker": "Weapons", "Flag Holo Room": "Flag Holo", "Comms Center": "Comms",
             "Officers' Mess": "Mess", "Gunnery Control": "Gunnery", "Holo Chart Room": "Holo Chart", "Flag Briefing": "Briefing"}

    return U, SHORT

def _lower():
    AX = FX
    LIFT = box(467, 476, 495, 504)
    # ===================================================================== LOWER DECK - HOLD
    L = Deck(AX)
    L.room("Lift", LIFT, "lift car (the main deck's Lift (port) shaft)")
    L.room("Brig", lib("malgus_07", 527, 673, w=4.4, h=13.6, rot=90), "malgus_07 entry corridor as the cell corridor")
    BX0, BY0, BX1, BY1 = [round(v, 1) for v in L.R["Brig"].bounds]
    hh = (BY1 - BY0) / 4
    for i in range(4):
        y = BY0 + hh * (i + 0.5)
        L.room("Cell %d" % (i + 1), lib("kasparov_b_01", BX1 + 34, y, w=6.8, h=hh / 10), "kasparov_b_01 cabin", feat=[box(BX1 + 38, y - 8, BX1 + 48, y + 8)])
    L.room("Detention", lib("fury_08", BX0 - 36, BY0 + hh, w=7.2, h=2 * hh / 10, flip=True), "fury_08 secondary quarters (angled)")
    for i, nm in enumerate(("Cell 5", "Cell 6")):
        y = BY0 + hh * (2.5 + i)
        L.room(nm, lib("kasparov_b_01", BX0 - 34, y, w=6.8, h=hh / 10), "kasparov_b_01 cabin", feat=[box(BX0 - 48, y - 8, BX0 - 38, y + 8)])
    L.room("Life Support", lib("kasparov_a_14", 420, 505, w=6.6, h=6.6), "kasparov_a_14 hyperdrive room (round machine)", twin="Water Recycling",
           feat=[ring(420, 505, 18), circle(420, 505, 8).exterior])
    L.room("Magazine P", lib("kasparov_b_07", 330, 510, w=7.4, h=6.9, flip=True), "kasparov_b_07 storage & lockers (wedge)", twin="Magazine S")
    L.room("Cargo Hold A", lib("kasparov_b_11", 330, 670, w=11.3, h=17.4), "kasparov_b_11 cargo bay", twin="Cargo Hold B")
    L.room("Shield Gen P", lib("kasparov_a_14", 335, 800, w=7.4, h=7.4), "kasparov_a_14 round machine room", twin="Shield Gen S",
           feat=[ring(335, 800, 20), circle(335, 800, 9).exterior])
    L.room("Machine Shop", lib("kasparov_a_08", 462, 820, w=11.3, h=5.8, rot=90), "kasparov_a_08 machine shop (angled)", twin="Fuel Store")
    L.room("Spare Parts", lib("tianjin_29", 462, 920, w=11.8, h=8.0), "tianjin_29 machineshop", twin="Med Store")
    L.room("Hangar Workshop", lib("fury_12", 340, 935, w=8.4, h=17.6, rot=90), "fury_12 engine room round a machine", twin="Vehicle Store")
    L.room("Coolant Pumps", circle(527, 1068, 39), "tianjin_14 round room (pump in a ring walkway), drawn true round",
           feat=[ring(527, 1068, 22), circle(527, 1068, 9).exterior])
    L.room("Escape Pods", sector(527, 1068, 62, 92, 40, 140), "carrick ring corridor (arc, 3 m), pod hatches along the hull")
    L.room("Battery P", lib("kasparov_a_14", 350, 1080, w=6.6, h=6.6), "kasparov_a_14 round machine room", twin="Battery S",
           feat=[ring(350, 1080, 18), circle(350, 1080, 8).exterior])
    L.room("Pump Room", lib("tianjin_30", 438, 1090, w=7.3, h=4.6), "tianjin_30 workshop", twin="Fuel Pumps")
    L.H += [hall((527, 460), (527, 576), w=24), hall((527, 769), (527, 1000), w=24), junction(527, 570), junction(527, 775), junction(527, 1000),
            box(495, 482, 515, 498)]
    L.hall(hall((527, 570), (320, 570), w=18)); L.hall(hall((400, 570), (400, 1110), w=18)); L.hall(hall((400, 775), (527, 775), w=18))
    L.hall(hall((400, 1000), (527, 1000), w=18))
    WH = {"Lift", "Brig", "Life Support", "Water Recycling", "Shield Gen P", "Shield Gen S", "Coolant Pumps", "Escape Pods", "Battery P", "Battery S"}
    L.R = decklib.settle(L.R, L.H, whole=WH, twins=L.TW, mirror_fn=L.M, mode="close")
    L.door(495, 490, "v", both=False)
    L.link("Life Support", (420, 561)); L.link("Magazine P", (330, 561)); L.link("Brig", (527, 576), both=False)
    for i in range(4): L.door(BX1, round(L.R["Cell %d" % (i + 1)].centroid.y, 1), "v", both=False)
    for nm in ("Detention", "Cell 5", "Cell 6"): L.door(BX0, round(L.R[nm].centroid.y, 1), "v", both=False)
    L.link("Cargo Hold A", (391, 670)); L.link("Shield Gen P", (391, 800)); L.link("Machine Shop", (462, 784)); L.link("Spare Parts", (409, 920))
    L.link("Spare Parts", (515, 920)); L.link("Hangar Workshop", (391, 935)); L.link("Coolant Pumps", (527, 1009), both=False)
    L.link("Battery P", (391, 1080)); L.link("Pump Room", (409, 1090))
    _c = L.R["Coolant Pumps"].bounds[3]; _p = L.R["Escape Pods"].intersection(LineString([(527, 1000), (527, 1300)])).bounds[1]
    L.H.append(hall((527, _c), (527, _p), w=16).difference(L.R["Coolant Pumps"]).difference(L.R["Escape Pods"]))
    L.door(527, round(_c, 1), "h", both=False); L.door(527, round(_p, 1), "h", both=False)
    L.D = list(dict.fromkeys(L.D))
    for nm, f in [("Cargo Hold A", lambda x, y: [box(x - 30, y - 50, x, y - 20), box(x - 30, y + 5, x, y + 35)]),
                  ("Machine Shop", lambda x, y: [ring(x, y, 8)]), ("Spare Parts", lambda x, y: [box(x - 30, y - 4, x + 30, y + 4)]),
                  ("Hangar Workshop", lambda x, y: [ring(x, y, 12)]), ("Pump Room", lambda x, y: [ring(x, y, 7)])]:
        L.feat(nm, f(*L.ctr(nm)))
    L.R = decklib.finalize(L.R, L.H, list(L.R), L.TW, L.M, keep=WH)
    for nm, sd, off, lab in [("Cargo Hold A", "w", 0, "console"), ("Detention", "w", 0, "console"), ("Magazine P", "w", 0, "locker"),
                             ("Spare Parts", "s", 0, "shelves"), ("Hangar Workshop", "w", 0, "fuse box")]:
        L.wallniche(nm, sd, off, lab)
    for a in (70, 90, 110):
        L.NICHE.append(("Escape Pods", (round(527 + 92 * math.cos(math.radians(a)), 1), round(1068 + 92 * math.sin(math.radians(a)), 1)), "s", "pod hatch"))
    L.hatch((400, 720), "v"); L.hatch((527, 900), "v"); L.hatch((460, 1000), "h")
    SHORT = {"Life Support": "Life Sup.", "Water Recycling": "Water", "Coolant Pumps": "Coolant", "Escape Pods": "Pods",
             "Hangar Workshop": "Workshop", "Vehicle Store": "Vehicles", "Machine Shop": "Machine", "Detention": "Detention"}

    return L, SHORT, WH

UP_ROUND = {"Observation Dome", "Flag Holo Room", "Comms Center", "Officers' Mess", "Wardroom"}
LO_ROUND = {"Life Support", "Water Recycling", "Shield Gen P", "Shield Gen S", "Coolant Pumps", "Escape Pods", "Battery P", "Battery S"}
# room names by class (the frame's names are the Capital's); a class may rename any room (owner's class rules,
# docs/HANDOFF_SHIP_INTERIORS.md section 7)
CLASS_NAMES = {
    "capital": {},
    "cruiser": {"Observation Dome": "Command Dome", "Admiral's Quarters": "XO Quarters", "Flag Briefing": "Briefing", "Flag Holo Room": "Gunnery Plot",
                "War Room": "Fire Control", "Fleet Ops": "Targeting", "Hangar Workshop": "Gun Workshop", "Vehicle Store": "Shell Store"},
    "destroyer": {"Observation Dome": "Command Dome", "Admiral's Quarters": "XO Quarters", "Flag Briefing": "Briefing", "Flag Holo Room": "Weapons Plot",
                  "War Room": "Torpedo Control", "Fleet Ops": "Fire Control", "Hangar Workshop": "Torpedo Shop", "Vehicle Store": "Warhead Store",
                  "Cargo Hold A": "Armoury A", "Cargo Hold B": "Armoury B"},
    "resupply": {"Observation Dome": "Command Dome", "Admiral's Quarters": "Quartermaster", "Flag Briefing": "Manifest Room", "Flag Holo Room": "Cargo Control",
                 "War Room": "Loading Office", "Fleet Ops": "Dock Control", "Hangar Workshop": "Loader Bay", "Vehicle Store": "Crate Store",
                 "Magazine P": "Fuel Store P", "Magazine S": "Fuel Store S"},
    "trooptransport": {"Observation Dome": "Command Dome", "Admiral's Quarters": "Commander", "Flag Briefing": "Briefing", "Flag Holo Room": "Drop Plot",
                       "War Room": "Mission Room", "Fleet Ops": "Drop Control", "Cabins A": "Barracks A", "Cabins B": "Barracks B",
                       "Hangar Workshop": "Drop Pod Bay A", "Vehicle Store": "Drop Pod Bay B", "Cargo Hold A": "Armoury A", "Cargo Hold B": "Armoury B"},
    "frigate": {"Observation Dome": "Command Dome", "Admiral's Quarters": "XO Quarters", "Flag Briefing": "Briefing", "Flag Holo Room": "Gun Plot",
                "War Room": "Gun Deck Control", "Fleet Ops": "Navigation"},
}

def _ren(D, names, short):
    """rename the rooms of a Deck (and everything that refers to them)"""
    n = lambda k: names.get(k, k)
    D.R = {n(k): v for k, v in D.R.items()}; D.F = {n(k): v for k, v in D.F.items()}; D.FROM = {n(k): v for k, v in D.FROM.items()}
    D.FIT = {n(k): v for k, v in D.FIT.items()}; D.TW = {n(k): n(v) for k, v in D.TW.items()}
    D.NICHE = [(n(a), b, c, d) for a, b, c, d in D.NICHE]
    short = {n(k): v for k, v in short.items()}
    for old, new in names.items():
        if new not in short and len(new) > 12: short[new] = new.split()[0]
    return short

def _move(D, dx, dy):
    T = lambda g: affinity.translate(g, dx, dy)
    D.R = {k: T(g) for k, g in D.R.items()}; D.H = [T(h) for h in D.H]
    D.F = {k: [T(f) for f in fs] for k, fs in D.F.items()}
    D.D = [(round(x + dx, 1), round(y + dy, 1), o) for x, y, o in D.D]
    D.NICHE = [(k, (round(p[0] + dx, 1), round(p[1] + dy, 1)), sd, lab) for k, p, sd, lab in D.NICHE]
    D.HATCH = [((round(p[0] + dx, 1), round(p[1] + dy, 1)), o) for p, o in D.HATCH]
    D.AX += dx
    from planlib import mirror
    D.M = mirror(D.AX)

def _reseat_lift(D, ax, shaft, dx, dy):
    """the lift car onto the ship's own shaft; its connector and door re-cut to the spine"""
    sx, sy = shaft
    old_conn = affinity.translate(box(495, 482, 515, 498), dx, dy)
    D.H = [h for h in D.H if not h.equals(old_conn) and not (h.symmetric_difference(old_conn).area < 1)]
    old_door = (round(495 + dx, 1), round(490 + dy, 1))
    D.D = [d for d in D.D if (d[0], d[1]) != old_door]
    D.R["Lift"] = box(sx - 14, sy - 14, sx + 14, sy + 14)
    if abs(sx - ax) <= 12:          # the shaft on the axis: the lift car stands IN the spine, doors fore and aft
        cut = box(ax - 40, sy - 14, ax + 40, sy + 14)
        D.H = [q for q in (h.difference(cut) for h in D.H) if not q.is_empty and q.area > 4]
        D.H = [max(getattr(q, "geoms", [q]), key=lambda r: r.area) if q.geom_type == "MultiPolygon" and len(q.geoms) == 1 else q for q in D.H]
        D.H = [g for q in D.H for g in getattr(q, "geoms", [q])]
        D.R["Lift"] = box(ax - 14, sy - 14, ax + 14, sy + 14)
        D.D += [(ax, sy - 14, "h"), (ax, sy + 14, "h")]
    elif sx < ax - 12:
        D.H.append(box(sx + 14, sy - 8, ax - 11, sy + 8)); D.D.append((sx + 14, sy, "v"))
    elif sx > ax + 12:
        D.H.append(box(ax + 11, sy - 8, sx - 14, sy + 8)); D.D.append((sx - 14, sy, "v"))

def _prune(D, drop, keep_x=None, max_y=None):
    """take rooms out of the frame deck (a narrower / shorter hull): rooms with drop(name, centroid) go (with their
    twin), corridors beyond keep_x (frame x range) or below max_y are cut back, doors left facing service space go."""
    from shapely.geometry import Point
    from shapely.ops import unary_union
    stb = set(D.TW.values())
    gone = set()
    for k in list(D.R):
        if k == "Lift" or k in stb: continue
        c = D.R[k].centroid
        if drop(k, c):
            gone.add(k)
            if k in D.TW: gone.add(D.TW[k])
    for k in gone:
        for dct in (D.R, D.F, D.FROM, D.FIT): dct.pop(k, None)
    D.TW = {a: b for a, b in D.TW.items() if a not in gone}
    D.NICHE = [n for n in D.NICHE if n[0] not in gone]
    keep_box = box(keep_x[0] if keep_x else -1e4, -1e4, keep_x[1] if keep_x else 1e4, max_y if max_y else 1e4)
    H = []
    for h in D.H:
        q = h.intersection(keep_box)
        if q.is_empty or q.area < 30: continue
        H += [g for g in getattr(q, "geoms", [q]) if g.area >= 30]
    # stubs that only led to a removed room: a corridor piece touching no kept room and only one other corridor piece
    for _ in range(3):
        keepH = []
        for i, h in enumerate(H):
            near_rooms = any(h.distance(g) < 1.0 for g in D.R.values())
            near_halls = sum(1 for j, o in enumerate(H) if j != i and h.distance(o) < 1.0)
            if near_rooms or near_halls >= 2: keepH.append(h)
        H = keepH
    D.H = H
    walk = unary_union(list(D.R.values()) + D.H).buffer(0.01)
    def ok(x, y, o):
        e = decklib.T + 3.0
        pa, pb = ((x, y - e), (x, y + e)) if o == "h" else ((x - e, y), (x + e, y))
        return walk.contains(Point(pa)) and walk.contains(Point(pb))
    D.D = [d for d in D.D if ok(*d)]
    D.HATCH = [h for h in D.HATCH if walk.contains(Point(h[0]))]
    return gone

def compose(sid, here, src, ax, shaft, cls="capital", names=None, titles=None, dy_extra=0.0, narrow=False, max_y=None, coverage=None, drop=()):
    """narrow: drop the outer columns (a destroyer / frigate hull); max_y: drop everything below this FRAME y (a short hull)"""
    nm = dict(CLASS_NAMES.get(cls, {})); nm.update(names or {})
    dx = ax - FX; dy = shaft[1] - FLIFT[1] + dy_extra
    U, SU = _upper(); L, SL, WH = _lower()
    if drop:
        for D in (U, L): _prune(D, lambda k, c: k in drop)
    if narrow or max_y:
        kx = (395, 2 * FX - 395) if narrow else None
        dropf = lambda k, c: (narrow and (c.x < 400 or c.x > 2 * FX - 400)) or (max_y and c.y > max_y)
        for D in (U, L):
            g = _prune(D, dropf, kx, (max_y + 40) if max_y else None)
            print("  frame rooms left out:", sorted(g))
    for D in (U, L):
        _move(D, dx, dy); _reseat_lift(D, ax, shaft, dx, dy)
    SU = _ren(U, nm, SU); SL = _ren(L, nm, SL)
    n = lambda k: nm.get(k, k)
    cut_any = [bool(max_y)]
    # rooms that poke out of a narrower hull: trimmed to the hull (a straight cut, mirrored to the twin)
    hp = decklib.hull(src, ax).buffer(-decklib.T - 2, join_style=2)
    for D in (U, L):
        stb = set(D.TW.values()); small = set(); trimmed = []
        for k in list(D.R):
            if k in stb or k == "Lift": continue
            g = D.R[k]
            if hp.contains(g): continue
            x0, y0, x1, y1 = g.bounds
            c = g.centroid; outer = "w" if c.x < ax - 1 else ("e" if c.x > ax + 1 else None)
            q = g
            for cut in range(2, 90, 2):     # shave strips off the OUTER side (away from the spine), then the nose side
                cx_ = min(cut, 60); cy_ = max(0, cut - 60) * 2
                q = g
                if outer == "w": q = q.intersection(box(x0 + cx_, y0 - 1, x1 + 1, y1 + 1))
                if outer == "e": q = q.intersection(box(x0 - 1, y0 - 1, x1 - cx_, y1 + 1))
                if outer is None or cy_: q = q.intersection(box(x0 - 1, y0 + (cy_ or cut), x1 + 1, y1 + 1))
                if hp.contains(q): break
            if q.is_empty or q.area < 0.45 * g.area:
                small.add(k); print("  too little left inside the hull, left out:", k); continue
            q = decklib.dedupe(max(getattr(q, "geoms", [q]), key=lambda r: r.area))
            q2 = decklib.clean(q, nub=6.0)
            q2 = max(getattr(q2, "geoms", [q2]), key=lambda r: r.area)
            if hp.contains(q2) and q2.area > 0.9 * q.area: q = decklib.dedupe(q2)
            D.R[k] = q; trimmed.append(k)
            D.F[k] = [f for f in D.F.get(k, []) if q.buffer(-3.0).contains(f)]
            if k in D.TW: D.F[D.TW[k]] = [D.M(f) for f in D.F[k]]
            D.NICHE = [n for n in D.NICHE if n[0] not in (k, D.TW.get(k)) or (D.R[n[0]] if n[0] == k else D.M(q)).buffer(-1).contains(box(n[1][0] - 8, n[1][1] - 8, n[1][0] + 8, n[1][1] + 8))]
            if k in D.TW: D.R[D.TW[k]] = D.M(q)
            print("  trimmed to the hull:", k, "(%.0f%% kept)" % (100 * q.area / g.area))
        if small: _prune(D, lambda k, c, sm=frozenset(small): k in sm)
        if small or trimmed or max_y: cut_any[0] = True
    P = json.load(open(os.path.join(here, "plan.json")))
    LIFT = U.R["Lift"]
    lifts_main = [k for k in P["rooms"] if "ift" in k]
    if not lifts_main: print("  NOTE: the main deck has no lift: a NEW shaft at %s (the main deck needs a lift there too)" % (shaft,))
    lift_ok = [] if not lifts_main or any(_shape(g).buffer(2).contains(LIFT) for k, g in P["rooms"].items() if "ift" in k) else ["the shaft is not a main deck lift"]
    CH = dict(service=SERVICE, lift_ok=lift_ok, outline_style="ring", coverage=coverage or ((0.40, 0.65) if narrow else ((0.50, 0.65) if cut_any[0] else (0.55, 0.65))))
    if cut_any[0] and not narrow: print("  NOTE: rooms trimmed / left out for this hull: rooms / deck target 50-65%")
    if narrow: print("  NOTE: narrow hull (outer columns left out): rooms / deck target 40-65%")
    tu, tl = titles or ("UPPER DECK - COMMAND", "LOWER DECK - HOLD")
    bad = decklib.run(sid, here, src, ax, "upper", 1, U.R, U.H, U.D, [tuple(shaft)], title=tu, features=U.F, short=SU,
                      whole={"Observation Dome", "Lift"} and {n("Observation Dome"), "Lift"}, niches=U.NICHE, hatches=U.HATCH, source=U.FROM,
                      fits=U.FIT, round_rooms={n(k) for k in UP_ROUND}, **CH)
    bad += decklib.run(sid, here, src, ax, "lower", -1, L.R, L.H, L.D, [tuple(shaft)], title=tl, features=L.F, short=SL,
                       whole={n(k) for k in WH}, niches=L.NICHE, hatches=L.HATCH, source=L.FROM, fits=L.FIT,
                       anchor={n("Escape Pods"): (527 + dx, 1146 + dy)}, round_rooms={n(k) for k in LO_ROUND}, **CH)
    decklib.both(os.path.join(here, "deck_upper.png"), os.path.join(here, "deck_lower.png"), os.path.join(here, "decks_plan.jpg"))
    decklib.both(os.path.join(here, "deck_upper_on_map.jpg"), os.path.join(here, "deck_lower_on_map.jpg"), os.path.join(here, "decks_on_map.jpg"))
    decklib.source_sheet([os.path.join(here, "deck_upper.json"), os.path.join(here, "deck_lower.json")], os.path.join(here, "decks_sources.jpg"))
    print("TOTAL FAILURES (both decks):", len(bad))
    return bad
