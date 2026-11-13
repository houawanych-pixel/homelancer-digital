#!/usr/bin/env python3
"""Imperium Troop Transport: PROPOSED upper (command) deck and lower (hold) deck - PASS 2 (owner, 13 Nov 2026:
"stop packing rooms like Tetris. Real ships have SERVICE SPACE"). (Pass 1, the packed version: build_decks_v1.py.)

Every room is a REAL traced room from the reference library (tools/trace/shape_library.json: Fury, Defender,
Kasparov, Malgus command deck, Carrick ring, Tianjin), picked by function, scaled / rotated / mirrored to fit; FROM
records which traced room each one came from. Rooms sit inside structure: the space round and between them is
service space (conduit, duct, power trunk, coolant loop, crawlspace, machinery, structure: dark grey, not walkable),
rooms take 55-65 % of the deck, short connectors run from the corridors to the rooms, niches are cut into the thick
walls, maintenance hatches open off the corridors. Corridors: a main spine (2.4 m) with small octagonal junction rooms,
side branches (1.6-1.8 m), a lateral turret corridor aft (Fury) with hatches at its ends.
Mirrored about x 494. Lift A (main <-> upper) and Lift B (main <-> lower) where they stand on the main deck.
decklib.check() must print 0 failures. Walls 0.4 m, doors 1.6 m, 10 px = 1 m."""
import json, math, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import hall, mirror, circle
import decklib
from decklib import lib, fit
from shapely.geometry import Polygon, LineString, box

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "source.jpg")
AX = 494.0
M = mirror(AX)
LIFT_A, LIFT_B = (459, 490), (529, 490)
# owner (pass 2 review): the upper and lower lifts stand in ONE shaft: the main deck's Lift A, (459, 490), runs up and down
SHAFT = LIFT_A
_MAIN = json.load(open(os.path.join(HERE, "plan.json")))
LIFT_CHECK = [] if any(abs(sum(_c) / len(_c) - v) < 1 for _c, v in []) else []
from shapely.geometry import shape as _shape
if not _shape(_MAIN["rooms"]["Lift A"]).contains(_shape({"type": "Point", "coordinates": SHAFT})): LIFT_CHECK.append("the shaft is not on the main deck's Lift A")
SERVICE = ["conduit", "duct", "power trunk", "coolant loop", "crawlspace", "machinery", "structure", "wiring run", "fuse bay"]

def ring(cx, cy, r): return circle(cx, cy, r).exterior
def arc(cx, cy, r, a0, a1, n=24):
    return LineString([(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)])
def sector(cx, cy, r0, r1, a0, a1):
    return Polygon(list(arc(cx, cy, r1, a0, a1).coords) + list(arc(cx, cy, r0, a1, a0).coords))
def junction(cx, cy, d=4.6): return lib("tianjin_10", cx, cy, w=d, h=d)        # a small octagonal junction room (Tianjin lift hall)

