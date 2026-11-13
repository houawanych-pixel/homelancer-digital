#!/usr/bin/env python3
"""Covenant Cruiser: PROPOSED upper (command) and lower (hold) decks in the owner-preferred pass 2a style (traced
rooms from tools/trace/shape_library.json picked by function, service space, spine with junction rooms, niches,
hatches), centre mass in the narrow hull body and the wing roots, mirrored about x 591. Both decks stop at ONE lift
shaft: the main deck's Lift (port), (568, 485). decklib.check() runs on both."""
import json, math, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import hall, circle
import decklib
from decklib import lib, Deck
from shapely.geometry import Polygon, LineString, box, shape

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "source.jpg")
SID, AX = "covenant_cruiser", 591.0
SHAFT = (568, 485)
LIFT = box(553, 470, 583, 500)
SERVICE = ["conduit", "duct", "power trunk", "coolant loop", "crawlspace", "machinery", "structure", "wiring run", "fuse bay"]
def ring(cx, cy, r): return circle(cx, cy, r).exterior
def junction(cx, cy, d=4.4): return lib("tianjin_10", cx, cy, w=d, h=d)
def arc(cx, cy, r, a0, a1, n=24):
    return LineString([(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)])
def sector(cx, cy, r0, r1, a0, a1):
    return Polygon(list(arc(cx, cy, r1, a0, a1).coords) + list(arc(cx, cy, r0, a1, a0).coords))
_MAIN = json.load(open(os.path.join(HERE, "plan.json")))
LIFT_CHECK = [] if shape(_MAIN["rooms"]["Lift (port)"]).buffer(1).contains(LIFT) else ["the shaft is not the main deck's Lift (port)"]
CHECKS = dict(service=SERVICE, lift_ok=LIFT_CHECK, outline_style="ring")
def spine(y0, y1):   # (2.2 m, narrowed to 1.6 m past the lift so the lift car meets it)
    return [hall((591, y0), (591, 462), w=22), hall((591, 462), (591, 508), w=16), hall((591, 508), (591, y1), w=22)]

# ===================================================================== UPPER DECK - COMMAND
U = Deck(AX); M = U.M
U.room("Observation Dome", lib("malgus_11", 591, 272, w=8.4), "malgus_11 command hub, railing ring", feat=[ring(591, 272, 24), ring(591, 272, 10)])
U.room("Lift", LIFT, "lift car (the main deck's Lift (port) shaft)")
U.room("Navigation", lib("kasparov_a_03", 538, 360, w=5.8, h=6.3), "kasparov_a_03 ops (round alcove)", twin="Sensors")
U.room("Security Office", lib("fury_08", 532, 425, w=5.6, h=4.8), "fury_08 secondary quarters (angled)", twin="Weapons Locker")
U.room("Captain's Quarters", lib("fury_04", 523, 540, w=8.6, h=6.0, flip=True), "fury_04 captain's quarters", twin="First Officer")
U.room("War Room", lib("kasparov_a_09", 530, 612, w=9.7, h=5.2), "kasparov_a_09 central hall (chamfered)", twin="Fleet Ops")
U.room("Lounge P", lib("fury_06", 500, 700, w=13.0, h=4.5), "fury_06 lounge + holoterminal", twin="Lounge S")
U.room("Cabins A", lib("kasparov_b_03", 490, 770, w=10.4, h=6.3), "kasparov_b_03 passenger quarters", twin="Cabins B")
U.room("Gym", lib("kasparov_b_06", 362, 742, w=6.4, h=6.4), "kasparov_b_06 round room", twin="Chapel")
U.room("Officers' Mess", lib("kasparov_b_06", 591, 860, w=7.4, h=7.4), "kasparov_b_06 dining area (round)")
U.room("Galley", lib("tianjin_01", 515, 862, w=6.9, h=7.3, flip=True), "tianjin_01 galley (quarter round)", twin="Wardroom")
U.room("Gunnery Control", lib("tianjin_26", 591, 957, w=9.1, h=7.6, rot=90), "tianjin_26 gunnery (tapered)")
U.H += spine(314, 790) + [junction(591, 380), junction(591, 560), junction(591, 740), junction(591, 790)]
U.hall(hall((591, 740), (397, 740), w=18))
WHU = {"Observation Dome", "Lift", "Officers' Mess", "Gym", "Chapel"}
U.R = decklib.settle(U.R, U.H, whole=WHU, twins=U.TW, mirror_fn=M, mode="close")
U.door(591, 314, "h", both=False); U.door(583, 485, "v", both=False)
U.link("Navigation", (580, 360)); U.link("Security Office", (580, 425)); U.link("Captain's Quarters", (580, 540)); U.link("War Room", (580, 610))
U.link("Lounge P", (500, 731)); U.link("Gym", (405, 740)); U.link("Cabins A", (490, 749)); U.link("Officers' Mess", (591, 800), both=False)
U.link("Galley", (554, 860))
_g = U.R["Gunnery Control"]; _m = U.R["Officers' Mess"]
_gt = _g.intersection(LineString([(575, 800), (575, 1100)])).bounds[1]; _mb = _m.intersection(LineString([(575, 800), (575, 1100)])).bounds[3]
U.H.append(hall((575, _mb), (575, _gt), w=16).difference(_g).difference(_m)); U.door(575, round(_mb, 1), "h", both=False); U.door(575, round(_gt, 1), "h", both=False)
U.R = decklib.finalize(U.R, U.H, list(U.R), U.TW, M, keep=WHU)
U.D = list(dict.fromkeys(U.D))
for nm, f in [("War Room", lambda x, y: [ring(x, y, 9)]), ("Officers' Mess", lambda x, y: [ring(x, y, 14)]),
              ("Captain's Quarters", lambda x, y: [box(x - 14, y - 7, x + 14, y + 7)]), ("Lounge P", lambda x, y: [ring(x, y, 8)]),
              ("Navigation", lambda x, y: [ring(x, y, 8)])]:
    U.feat(nm, f(*U.ctr(nm)))
