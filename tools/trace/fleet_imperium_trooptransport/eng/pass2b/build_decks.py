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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from planlib import hall, mirror, circle
import decklib_p2a as decklib
from decklib_p2a import lib
from shapely.geometry import Polygon, LineString, box

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "source.jpg")
AX = 494.0
M = mirror(AX)
LIFT_A, LIFT_B = (459, 490), (529, 490)
SERVICE = ["conduit", "duct", "power trunk", "coolant loop", "crawlspace", "machinery", "structure", "wiring run", "fuse bay"]

def ring(cx, cy, r): return circle(cx, cy, r).exterior
def arc(cx, cy, r, a0, a1, n=24):
    return LineString([(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)])
def sector(cx, cy, r0, r1, a0, a1):
    return Polygon(list(arc(cx, cy, r1, a0, a1).coords) + list(arc(cx, cy, r0, a1, a0).coords))
def junction(cx, cy, d=4.6): return lib("tianjin_10", cx, cy, w=d, h=d)        # a small octagonal junction room (Tianjin lift hall)

class Deck:
    """Rooms, halls, doors and the 'which traced room' record of one deck; port side mirrored to starboard."""
    def __init__(s): s.R, s.H, s.D, s.FROM, s.F, s.NICHE, s.HATCH, s.TW = {}, [], [], {}, {}, [], [], {}
    def room(s, name, g, src, twin=None, feat=()):
        s.R[name] = g; s.FROM[name] = src; s.F[name] = list(feat)
        if twin:
            s.R[twin] = M(g); s.FROM[twin] = src + " (mirrored)"; s.F[twin] = [M(f) for f in feat]; s.TW[name] = twin
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
        if not pts: raise SystemExit("link %s -> %s: the connector misses the room" % (name, to))
        if horiz:
            px = round(min(pts, key=lambda p: abs(p.x - tx)).x, 1)
            s.hall(hall((px, ty), (tx, ty), w=w).difference(g), both); s.door(px, ty, "v", both)   # (ends on the room's own wall, curved or not)
        else:
            py = round(min(pts, key=lambda p: abs(p.y - ty)).y, 1)
            s.hall(hall((tx, py), (tx, ty), w=w).difference(g), both); s.door(tx, py, "h", both)
    def niche(s, name, at, side, lab, both=True):
        s.NICHE.append((name, at, side, lab))
        if both and name in s.TW: s.NICHE.append((s.TW[name], (2 * AX - at[0], at[1]), {"e": "w", "w": "e"}.get(side, side), lab))
    def wallniche(s, name, side, off, lab, both=True):
        """An equipment niche cut into the room's thick wall on side n/s/e/w, `off` px from the room's centre line."""
        g = s.R[name]; c = g.centroid; x0, y0, x1, y1 = g.bounds
        if side in "ns":
            ray = LineString([(c.x + off, c.y), (c.x + off, y0 - 1 if side == "n" else y1 + 1)])
        else:
            ray = LineString([(c.x, c.y + off), (x0 - 1 if side == "w" else x1 + 1, c.y + off)])
        hit = g.exterior.intersection(ray)
        pts = [p for p in getattr(hit, "geoms", [hit]) if p.geom_type == "Point"]
        far = max(pts, key=lambda p: p.distance(c))
        s.niche(name, (round(far.x, 1), round(far.y, 1)), side, lab, both)
    def hatch(s, at, o, both=True):
        s.HATCH.append((at, o))
        if both and abs(at[0] - AX) > 1: s.HATCH.append(((2 * AX - at[0], at[1]), o))

# ===================================================================== UPPER DECK - COMMAND
U = Deck()
def C(name): return U.R[name].centroid
U.room("Observation Lounge", lib("malgus_11", 494, 305, w=12), "malgus_11 command hub, railing ring",
       feat=[ring(494, 305, 36), ring(494, 305, 15)])
U.room("Star Chart P", lib("tianjin_09", 382, 335, w=8.2, h=4.6, rot=90), "tianjin_09 long room", "Star Chart S", [ring(382, 335, 10)])
U.room("Security Office", lib("fury_08", 400, 443, w=6.6, h=4.8), "fury_08 secondary quarters (angled)", "Weapons Locker")
U.room("Lift B", box(510, 470, 548, 510), "lift car (main deck Lift B shaft: one shaft, all three decks)")
U.room("Officers' Quarters A", lib("fury_04", 360, 498, w=8.6, h=6.0, flip=True), "fury_04 captain's quarters", "Officers' Quarters B",
       [box(340, 492, 372, 506)])
