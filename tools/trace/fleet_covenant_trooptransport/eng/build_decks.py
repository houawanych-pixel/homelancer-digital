#!/usr/bin/env python3
"""RETIRED v13.119 (class rule v13.118: this class has the main deck only). Kept for reference, outputs removed.
Covenant Troop Transport: PROPOSED upper (troop berths) and lower (hold) decks in the owner-preferred pass 2a style (traced
rooms from tools/trace/shape_library.json picked by function, service space, spine with junction rooms, niches,
hatches), centre mass in the narrow hull body and the wing roots, mirrored about x 512. Both decks stop at ONE lift
shaft: the main deck's Lift (port), (444, 517), joined to the spine by a short corridor. decklib.check() runs on both."""
import json, math, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import hall, circle
import decklib
from decklib import lib, Deck
from shapely.geometry import Polygon, LineString, box, shape

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "source.jpg")
SID, AX = "covenant_trooptransport", 512.0
SHAFT = (444, 517)
LIFT = box(430, 503, 458, 531)
LIFTJ = hall((458, 517), (505, 517), w=16)   # (lift door -> spine)
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
def spine(y0, y1):   # (2.2 m) + the short corridor to the lift
    return [hall((512, y0), (512, y1), w=22), LIFTJ]

# ===================================================================== UPPER DECK - TROOP BERTHS
U = Deck(AX); M = U.M
U.room("Drop Control", lib("malgus_11", 512, 252, w=8.4), "malgus_11 command hub, railing ring", feat=[ring(512, 252, 24), ring(512, 252, 10)])
U.room("Lift", LIFT, "lift car (the main deck's Lift (port) shaft)")
U.room("Comms", lib("kasparov_a_03", 452, 340, w=6.4, h=6.4), "kasparov_a_03 ops (round alcove)", twin="Sensors")
U.room("Officers' Quarters", lib("fury_04", 440, 432, w=9.4, h=6.4, flip=True), "fury_04 captain's quarters", twin="Sergeants' Quarters")
U.room("Barracks A", lib("kasparov_b_03", 432, 590, w=11.6, h=7.2), "kasparov_b_03 passenger quarters (bunk rows)", twin="Barracks B")
U.room("Barracks C", lib("kasparov_b_03", 432, 678, w=11.6, h=7.2), "kasparov_b_03 passenger quarters (bunk rows)", twin="Barracks D")
U.room("Barracks E", lib("kasparov_b_03", 432, 766, w=11.6, h=7.2), "kasparov_b_03 passenger quarters (bunk rows)", twin="Barracks F")
U.room("Troop Mess", lib("kasparov_b_06", 512, 900, w=8.0, h=8.0), "kasparov_b_06 dining area (round)")
U.room("Galley", lib("tianjin_01", 432, 902, w=6.9, h=7.3, flip=True), "tianjin_01 galley (quarter round)", twin="Rec Room")
U.room("Ready Room", lib("tianjin_26", 512, 1002, w=9.1, h=7.6, rot=90), "tianjin_26 gunnery (tapered) as the squad ready room")
U.H += spine(294, 830) + [junction(512, 340), junction(512, 432), junction(512, 830)]
WHU = {"Drop Control", "Lift", "Troop Mess"}
U.R = decklib.settle(U.R, U.H, whole=WHU, twins=U.TW, mirror_fn=M, mode="close")
U.door(512, 294, "h", both=False); U.door(458, 517, "v", both=False)
U.link("Comms", (501, 340)); U.link("Officers' Quarters", (501, 432))
for nm, y in (("Barracks A", 590), ("Barracks C", 678), ("Barracks E", 766)): U.link(nm, (501, y))
U.link("Troop Mess", (512, 840), both=False); U.link("Galley", (472, 900))
_g = U.R["Ready Room"]; _m = U.R["Troop Mess"]
_gt = _g.intersection(LineString([(496, 850), (496, 1150)])).bounds[1]; _mb = _m.intersection(LineString([(496, 850), (496, 1150)])).bounds[3]
U.H.append(hall((496, _mb), (496, _gt), w=16).difference(_g).difference(_m)); U.door(496, round(_mb, 1), "h", both=False); U.door(496, round(_gt, 1), "h", both=False)
U.R = decklib.finalize(U.R, U.H, list(U.R), U.TW, M, keep=WHU)
U.D = list(dict.fromkeys(U.D))
def bunks(nm):   # two bunk rows, kept well inside the room
    x0, y0, x1, y1 = U.R[nm].bounds; cx, cy = U.ctr(nm); w, h = (x1 - x0) * 0.3, (y1 - y0) * 0.1
    return [box(cx - w, cy - 2.6 * h, cx + w, cy - 1.0 * h), box(cx - w, cy + 1.0 * h, cx + w, cy + 2.6 * h)]