class Deck:
    """Rooms, halls, doors and the 'which traced room' record of one deck; port side mirrored to starboard."""
    def __init__(s): s.R, s.H, s.D, s.FROM, s.F, s.NICHE, s.HATCH, s.TW, s.FIT = {}, [], [], {}, {}, [], [], {}, {}
    def room(s, name, g, src=None, twin=None, feat=()):
        if isinstance(g, tuple): g, src = g                       # (from decklib.fit: the traced room it picked)
        s.R[name] = g; s.FROM[name] = src; s.F[name] = list(feat)
        if src and not src.startswith("lift") and decklib.LAST_FIT: s.FIT[name] = decklib.LAST_FIT["aspect_change"]
        if twin:
            s.R[twin] = M(g); s.FROM[twin] = src + " (mirrored)"; s.F[twin] = [M(f) for f in feat]; s.TW[name] = twin
            if name in s.FIT: s.FIT[twin] = s.FIT[name]
    def ctr(s, name): c = s.R[name].centroid; return c.x, c.y
    def hall(s, g, both=True):
        s.H.append(g)
        if both: s.H.append(M(g))
    def door(s, x, y, o, both=True):
        s.D.append((x, y, o))
        if both and abs(x - AX) > 1: s.D.append((round(2 * AX - x, 1), y, o))
    def link(s, name, to, w=16, both=True):
        """A short connector from the room's wall to the corridor point `to` (straight along x or y); the door sits
        on the room's wall where the connector meets it."""
        g = s.R[name]; tx, ty = to; c = g.centroid
        horiz = abs(tx - c.x) > abs(ty - c.y)
        ray = LineString([(c.x, ty), (tx, ty)]) if horiz else LineString([(tx, c.y), (tx, ty)])
        hit = g.boundary.intersection(ray)
        pts = [p for p in getattr(hit, "geoms", [hit]) if not p.is_empty and p.geom_type == "Point"]
        if not pts:
            from shapely.geometry import Point as _P
            if g.distance(_P(tx, ty)) < 1.5: s.door(tx, ty, "v" if horiz else "h", both); return   # (the room already meets the corridor there)
            raise SystemExit("link %s -> %s: the connector misses the room" % (name, to))
        if horiz:
            px = round(min(pts, key=lambda p: abs(p.x - tx)).x, 1)
            if abs(px - tx) > 1.0: s.stub(name, hall((px, ty), (tx, ty), w=w).difference(g), both)   # (ends on the room's own wall, curved or not)
            s.door(px, ty, "v", both)
        else:
            py = round(min(pts, key=lambda p: abs(p.y - ty)).y, 1)
            if abs(py - ty) > 1.0: s.stub(name, hall((tx, py), (tx, ty), w=w).difference(g), both)
            s.door(tx, py, "h", both)
    def stub(s, name, h, both):
        """A connector: the rooms it passes are cut back so it runs clear (one wall between them)."""
        for hh in ([h, M(h)] if both else [h]):
            s.H.append(hh)
            for k in list(s.R):
                if k != name and k != s.TW.get(name) and s.R[k].intersection(hh).area > 0.5:
                    q = s.R[k].difference(hh.buffer(0.01)); q = max(getattr(q, "geoms", [q]), key=lambda r: r.area)
                    s.R[k] = decklib.dedupe(q)
    def niche(s, name, at, side, lab, both=True):
        s.NICHE.append((name, at, side, lab))
        if both and name in s.TW: s.NICHE.append((s.TW[name], (2 * AX - at[0], at[1]), {"e": "w", "w": "e"}.get(side, side), lab))
    def wallniche(s, name, side, off, lab, both=True):
        """An equipment niche: a small recess on the room side of its wall n/s/e/w, near `off` px from the room's
        centre line; tries nearby spots until the recess sits wholly inside the room."""
        g = s.R[name]; c = g.centroid; x0, y0, x1, y1 = g.bounds
        for o2 in [off, off + 10, off - 10, off + 20, off - 20, off + 30, off - 30]:
            if side in "ns": ray = LineString([(c.x + o2, c.y), (c.x + o2, y0 - 1 if side == "n" else y1 + 1)])
            else: ray = LineString([(c.x, c.y + o2), (x0 - 1 if side == "w" else x1 + 1, c.y + o2)])
            hit = g.exterior.intersection(ray)
            pts = [p for p in getattr(hit, "geoms", [hit]) if p.geom_type == "Point"]
            if not pts: continue
            far = max(pts, key=lambda p: p.distance(c)); x, y = far.x, far.y
            nb = {"n": box(x - 6, y + 2.5, x + 6, y + 9.5), "s": box(x - 6, y - 9.5, x + 6, y - 2.5),
                  "w": box(x + 2.5, y - 6, x + 9.5, y + 6), "e": box(x - 9.5, y - 6, x - 2.5, y + 6)}[side]
            if g.contains(nb) and (name not in s.TW or s.R[s.TW[name]].contains(M(nb))):
                s.niche(name, (round(x, 1), round(y, 1)), side, lab, both); return
        print("  (no room for a niche on the %s wall of %s)" % (side, name))
    def hatch(s, at, o, both=True):
        s.HATCH.append((at, o))
        if both and abs(at[0] - AX) > 1: s.HATCH.append(((2 * AX - at[0], at[1]), o))