U.room("War Room", lib("kasparov_a_09", 428, 594, w=10.2, h=6.0), "kasparov_a_09 central hall (chamfered)", "Navigation Room", [ring(428, 592, 11)])
U.room("Captain's Quarters", lib("fury_05", 428, 676, w=10.0, h=8.0), "fury_05 crew quarters (L)", "Captain's Office", [box(408, 662, 442, 680)])
U.room("Lounge P", lib("fury_06", 310, 628, w=7.6, h=14.6, rot=90), "fury_06 lounge + holoterminal", "Lounge S", [ring(318, 620, 10)])
U.room("Comms Array", lib("tianjin_05", 428, 776, w=10.2, h=8.6), "tianjin_05 comms / gun deck (tapered)", "Sensor Station")
U.room("Cabins A", lib("kasparov_b_03", 303, 776, w=8.6, h=13.8, rot=90), "kasparov_b_03 passenger quarters", "Cabins B",
       [LineString([(292, 740), (330, 740)]), LineString([(292, 770), (330, 770)]), LineString([(292, 800), (330, 800)])])
U.room("Galley", lib("tianjin_01", 300, 895, w=10.0, h=7.6, flip=True), "tianjin_01 galley (quarter round)", "Wardroom", [LineString([(280, 905), (320, 905)])])
U.room("Shield Control", lib("fury_12", 428, 895, w=10.4, h=7.8), "fury_12 engine room round a machine", "Fire Control", [ring(428, 895, 12)])
U.room("Turret P", lib("fury_09", 240, 950, w=4.0, h=5.0), "fury_09 turret hatch", "Turret S")
U.room("Gunnery Control", lib("tianjin_26", 494, 999, w=12.4, h=6.6, rot=90), "tianjin_26 gunnery (tapered)", feat=[ring(524, 1003, 7), ring(464, 1003, 7)])
# corridors: spine, junctions, branches, side corridors, the lateral turret corridor (Fury)
U.H += [hall((494, 365), (494, 950), w=24), junction(494, 410), junction(494, 545), junction(494, 845), box(506, 482, 510, 498)]
U.hall(hall((494, 545), (340, 545), w=18)); U.hall(hall((365, 545), (365, 845), w=18)); U.hall(hall((300, 845), (494, 845), w=18))
U.H.append(hall((262, 950), (726, 950), w=20))
U.hall(hall((494, 410), (385, 410), w=16))
U.link("Star Chart P", (385, 410)); U.link("Security Office", (400, 410)); U.door(510, 490, "v", both=False)
U.door(494, 365, "h", both=False)
U.link("Officers' Quarters A", (360, 537)); U.link("War Room", (356, 595)); U.link("War Room", (482, 595))
U.link("Captain's Quarters", (482, 690)); U.link("Lounge P", (356, 620)); U.link("Comms Array", (356, 770)); U.link("Comms Array", (482, 770))
U.link("Cabins A", (356, 770)); U.link("Galley", (312, 854)); U.link("Galley", (300, 940)); U.link("Shield Control", (428, 854))
U.link("Shield Control", (428, 940)); U.door(262, 950, "v"); U.link("Gunnery Control", (478, 960), both=False)
U.D = list(dict.fromkeys(U.D))
U.R = decklib.settle(U.R, U.H, whole={"Observation Lounge", "Lift B", "Gunnery Control"})
for nm, sd, off, lab in [("Captain's Quarters", "w", -15, "locker"),
                          ("Comms Array", "s", 0, "panel"), ("Shield Control", "w", 0, "fuse box"), 
                          ("Cabins A", "w", -30, "locker"), ("Cabins A", "w", 30, "locker"), ("Lounge P", "w", 0, "med station"),
                          ("Officers' Quarters A", "w", 0, "locker"), ("Star Chart P", "n", 0, "console")]:
    U.wallniche(nm, sd, off, lab)
U.hatch((365, 690), "v"); U.hatch((494, 700), "v"); U.hatch((600, 950), "h")
SHORT = {"Observation Lounge": "Observation", "Officers' Quarters A": "Officers A", "Officers' Quarters B": "Officers B",
         "Security Office": "Security", "Weapons Locker": "Weapons", "Captain's Quarters": "Capt. Qtrs", "Captain's Office": "Capt. Office",
         "Navigation Room": "Navigation", "Comms Array": "Comms", "Sensor Station": "Sensors", "Shield Control": "Shields",
         "Fire Control": "Fire Ctrl", "Gunnery Control": "Gunnery"}