for nm in ("Barracks A", "Barracks C", "Barracks E"): U.feat(nm, bunks(nm))
for nm, f in [("Troop Mess", lambda x, y: [ring(x, y, 15)]), ("Officers' Quarters", lambda x, y: [box(x - 14, y - 7, x + 14, y + 7)]),
              ("Comms", lambda x, y: [ring(x, y, 8)])]:
    U.feat(nm, f(*U.ctr(nm)))
for nm, sd, off, lab in [("Officers' Quarters", "w", 0, "locker"), ("Barracks A", "w", 0, "locker"), ("Barracks C", "w", 0, "weapon rack"),
                         ("Barracks E", "w", 0, "locker"), ("Galley", "w", 0, "fuse box"), ("Comms", "w", 0, "console")]:
    U.wallniche(nm, sd, off, lab)
U.hatch((512, 720), "v")
SHORT = {"Drop Control": "Drop Ctrl", "Officers' Quarters": "Officers", "Sergeants' Quarters": "Sergeants", "Troop Mess": "Mess"}
bad = decklib.run(SID, HERE, SRC, AX, "upper", 1, U.R, U.H, U.D, [SHAFT], title="UPPER DECK - TROOP BERTHS", features=U.F, short=SHORT,
                  whole=WHU, niches=U.NICHE, hatches=U.HATCH, source=U.FROM, fits=U.FIT, round_rooms={"Drop Control", "Troop Mess"}, **CHECKS)

# ===================================================================== LOWER DECK - HOLD
L = Deck(AX)
L.room("Lift", LIFT, "lift car (the main deck's Lift (port) shaft)")
L.room("Life Support", lib("kasparov_a_14", 440, 420, w=6.4, h=6.4), "kasparov_a_14 round machine room", twin="Water Recycling",
       feat=[ring(445, 418, 15), circle(445, 418, 6).exterior])
L.room("Brig", lib("malgus_07", 512, 647, w=3.8, h=11.4, rot=90), "malgus_07 entry corridor as the cell corridor")
BX0, BY0, BX1, BY1 = [round(v, 1) for v in L.R["Brig"].bounds]
hh = (BY1 - BY0) / 3
for i in range(3):
    y = BY0 + hh * (i + 0.5)
    L.room("Cell %d" % (i + 1), lib("kasparov_b_01", BX0 - 36, y, w=7.2, h=hh / 10), "kasparov_b_01 cabin", twin=["Detention", "Cell 4", "Cell 5"][i],
           feat=[box(BX0 - 56, y - 7, BX0 - 46, y + 7)])
L.room("Cargo Hold A", lib("kasparov_b_11", 361, 696, w=8.2, h=5.8, rot=90), "kasparov_b_11 cargo bay", twin="Cargo Hold B")
L.room("Torpedo Store P", lib("fury_01", 300, 762, w=8.6, h=6.0, rot=90), "fury_01 cargo hold", twin="Torpedo Store S")
L.room("Shield Gen P", lib("kasparov_a_14", 433, 816, w=8.4, h=8.4), "kasparov_a_14 round machine room", twin="Shield Gen S",
       feat=[ring(441, 810, 18), circle(441, 810, 8).exterior])
L.room("Machine Shop", lib("tianjin_29", 437, 886, w=8.2, h=5.4), "tianjin_29 machineshop", twin="Fuel Store")
L.room("Coolant Pumps", circle(512, 982, 38), "tianjin_14 round room (pump in a ring walkway), drawn true round", feat=[ring(512, 982, 22), circle(512, 982, 9).exterior])
L.room("Battery P", lib("kasparov_a_14", 457, 1036, w=5.8, h=5.8), "kasparov_a_14 round machine room", twin="Battery S",
       feat=[ring(461, 1040, 13), circle(461, 1040, 5).exterior])