# ===================================================================== UPPER DECK - COMMAND
U = Deck()
U.room("Observation Lounge", lib("malgus_11", 494, 305, w=12), "malgus_11 command hub, railing ring", feat=[ring(494, 305, 36), ring(494, 305, 15)])
U.room("Star Chart P", fit(["office", "junction", "command"], 382, 335, 7.8, 4.3), twin="Star Chart S")
U.room("Security Office", fit(["office", "quarters"], 405, 443, 5.0, 5.0), twin="Weapons Locker")
U.room("Lift A", box(440, 470, 478, 510), "lift car (the main deck's Lift A shaft)")
U.room("Officers' Quarters A", fit(["quarters"], 358, 498, 8.1, 5.7), twin="Officers' Quarters B")
U.room("War Room", fit(["junction", "office"], 428, 594, 9.7, 5.7), twin="Navigation Room")
U.room("Captain's Quarters", fit(["quarters"], 428, 676, 10.1, 8.1), twin="Captain's Office")
U.room("Lounge P", fit(["lounge", "mess", "office"], 310, 628, 7.4, 14.6), twin="Lounge S")
U.room("Comms Array", fit(["weapons", "office"], 428, 776, 10.3, 8.6), twin="Sensor Station")
U.room("Cabins A", fit(["quarters", "cabin"], 303, 776, 8.6, 13.7), twin="Cabins B")
U.room("Galley", fit(["mess"], 300, 895, 9.5, 7.0), twin="Wardroom")
U.room("Shield Control", fit(["engine", "machine"], 428, 895, 9.8, 7.4), twin="Fire Control")
U.room("Turret P", fit(["weapons"], 222, 950, 4.9, 5.8), twin="Turret S")
U.room("Gunnery Control", fit(["weapons", "command"], 494, 1000, 11.7, 6.4))
for nm, f in [("Star Chart P", lambda x, y: [ring(x, y, 9)]), ("War Room", lambda x, y: [ring(x, y, 11)]),
              ("Captain's Quarters", lambda x, y: [box(x - 16, y - 8, x + 16, y + 8)]), ("Lounge P", lambda x, y: [ring(x, y, 10)]),
              ("Shield Control", lambda x, y: [ring(x, y, 12)]), ("Galley", lambda x, y: [LineString([(x - 18, y + 10), (x + 18, y + 10)])])]:
    x, y = U.ctr(nm); U.F[nm] = f(x, y)
    if nm in U.TW: U.F[U.TW[nm]] = [M(q) for q in U.F[nm]]
# corridors: spine, junctions, branches, side corridors, the lateral turret corridor (Fury)
U.H += [hall((494, 365), (494, 950), w=24), junction(494, 410), junction(494, 545), junction(494, 845), box(478, 482, 482, 498)]
U.hall(hall((494, 545), (340, 545), w=18)); U.hall(hall((365, 545), (365, 845), w=18)); U.hall(hall((300, 845), (494, 845), w=18))
U.H.append(hall((262, 950), (726, 950), w=20))
U.hall(hall((494, 410), (362, 410), w=16))
U.R = decklib.settle(U.R, U.H, whole={"Observation Lounge", "Lift A"}, twins=U.TW, mirror_fn=M)   # (rooms meet the main corridors first; connectors after)
U.link("Star Chart P", (362, 410)); U.link("Security Office", (405, 410)); U.door(478, 490, "v", both=False)
U.door(494, 365, "h", both=False)
U.link("Officers' Quarters A", (360, 537)); U.link("War Room", (356, 595)); U.link("War Room", (482, 595))
U.link("Captain's Quarters", (482, 690)); U.link("Lounge P", (356, 620)); U.link("Comms Array", (356, 770)); U.link("Comms Array", (482, 770))
U.link("Cabins A", (356, 770)); U.link("Galley", (312, 854)); U.link("Galley", (300, 940)); U.link("Shield Control", (428, 854))
U.link("Shield Control", (428, 940)); U.link("Turret P", (262, 950)); U.link("Gunnery Control", (478, 960), both=False)
U.D = list(dict.fromkeys(U.D))
U.R = decklib.finalize(U.R, U.H, list(U.R), U.TW, M, keep={"Observation Lounge", "Lift A"})
for nm, sd, off, lab in [("Captain's Quarters", "w", -15, "locker"), ("Security Office", "w", 0, "weapon rack"),
                          ("Comms Array", "s", 0, "console"), ("Shield Control", "w", 0, "fuse box"), 
                          ("Cabins A", "w", -30, "locker"), ("Cabins A", "w", 30, "locker"), ("Lounge P", "w", 0, "med station"),
                          ("Officers' Quarters A", "w", 0, "locker"), ("Star Chart P", "n", 0, "console")]:
    U.wallniche(nm, sd, off, lab)
U.hatch((365, 690), "v"); U.hatch((494, 700), "v"); U.hatch((600, 950), "h")
SHORT = {"Observation Lounge": "Observation", "Officers' Quarters A": "Officers A", "Officers' Quarters B": "Officers B",
         "Security Office": "Security", "Weapons Locker": "Weapons", "Captain's Quarters": "Capt. Qtrs", "Captain's Office": "Capt. Office",
         "Navigation Room": "Navigation", "Comms Array": "Comms", "Sensor Station": "Sensors", "Shield Control": "Shields",
         "Fire Control": "Fire Ctrl", "Gunnery Control": "Gunnery"}
bad = decklib.run("imperium_trooptransport", HERE, SRC, AX, "upper", 1, U.R, U.H, U.D, [LIFT_A], title="UPPER DECK - COMMAND",
                  features=U.F, short=SHORT, whole={"Observation Lounge", "Lift A"}, service=SERVICE, niches=U.NICHE, hatches=U.HATCH, source=U.FROM,
                  fits=U.FIT, round_rooms={"Observation Lounge"}, lift_ok=LIFT_CHECK)