bad = decklib.run("imperium_trooptransport", HERE, SRC, AX, "upper", 1, U.R, U.H, U.D, [LIFT_B], title="UPPER DECK - COMMAND",
                  features=U.F, short=SHORT, whole={"Observation Lounge", "Lift B", "Gunnery Control"}, service=SERVICE, niches=U.NICHE, hatches=U.HATCH, source=U.FROM)
print("TOTAL FAILURES:", len(bad))

# ===================================================================== LOWER DECK - HOLD
L = Deck()
U_ = U
def bot(n): return round(L.R[n].bounds[3], 1)
L.room("Lift B", box(510, 470, 548, 510), "lift car (main deck shaft)")
L.room("Water Recycling", lib("kasparov_a_14", 418, 500, w=7.6, h=7.6), "kasparov_a_14 hyperdrive room (round machine)",
       feat=[ring(420, 500, 20), circle(420, 500, 9).exterior])
L.room("Life Support", lib("kasparov_a_14", 600, 516, w=6.0, h=6.0), "kasparov_a_14 hyperdrive room (round machine)",
       feat=[ring(600, 516, 16), circle(600, 516, 8).exterior])
L.room("Ammo P", lib("kasparov_b_07", 336, 507, w=6.0, h=6.2, flip=True), "kasparov_b_07 storage & lockers (wedge)", "Ammo S")
L.room("Brig", lib("kasparov_a_05", 494, 702, w=4.4, h=21.0), "kasparov_a_05 infirmary (long) as the cell corridor")
BX0, BX1 = round(L.R["Brig"].bounds[0], 1), round(L.R["Brig"].bounds[2], 1)
for i, y in enumerate((622, 676, 730, 784)):
    L.room("Cell %d" % (i + 1), lib("kasparov_a_12", BX1 + 32, y, w=6.4, h=5.2), "kasparov_a_12 cabin", feat=[box(BX1 + 34, y - 12, BX1 + 44, y + 12)])
L.room("Detention", lib("fury_08", BX0 - 34, 632, w=6.8, h=7.4, flip=True), "fury_08 secondary quarters (angled)")
L.room("Cell 5", lib("kasparov_a_12", BX0 - 32, 716, w=6.4, h=5.2), "kasparov_a_12 cabin", feat=[box(BX0 - 44, 702, BX0 - 34, 726)])
L.room("Cell 6", lib("kasparov_a_12", BX0 - 32, 770, w=6.4, h=5.2), "kasparov_a_12 cabin", feat=[box(BX0 - 44, 756, BX0 - 34, 780)])
L.room("Guard P", lib("defender_lower_04", 316, 622, w=7.0, h=5.6), "defender_lower_04 central access chamber", "Guard S", [ring(318, 618, 7)])
L.room("Spare Parts", lib("kasparov_a_08", 308, 724, w=7.6, h=11.0), "kasparov_a_08 machine shop (angled)", "Med Store",
       [box(292, 690, 300, 750)])
L.room("Drop Pods A", lib("fury_01", 296, 874, w=10.6, h=14.0, flip=True), "fury_01 cargo hold", "Drop Pods B",
       [ring(278, 840 + 22 * i, 7) for i in range(4)])
L.room("Pod Launch P", lib("tianjin_06", 303, 990, w=7.0, h=6.0), "tianjin_06 tapered room", "Pod Launch S")
L.room("Cargo Hold A", lib("kasparov_b_11", 428, 968, w=10.4, h=21.4), "kasparov_b_11 cargo bay", "Cargo Hold B",
       [box(395, 885, 425, 915), box(395, 930, 425, 960), box(440, 1010, 465, 1035)])
L.room("Battery", lib("kasparov_a_14", 298, 1082, w=7.6, h=7.6), "kasparov_a_14 round machine room", "Shield Gen",
       [ring(298, 1082, 21), circle(298, 1082, 9).exterior])
L.room("Machine", lib("kasparov_a_08", 420, 1140, w=5.8, h=4.8, rot=90), "kasparov_a_08 machine shop (angled)", "Fuel", [ring(420, 1140, 7)])
L.room("Coolant", lib("tianjin_14", 494, 1168, w=8.0, h=8.0), "tianjin_14 round room (pump in a ring walkway)",
       feat=[ring(494, 1168, 24), circle(494, 1168, 10).exterior])