L.room("Escape Pods", sector(512, 1060, 52, 82, 45, 135), "carrick ring corridor (arc, 3 m), pod hatches along the hull")
L.H += spine(408, 572) + [ hall((512, 740), (512, 920), w=22), junction(512, 570, 4.0), junction(512, 740), junction(512, 920), hall((487, 1060), (537, 1060), w=16)]
L.hall(hall((512, 570), (409, 570), w=18)); L.hall(hall((409, 570), (409, 740), w=18)); L.hall(hall((512, 740), (331, 740), w=18))
WHL = {"Lift", "Life Support", "Water Recycling", "Brig", "Shield Gen P", "Shield Gen S", "Coolant Pumps", "Battery P", "Battery S", "Escape Pods"}
L.R = decklib.settle(L.R, L.H, whole=WHL, twins=L.TW, mirror_fn=L.M, mode="close")
L.door(458, 517, "v", both=False)
L.link("Life Support", (501, 420)); L.door(512, BY0, "h", both=False)
for nm in ("Cell 1", "Cell 2", "Cell 3"): L.door(BX0, round(L.R[nm].centroid.y, 1), "v")
L.link("Cargo Hold A", (400, 696)); L.link("Shield Gen P", (441, 749)); L.link("Torpedo Store P", (341, 749)); L.link("Machine Shop", (501, 880))
def vlink(a, b, x):   # a connector straight down between two rooms (doors on both walls)
    ra, rb = L.R[a], L.R[b]
    ya = ra.intersection(LineString([(x, 0), (x, 2000)])).bounds[3]; yb = rb.intersection(LineString([(x, 0), (x, 2000)])).bounds[1]
    L.H.append(hall((x, ya), (x, yb), w=16).difference(ra).difference(rb)); L.door(x, round(ya, 1), "h", both=False); L.door(x, round(yb, 1), "h", both=False)
_ct = L.R["Coolant Pumps"].bounds[1]
L.H.append(hall((512, 929), (512, _ct), w=16).difference(L.R["Coolant Pumps"])); L.door(512, round(_ct, 1), "h", both=False)
_cb = L.R["Coolant Pumps"].bounds[3]
L.H.append(hall((512, _cb), (512, 1052), w=16).difference(L.R["Coolant Pumps"])); L.door(512, round(_cb, 1), "h", both=False)
_pt = L.R["Escape Pods"].intersection(LineString([(512, 1000), (512, 1300)])).bounds[1]
L.H.append(hall((512, 1068), (512, _pt), w=16).difference(L.R["Escape Pods"])); L.door(512, round(_pt, 1), "h", both=False)
L.link("Battery P", (487, 1060))
L.R = decklib.finalize(L.R, L.H, list(L.R), L.TW, L.M, keep=WHL)
L.D = list(dict.fromkeys(L.D))
for nm, f in [("Cargo Hold A", lambda x, y: [box(x - 30, y - 12, x - 6, y + 12), box(x + 6, y - 12, x + 30, y + 12)]),
              ("Machine Shop", lambda x, y: [ring(x, y, 6)])]:
    L.feat(nm, f(*L.ctr(nm)))
for nm, sd, off, lab in [("Cargo Hold A", "n", 0, "console"), ("Machine Shop", "w", 0, "fuse box")]:
    L.wallniche(nm, sd, off, lab)
for a in (70, 90, 110):
    L.NICHE.append(("Escape Pods", (round(512 + 82 * math.cos(math.radians(a)), 1), round(1060 + 82 * math.sin(math.radians(a)), 1)), "s", "pod hatch"))
L.hatch((512, 660), "v"); L.hatch((512, 860), "v")
SHORT = {"Life Support": "Life Sup.", "Water Recycling": "Water", "Coolant Pumps": "Coolant", "Escape Pods": "Pods", "Machine Shop": "Machine",
         "Shield Gen P": "Shield P", "Shield Gen S": "Shield S"}
bad += decklib.run(SID, HERE, SRC, AX, "lower", -1, L.R, L.H, L.D, [SHAFT], title="LOWER DECK - HOLD", features=L.F, short=SHORT,
                   whole=WHL, niches=L.NICHE, hatches=L.HATCH, source=L.FROM, fits=L.FIT, anchor={"Escape Pods": (512, 1128)},
                   round_rooms={"Life Support", "Water Recycling", "Shield Gen P", "Shield Gen S", "Coolant Pumps", "Battery P", "Battery S", "Escape Pods"},
                   **dict(CHECKS, outline_style="close"))
decklib.both(os.path.join(HERE, "deck_upper.png"), os.path.join(HERE, "deck_lower.png"), os.path.join(HERE, "decks_plan.jpg"))
decklib.both(os.path.join(HERE, "deck_upper_on_map.jpg"), os.path.join(HERE, "deck_lower_on_map.jpg"), os.path.join(HERE, "decks_on_map.jpg"))
decklib.source_sheet([os.path.join(HERE, "deck_upper.json"), os.path.join(HERE, "deck_lower.json")], os.path.join(HERE, "decks_sources.jpg"))
print("TOTAL FAILURES (both decks):", len(bad))
sys.exit(1 if bad else 0)