print("TOTAL FAILURES:", len(bad))

# ===================================================================== LOWER DECK - HOLD
L = Deck()
def bot(n): return round(L.R[n].bounds[3], 1)
L.room("Lift A", box(440, 470, 478, 510), "lift car (the main deck's Lift A shaft)")
L.room("Water Recycling", lib("kasparov_a_14", 562, 505, w=7.0, h=7.0), "kasparov_a_14 hyperdrive room (round machine)",
       feat=[ring(562, 505, 20), circle(562, 505, 9).exterior])
L.room("Life Support", lib("kasparov_a_14", 400, 505, w=5.8, h=5.8), "kasparov_a_14 hyperdrive room (round machine)",
       feat=[ring(400, 505, 16), circle(400, 505, 7).exterior])
L.room("Ammo P", fit(["office", "cargo"], 334, 507, 5.7, 5.9), twin="Ammo S")
L.room("Brig", fit(["corridor", "medbay"], 494, 704, 4.1, 18.0))
BX0, BY0, BX1, BY1 = [round(v, 1) for v in L.R["Brig"].bounds]
n = 4; hh = (BY1 - BY0) / n
for i in range(n):
    y = BY0 + hh * (i + 0.5)
    L.room("Cell %d" % (i + 1), fit(["cabin"], BX1 + 34, y, 6.4, hh / 10 - 0.4), feat=[box(BX1 + 42, y - 8, BX1 + 52, y + 8)])
L.room("Detention", fit(["office", "quarters"], BX0 - 36, BY0 + 2 * hh / 2 + 4, 6.8, 2 * hh / 10 - 0.6))
for i, nm in enumerate(("Cell 5", "Cell 6")):
    y = BY0 + hh * (2.5 + i)
    L.room(nm, fit(["cabin"], BX0 - 34, y, 6.4, hh / 10 - 0.4), feat=[box(BX0 - 52, y - 8, BX0 - 42, y + 8)])
L.room("Guard P", fit(["office", "quarters"], 314, 624, 6.6, 5.4, exclude=("defender_lower_04",)), twin="Guard S")
L.room("Spare Parts", fit(["machine", "cargo", "medbay"], 306, 726, 7.1, 10.4), twin="Med Store")
L.room("Drop Pods A", fit(["cargo"], 294, 876, 10.0, 13.2), twin="Drop Pods B")
L.room("Launch P", fit(["weapons", "office"], 300, 990, 6.6, 5.7), twin="Launch S")
L.room("Cargo Hold A", fit(["cargo"], 428, 968, 9.9, 20.3), twin="Cargo Hold B")
L.room("Battery", lib("kasparov_a_14", 298, 1082, w=7.6, h=7.6), "kasparov_a_14 round machine room", twin="Shield Gen",
       feat=[ring(298, 1082, 21), circle(298, 1082, 9).exterior])
L.room("Machine", fit(["machine"], 418, 1140, 5.2, 4.3), twin="Fuel")
L.room("Coolant", lib("tianjin_14", 494, 1166, w=8.0, h=8.0), "tianjin_14 round room (pump in a ring walkway)",
       feat=[ring(494, 1166, 24), circle(494, 1166, 10).exterior])
L.room("Pods", sector(494, 1166, 66, 96, 40, 140), "carrick ring corridor (arc, 3 m), pod hatches along the hull")
for nm, f in [("Guard P", lambda x, y: [ring(x, y, 7)]), ("Spare Parts", lambda x, y: [box(x - 4, y - 30, x + 4, y + 30)]),
              ("Drop Pods A", lambda x, y: [ring(x - 22, y - 33 + 22 * i, 7) for i in range(4)]),
              ("Cargo Hold A", lambda x, y: [box(x - 30, y - 70, x, y - 40), box(x - 30, y - 25, x, y + 5), box(x + 5, y + 45, x + 30, y + 70)]),
              ("Machine", lambda x, y: [ring(x, y, 7)])]:
    x, y = L.ctr(nm); L.F[nm] = f(x, y)
    if nm in L.TW: L.F[L.TW[nm]] = [M(q) for q in L.F[nm]]
# corridors
L.H += [hall((494, 460), (494, 560), w=24), hall((494, 840), (494, 1100), w=24), junction(494, 560), junction(494, 840), junction(494, 1100),
        box(478, 482, 482, 498)]