L.room("Pods", sector(494, 1170, 70, 92, 38, 142), "carrick ring corridor (arc), pod hatches along the hull",
       feat=[box(494 + 82 * math.cos(math.radians(a)) - 4, 1170 + 82 * math.sin(math.radians(a)) - 4, 494 + 82 * math.cos(math.radians(a)) + 4, 1170 + 82 * math.sin(math.radians(a)) + 4) for a in (55, 75, 105, 125)])
# corridors
L.H += [hall((494, 460), (494, 560), w=24), hall((494, 840), (494, 1100), w=24), junction(494, 560), junction(494, 840), junction(494, 1100),
        box(506, 482, 510, 498)]
L.hall(hall((494, 560), (330, 560), w=18)); L.hall(hall((365, 560), (365, 1100), w=18)); L.hall(hall((365, 840), (494, 840), w=18))
L.hall(hall((365, 1100), (494, 1100), w=18))
L.door(510, 490, "v", both=False)
L.link("Water Recycling", (482, 500), both=False); L.link("Life Support", (506, 528), both=False)
L.link("Ammo P", (336, 552)); L.link("Brig", (494, 566), both=False)
for i, y in enumerate((622, 676, 730, 784)):
    L.door(BX1, y, "v", both=False)        # (the cells share the brig's wall)
for n, y in (("Detention", 632), ("Cell 5", 716), ("Cell 6", 770)):
    L.door(BX0, y, "v", both=False)
L.link("Guard P", (356, 622)); L.link("Spare Parts", (356, 722)); L.link("Drop Pods A", (356, 872)); L.link("Pod Launch P", (356, 990))
L.link("Cargo Hold A", (374, 965)); L.link("Cargo Hold A", (482, 965)); L.link("Battery", (356, 1082)); L.link("Machine", (420, 1109))
L.link("Coolant", (494, 1109), both=False)
_pi = L.R["Pods"].intersection(LineString([(425, 1100), (425, 1300)]))   # machine shop -> escape pods
_pt = round(_pi.bounds[1], 1) if not _pi.is_empty else None
if _pt is None: raise SystemExit("pods: no wall at x 425")
L.hall(hall((425, bot("Machine")), (425, _pt), w=16).difference(L.R["Pods"])); L.door(425, bot("Machine"), "h"); L.door(425, _pt, "h")
L.D = list(dict.fromkeys(L.D))
WH = {"Lift B", "Water Recycling", "Life Support", "Coolant", "Battery", "Shield Gen", "Brig", "Pods"}
L.R = decklib.settle(L.R, L.H, whole=WH)
for nm, sd, off, lab in [("Spare Parts", "w", 0, "shelves"), ("Guard P", "w", 0, "weapon rack"), ("Detention", "w", 0, "console"),
                         ("Cargo Hold A", "n", 0, "panel"), ("Drop Pods A", "n", 0, "locker"), ("Ammo P", "n", 0, "locker")]:
    L.wallniche(nm, sd, off, lab)
L.hatch((365, 780), "v"); L.hatch((494, 960), "v"); L.hatch((430, 1100), "h")
SHORT = {"Water Recycling": "Water", "Life Support": "Life Sup.", "Pod Launch P": "Launch P", "Pod Launch S": "Launch S",
         "Drop Pods A": "Drop Pods A", "Detention": "Detention"}
bad += decklib.run("imperium_trooptransport", HERE, SRC, AX, "lower", -1, L.R, L.H, L.D, [LIFT_B], title="LOWER DECK - HOLD",
                   features=L.F, short=SHORT, whole=WH, service=SERVICE, niches=L.NICHE, hatches=L.HATCH, source=L.FROM,
                   anchor={"Pods": (494, 1251)})
decklib.both(os.path.join(HERE, "deck_upper.png"), os.path.join(HERE, "deck_lower.png"), os.path.join(HERE, "decks_plan.jpg"))
decklib.both(os.path.join(HERE, "deck_upper_on_map.jpg"), os.path.join(HERE, "deck_lower_on_map.jpg"), os.path.join(HERE, "decks_on_map.jpg"))
decklib.source_sheet([os.path.join(HERE, "deck_upper.json"), os.path.join(HERE, "deck_lower.json")], os.path.join(HERE, "decks_sources.jpg"))
print("TOTAL FAILURES (both decks):", len(bad))
sys.exit(1 if bad else 0)