for nm, sd, off, lab in [("Captain's Quarters", "w", 0, "locker"), ("Security Office", "w", 0, "weapon rack"), ("Cabins A", "w", 0, "locker"),
                         ("Lounge P", "n", 0, "med station"), ("Galley", "w", 0, "fuse box"), ("War Room", "w", 0, "console")]:
    U.wallniche(nm, sd, off, lab)
U.hatch((591, 680), "v"); U.hatch((480, 740), "h")
SHORT = {"Observation Dome": "Observation", "Captain's Quarters": "Captain", "First Officer": "1st Officer", "Security Office": "Security",
         "Weapons Locker": "Weapons", "Officers' Mess": "Mess", "Gunnery Control": "Gunnery"}
bad = decklib.run(SID, HERE, SRC, AX, "upper", 1, U.R, U.H, U.D, [SHAFT], title="UPPER DECK - COMMAND", features=U.F, short=SHORT,
                  whole=WHU, niches=U.NICHE, hatches=U.HATCH, source=U.FROM, fits=U.FIT, round_rooms={"Observation Dome", "Officers' Mess", "Gym", "Chapel"}, **CHECKS)

# ===================================================================== LOWER DECK - HOLD
L = Deck(AX)
L.room("Lift", LIFT, "lift car (the main deck's Lift (port) shaft)")
L.room("Life Support", lib("kasparov_a_14", 510, 507, w=6.4, h=6.4), "kasparov_a_14 round machine room", twin="Water Recycling",
       feat=[ring(515, 505, 15), circle(515, 505, 6).exterior])
L.room("Brig", lib("malgus_07", 591, 647, w=3.8, h=11.4, rot=90), "malgus_07 entry corridor as the cell corridor")
BX0, BY0, BX1, BY1 = [round(v, 1) for v in L.R["Brig"].bounds]
hh = (BY1 - BY0) / 3
for i in range(3):
    y = BY0 + hh * (i + 0.5)
    L.room("Cell %d" % (i + 1), lib("kasparov_b_01", BX0 - 36, y, w=7.2, h=hh / 10), "kasparov_b_01 cabin", twin=["Detention", "Cell 4", "Cell 5"][i],
           feat=[box(BX0 - 56, y - 7, BX0 - 46, y + 7)])
L.room("Cargo Hold A", lib("kasparov_b_11", 440, 696, w=8.2, h=5.8, rot=90), "kasparov_b_11 cargo bay", twin="Cargo Hold B")
L.room("Torpedo Store P", lib("fury_01", 368, 762, w=8.6, h=6.0, rot=90), "fury_01 cargo hold", twin="Torpedo Store S")
L.room("Shield Gen P", lib("kasparov_a_14", 512, 816, w=8.4, h=8.4), "kasparov_a_14 round machine room", twin="Shield Gen S",
       feat=[ring(520, 810, 18), circle(520, 810, 8).exterior])
L.room("Machine Shop", lib("tianjin_29", 516, 886, w=8.2, h=5.4), "tianjin_29 machineshop", twin="Fuel Store")
L.room("Coolant Pumps", circle(591, 982, 38), "tianjin_14 round room (pump in a ring walkway), drawn true round", feat=[ring(591, 982, 22), circle(591, 982, 9).exterior])
L.room("Battery P", lib("kasparov_a_14", 536, 1036, w=5.8, h=5.8), "kasparov_a_14 round machine room", twin="Battery S",
       feat=[ring(540, 1040, 13), circle(540, 1040, 5).exterior])
