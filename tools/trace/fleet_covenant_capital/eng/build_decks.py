#!/usr/bin/env python3
"""Covenant Capital Ship: PROPOSED upper (FLAG / COMMAND) deck and lower (HOLD) deck, composed in the owner-preferred
"pass 2a" style of the Troop Transport (traced rooms from tools/trace/shape_library.json picked by hand by function,
service space between them, a spine with junction rooms and side corridors, niches on the room side, maintenance
hatches), centre mass in the hull body between the crescent wings, mirrored about x 527.
Both decks stop at ONE lift shaft: the main deck's Lift (port), (481, 490). decklib.check() runs on both decks.
Walls 0.4 m, doors 1.6 m, corridors 1.6-2.4 m, 10 px = 1 m."""
import math, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import hall, circle
import decklib
from decklib import lib, Deck
from shapely.geometry import Polygon, LineString, box

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "source.jpg")
SID, AX = "covenant_capital", 527.0
SHAFT = (481, 490)
LIFT = box(467, 476, 495, 504)       # the main deck's Lift (port), same spot on every deck
SERVICE = ["conduit", "duct", "power trunk", "coolant loop", "crawlspace", "machinery", "structure", "wiring run", "fuse bay"]
def ring(cx, cy, r): return circle(cx, cy, r).exterior
def junction(cx, cy, d=4.6): return lib("tianjin_10", cx, cy, w=d, h=d)
def arc(cx, cy, r, a0, a1, n=24):
    return LineString([(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)])
def sector(cx, cy, r0, r1, a0, a1):
    return Polygon(list(arc(cx, cy, r1, a0, a1).coords) + list(arc(cx, cy, r0, a1, a0).coords))
from shapely.geometry import shape as _shape
import json
_MAIN = json.load(open(os.path.join(HERE, "plan.json")))
LIFT_CHECK = [] if _shape(_MAIN["rooms"]["Lift (port)"]).buffer(1).contains(LIFT) else ["the shaft is not the main deck's Lift (port)"]
CHECKS = dict(service=SERVICE, lift_ok=LIFT_CHECK, outline_style="ring")

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
bad = decklib.run(SID, HERE, SRC, AX, "upper", 1, U.R, U.H, U.D, [SHAFT], title="UPPER DECK - FLAG / COMMAND", features=U.F, short=SHORT,
                  whole={"Observation Dome", "Lift"}, niches=U.NICHE, hatches=U.HATCH, source=U.FROM, fits=U.FIT,
                  round_rooms={"Observation Dome", "Flag Holo Room", "Comms Center", "Officers' Mess", "Wardroom"}, **CHECKS)

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
bad += decklib.run(SID, HERE, SRC, AX, "lower", -1, L.R, L.H, L.D, [SHAFT], title="LOWER DECK - HOLD", features=L.F, short=SHORT,
                   whole=WH, niches=L.NICHE, hatches=L.HATCH, source=L.FROM, fits=L.FIT, anchor={"Escape Pods": (527, 1146)},
                   round_rooms={"Life Support", "Water Recycling", "Shield Gen P", "Shield Gen S", "Coolant Pumps", "Escape Pods", "Battery P", "Battery S"}, **CHECKS)
decklib.both(os.path.join(HERE, "deck_upper.png"), os.path.join(HERE, "deck_lower.png"), os.path.join(HERE, "decks_plan.jpg"))
decklib.both(os.path.join(HERE, "deck_upper_on_map.jpg"), os.path.join(HERE, "deck_lower_on_map.jpg"), os.path.join(HERE, "decks_on_map.jpg"))
decklib.source_sheet([os.path.join(HERE, "deck_upper.json"), os.path.join(HERE, "deck_lower.json")], os.path.join(HERE, "decks_sources.jpg"))
print("TOTAL FAILURES (both decks):", len(bad))
sys.exit(1 if bad else 0)