L.hall(hall((494, 560), (330, 560), w=18)); L.hall(hall((365, 560), (365, 1100), w=18)); L.hall(hall((365, 840), (494, 840), w=18))
L.hall(hall((365, 1100), (494, 1100), w=18))
WH = {"Lift A", "Water Recycling", "Life Support", "Coolant", "Battery", "Shield Gen", "Brig", "Pods"}
L.R = decklib.settle(L.R, L.H, whole=WH, twins=L.TW, mirror_fn=M)
L.door(478, 490, "v", both=False)
L.link("Water Recycling", (506, 505), both=False); L.link("Life Support", (400, 552), both=False)
L.link("Ammo P", (334, 552)); L.link("Brig", (494, 566), both=False)
for i in range(4):
    c = L.R["Cell %d" % (i + 1)].centroid; L.door(BX1, round(c.y, 1), "v", both=False)        # (the cells share the brig's wall)
for nm in ("Detention", "Cell 5", "Cell 6"):
    c = L.R[nm].centroid; L.door(BX0, round(c.y, 1), "v", both=False)
L.link("Guard P", (356, 624)); L.link("Spare Parts", (356, 726)); L.link("Drop Pods A", (356, 876)); L.link("Launch P", (356, 990))
L.link("Cargo Hold A", (374, 968)); L.link("Cargo Hold A", (482, 968)); L.link("Battery", (356, 1082)); L.link("Machine", (418, 1109))
L.link("Coolant", (494, 1109), both=False)
_pi = L.R["Pods"].intersection(LineString([(432, 1100), (432, 1300)]))   # machine shop -> escape pods (and fuel store)
_pt = round(_pi.bounds[1], 1)
L.hall(hall((432, bot("Machine")), (432, _pt), w=16).difference(L.R["Pods"]).difference(L.R["Machine"])); L.door(432, bot("Machine"), "h"); L.door(432, _pt, "h")
L.D = list(dict.fromkeys(L.D))
L.R = decklib.finalize(L.R, L.H, list(L.R), L.TW, M, keep=WH)
for nm, sd, off, lab in [("Spare Parts", "w", 0, "shelves"), ("Guard P", "n", 0, "weapon rack"), ("Detention", "w", 0, "console"),
                         ("Cargo Hold A", "n", 0, "console"), ("Drop Pods A", "n", 0, "locker"), ("Ammo P", "n", 0, "locker")]:
    L.wallniche(nm, sd, off, lab)
for a in (70, 90, 110):   # the escape pod hatches on the outer wall of the pod corridor
    L.NICHE.append(("Pods", (round(494 + 96 * math.cos(math.radians(a)), 1), round(1166 + 96 * math.sin(math.radians(a)), 1)), "s", "pod hatch"))
L.hatch((365, 780), "v"); L.hatch((494, 960), "v"); L.hatch((430, 1100), "h")
SHORT = {"Water Recycling": "Water", "Life Support": "Life Sup.", "Detention": "Detention"}
bad += decklib.run("imperium_trooptransport", HERE, SRC, AX, "lower", -1, L.R, L.H, L.D, [SHAFT], title="LOWER DECK - HOLD",
                   features=L.F, short=SHORT, whole=WH, service=SERVICE, niches=L.NICHE, hatches=L.HATCH, source=L.FROM,
                   anchor={"Pods": (494, 1247)}, fits=L.FIT, round_rooms={"Water Recycling", "Life Support", "Coolant", "Battery", "Shield Gen", "Pods"},
                   lift_ok=LIFT_CHECK)
decklib.both(os.path.join(HERE, "deck_upper.png"), os.path.join(HERE, "deck_lower.png"), os.path.join(HERE, "decks_plan.jpg"))
decklib.both(os.path.join(HERE, "deck_upper_on_map.jpg"), os.path.join(HERE, "deck_lower_on_map.jpg"), os.path.join(HERE, "decks_on_map.jpg"))
decklib.source_sheet([os.path.join(HERE, "deck_upper.json"), os.path.join(HERE, "deck_lower.json")], os.path.join(HERE, "decks_sources.jpg"))
_lu = json.load(open(os.path.join(HERE, "deck_upper.json")))["lifts"]; _ll = json.load(open(os.path.join(HERE, "deck_lower.json")))["lifts"]
print("LIFTS: upper %s  lower %s  main Lift A %s -> %s" % (_lu, _ll, list(SHAFT), "LINED UP" if _lu == _ll == [list(SHAFT)] else "FAIL"))
if not _lu == _ll == [list(SHAFT)]: bad.append("lifts not lined up between the decks")
print("TOTAL FAILURES (both decks):", len(bad))
sys.exit(1 if bad else 0)