L.room("Escape Pods", sector(591, 1060, 52, 82, 45, 135), "carrick ring corridor (arc, 3 m), pod hatches along the hull")
L.H += spine(460, 572)[:2] + [hall((591, 508), (591, 572), w=22), hall((591, 740), (591, 920), w=22), junction(591, 570, 4.0), junction(591, 740), junction(591, 920), box(583, 482, 586, 498), hall((566, 1060), (616, 1060), w=16)]
L.hall(hall((591, 570), (488, 570), w=18)); L.hall(hall((488, 570), (488, 740), w=18)); L.hall(hall((591, 740), (410, 740), w=18))
WHL = {"Lift", "Life Support", "Water Recycling", "Brig", "Shield Gen P", "Shield Gen S", "Coolant Pumps", "Battery P", "Battery S", "Escape Pods"}
L.R = decklib.settle(L.R, L.H, whole=WHL, twins=L.TW, mirror_fn=L.M, mode="close")
L.door(583, 485, "v", both=False)
L.link("Life Support", (513, 563)); L.door(591, BY0, "h", both=False)
for nm in ("Cell 1", "Cell 2", "Cell 3"): L.door(BX0, round(L.R[nm].centroid.y, 1), "v")
L.link("Cargo Hold A", (479, 696)); L.link("Shield Gen P", (520, 749)); L.link("Torpedo Store P", (420, 749)); L.link("Machine Shop", (580, 880))
def vlink(a, b, x):   # a connector straight down between two rooms (doors on both walls)
    ra, rb = L.R[a], L.R[b]
    ya = ra.intersection(LineString([(x, 0), (x, 2000)])).bounds[3]; yb = rb.intersection(LineString([(x, 0), (x, 2000)])).bounds[1]
    L.H.append(hall((x, ya), (x, yb), w=16).difference(ra).difference(rb)); L.door(x, round(ya, 1), "h", both=False); L.door(x, round(yb, 1), "h", both=False)
_ct = L.R["Coolant Pumps"].bounds[1]
L.H.append(hall((591, 929), (591, _ct), w=16).difference(L.R["Coolant Pumps"])); L.door(591, round(_ct, 1), "h", both=False)
_cb = L.R["Coolant Pumps"].bounds[3]
L.H.append(hall((591, _cb), (591, 1052), w=16).difference(L.R["Coolant Pumps"])); L.door(591, round(_cb, 1), "h", both=False)
_pt = L.R["Escape Pods"].intersection(LineString([(591, 1000), (591, 1300)])).bounds[1]
L.H.append(hall((591, 1068), (591, _pt), w=16).difference(L.R["Escape Pods"])); L.door(591, round(_pt, 1), "h", both=False)
L.link("Battery P", (566, 1060))
L.R = decklib.finalize(L.R, L.H, list(L.R), L.TW, L.M, keep=WHL)
L.D = list(dict.fromkeys(L.D))
for nm, f in [("Cargo Hold A", lambda x, y: [box(x - 30, y - 12, x - 6, y + 12), box(x + 6, y - 12, x + 30, y + 12)]),
              ("Machine Shop", lambda x, y: [ring(x, y, 6)])]:
    L.feat(nm, f(*L.ctr(nm)))
for nm, sd, off, lab in [("Cargo Hold A", "n", 0, "console"), ("Machine Shop", "w", 0, "fuse box")]:
    L.wallniche(nm, sd, off, lab)
for a in (70, 90, 110):
    L.NICHE.append(("Escape Pods", (round(591 + 82 * math.cos(math.radians(a)), 1), round(1060 + 82 * math.sin(math.radians(a)), 1)), "s", "pod hatch"))
L.hatch((591, 660), "v"); L.hatch((591, 860), "v")
SHORT = {"Life Support": "Life Sup.", "Water Recycling": "Water", "Coolant Pumps": "Coolant", "Escape Pods": "Pods", "Machine Shop": "Machine",
         "Shield Gen P": "Shield P", "Shield Gen S": "Shield S"}
bad += decklib.run(SID, HERE, SRC, AX, "lower", -1, L.R, L.H, L.D, [SHAFT], title="LOWER DECK - HOLD", features=L.F, short=SHORT,
                   whole=WHL, niches=L.NICHE, hatches=L.HATCH, source=L.FROM, fits=L.FIT, anchor={"Escape Pods": (591, 1128)},
                   round_rooms={"Life Support", "Water Recycling", "Shield Gen P", "Shield Gen S", "Coolant Pumps", "Battery P", "Battery S", "Escape Pods"},
                   **dict(CHECKS, outline_style="close"))
decklib.both(os.path.join(HERE, "deck_upper.png"), os.path.join(HERE, "deck_lower.png"), os.path.join(HERE, "decks_plan.jpg"))
decklib.both(os.path.join(HERE, "deck_upper_on_map.jpg"), os.path.join(HERE, "deck_lower_on_map.jpg"), os.path.join(HERE, "decks_on_map.jpg"))
decklib.source_sheet([os.path.join(HERE, "deck_upper.json"), os.path.join(HERE, "deck_lower.json")], os.path.join(HERE, "decks_sources.jpg"))
print("TOTAL FAILURES (both decks):", len(bad))
sys.exit(1 if bad else 0)
