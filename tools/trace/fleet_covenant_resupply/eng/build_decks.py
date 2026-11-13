#!/usr/bin/env python3
"""Covenant Resupply Ship: PROPOSED upper (command / crew) and lower (stores) decks in the owner-preferred pass 2a
style (traced rooms from tools/trace/shape_library.json picked by function, service space, spine with junction rooms,
niches, hatches), mirrored about x 567. Both decks stop at ONE lift shaft: the main deck's Lift on the centreline,
(567, 389), doors fore and aft. decklib.check() runs on both."""
import json, math, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import hall, circle
import decklib
from decklib import lib, Deck
from shapely.geometry import Polygon, LineString, box, shape

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "source.jpg")
SID, AX = "covenant_resupply", 567.0
SHAFT = (567, 389)
LIFT = box(555, 378, 579, 400)
SERVICE = ["conduit", "duct", "power trunk", "coolant loop", "crawlspace", "machinery", "structure", "wiring run", "fuse bay"]
def ring(cx, cy, r): return circle(cx, cy, r).exterior
def junction(cx, cy, d=4.4): return lib("tianjin_10", cx, cy, w=d, h=d)
def arc(cx, cy, r, a0, a1, n=24):
    return LineString([(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)])
def sector(cx, cy, r0, r1, a0, a1):
    return Polygon(list(arc(cx, cy, r1, a0, a1).coords) + list(arc(cx, cy, r0, a1, a0).coords))
_MAIN = json.load(open(os.path.join(HERE, "plan.json")))
LIFT_CHECK = [] if shape(_MAIN["rooms"]["Lift"]).buffer(1).contains(LIFT) else ["the shaft is not the main deck's Lift"]
CHECKS = dict(service=SERVICE, lift_ok=LIFT_CHECK, outline_style="ring")
def spine(y0, y1, w=22):   # (2.2 m, broken by the lift car on the centreline: doors fore and aft)
    out = []
    if y0 < 378: out.append(hall((567, y0), (567, 378), w=w))
    if y1 > 400: out.append(hall((567, 400), (567, y1), w=w))
    return out

# ===================================================================== UPPER DECK - COMMAND / CREW
U = Deck(AX); M = U.M
U.room("Flight Control", lib("malgus_11", 567, 250, w=8.4), "malgus_11 command hub, railing ring", feat=[ring(567, 250, 24), ring(567, 250, 10)])
U.room("Lift", LIFT, "lift car (the main deck's Lift shaft)")
U.room("Logistics Office", lib("kasparov_a_03", 498, 332, w=7.0, h=6.6), "kasparov_a_03 ops (round alcove)", twin="Comms")
U.room("Quartermaster", lib("fury_08", 498, 425, w=7.2, h=5.6), "fury_08 secondary quarters (angled)", twin="Security")
U.room("Captain's Quarters", lib("fury_04", 493, 512, w=10.0, h=6.6, flip=True), "fury_04 captain's quarters", twin="First Officer")
U.room("Cabins A", lib("kasparov_b_03", 478, 590, w=11.2, h=6.4), "kasparov_b_03 passenger quarters", twin="Cabins B")
U.room("Lounge P", lib("fury_06", 470, 690, w=13.6, h=5.4), "fury_06 lounge + holoterminal", twin="Lounge S")
U.room("Gym", lib("kasparov_b_06", 352, 640, w=6.4, h=6.4), "kasparov_b_06 round room", twin="Chapel")
U.room("Officers' Mess", lib("kasparov_b_06", 567, 790, w=7.4, h=7.4), "kasparov_b_06 dining area (round)")
U.room("Galley", lib("tianjin_01", 491, 792, w=6.9, h=7.3, flip=True), "tianjin_01 galley (quarter round)", twin="Wardroom")
U.room("Cargo Control", lib("tianjin_26", 567, 887, w=9.1, h=7.6, rot=90), "tianjin_26 gunnery (tapered) as the cargo control room")
U.H += spine(292, 720) + [junction(567, 332), junction(567, 470), junction(567, 640), junction(567, 720)]
U.hall(hall((567, 640), (382, 640), w=18))
WHU = {"Flight Control", "Lift", "Officers' Mess", "Gym", "Chapel"}
U.R = decklib.settle(U.R, U.H, whole=WHU, twins=U.TW, mirror_fn=M, mode="close")
U.door(567, 292, "h", both=False); U.door(567, 378, "h", both=False); U.door(567, 400, "h", both=False)
U.link("Logistics Office", (556, 332)); U.link("Quartermaster", (556, 425)); U.link("Captain's Quarters", (556, 505))
U.link("Cabins A", (482, 631)); U.link("Lounge P", (472, 649)); U.link("Gym", (395, 640)); U.link("Officers' Mess", (567, 730), both=False)
U.link("Galley", (530, 790))
_g = U.R["Cargo Control"]; _m = U.R["Officers' Mess"]
_gt = _g.intersection(LineString([(551, 700), (551, 1100)])).bounds[1]; _mb = _m.intersection(LineString([(551, 700), (551, 1100)])).bounds[3]
U.H.append(hall((551, _mb), (551, _gt), w=16).difference(_g).difference(_m)); U.door(551, round(_mb, 1), "h", both=False); U.door(551, round(_gt, 1), "h", both=False)
U.R = decklib.finalize(U.R, U.H, list(U.R), U.TW, M, keep=WHU)
U.D = list(dict.fromkeys(U.D))
for nm, f in [("Officers' Mess", lambda x, y: [ring(x, y, 14)]), ("Captain's Quarters", lambda x, y: [box(x - 14, y - 7, x + 14, y + 7)]),
              ("Lounge P", lambda x, y: [ring(x, y, 8)]), ("Logistics Office", lambda x, y: [ring(x, y, 8)])]:
    U.feat(nm, f(*U.ctr(nm)))
for nm, sd, off, lab in [("Captain's Quarters", "w", 0, "locker"), ("Quartermaster", "w", 0, "shelves"), ("Cabins A", "w", 0, "locker"),
                         ("Lounge P", "s", 0, "med station"), ("Galley", "w", 0, "fuse box"), ("Logistics Office", "w", 0, "console")]:
    U.wallniche(nm, sd, off, lab)
U.hatch((567, 560), "v"); U.hatch((440, 640), "h")
SHORT = {"Flight Control": "Flight Ctrl", "Captain's Quarters": "Captain", "First Officer": "1st Officer", "Logistics Office": "Logistics",
         "Quartermaster": "Q.Master", "Officers' Mess": "Mess", "Cargo Control": "Cargo Ctrl"}
bad = decklib.run(SID, HERE, SRC, AX, "upper", 1, U.R, U.H, U.D, [SHAFT], title="UPPER DECK - COMMAND / CREW", features=U.F, short=SHORT,
                  whole=WHU, niches=U.NICHE, hatches=U.HATCH, source=U.FROM, fits=U.FIT, round_rooms={"Flight Control", "Officers' Mess", "Gym", "Chapel"}, **CHECKS)

# ===================================================================== LOWER DECK - STORES
L = Deck(AX)
L.room("Lift", LIFT, "lift car (the main deck's Lift shaft)")
L.room("Life Support", lib("kasparov_a_14", 497, 320, w=6.4, h=6.4), "kasparov_a_14 round machine room", twin="Water Recycling",
       feat=[ring(502, 318, 15), circle(502, 318, 6).exterior])
L.room("Fuel Tank P", lib("kasparov_a_14", 490, 470, w=8.4, h=8.4), "kasparov_a_14 round machine room (tank in a ring walkway)", twin="Fuel Tank S",
       feat=[ring(498, 464, 18), circle(498, 464, 8).exterior])
L.room("Cargo Hold A", lib("kasparov_b_11", 480, 585, w=8.2, h=5.8, rot=90), "kasparov_b_11 cargo bay", twin="Cargo Hold B")
L.room("Bulk Hold P", lib("fury_01", 372, 712, w=11.0, h=8.0, rot=90), "fury_01 cargo hold", twin="Bulk Hold S")
L.room("Cold Store", lib("tianjin_29", 486, 800, w=8.2, h=5.4), "tianjin_29 machineshop as the refrigerated store", twin="Ammo Store")
L.room("Coolant Pumps", circle(567, 960, 38), "tianjin_14 round room (pump in a ring walkway), drawn true round", feat=[ring(567, 960, 22), circle(567, 960, 9).exterior])
L.room("Battery P", lib("kasparov_a_14", 512, 1014, w=5.8, h=5.8), "kasparov_a_14 round machine room", twin="Battery S",
       feat=[ring(516, 1018, 13), circle(516, 1018, 5).exterior])
L.room("Escape Pods", sector(567, 1040, 52, 82, 45, 135), "carrick ring corridor (arc, 3 m), pod hatches along the hull")
L.H += spine(290, 900) + [junction(567, 320), junction(567, 470), junction(567, 640), junction(567, 800), hall((542, 1040), (592, 1040), w=16)]
L.hall(hall((567, 640), (412, 640), w=18))
WHL = {"Lift", "Life Support", "Water Recycling", "Fuel Tank P", "Fuel Tank S", "Coolant Pumps", "Battery P", "Battery S", "Escape Pods"}
L.R = decklib.settle(L.R, L.H, whole=WHL, twins=L.TW, mirror_fn=L.M, mode="close")
L.door(567, 378, "h", both=False); L.door(567, 400, "h", both=False)
L.link("Life Support", (556, 320)); L.link("Fuel Tank P", (556, 470)); L.link("Cargo Hold A", (556, 585)); L.link("Bulk Hold P", (420, 640))
L.link("Cold Store", (556, 800))
_ct = L.R["Coolant Pumps"].bounds[1]
L.H.append(hall((567, 900), (567, _ct), w=16).difference(L.R["Coolant Pumps"])); L.door(567, round(_ct, 1), "h", both=False)
_cb = L.R["Coolant Pumps"].bounds[3]
L.H.append(hall((567, _cb), (567, 1032), w=16).difference(L.R["Coolant Pumps"])); L.door(567, round(_cb, 1), "h", both=False)
_pt = L.R["Escape Pods"].intersection(LineString([(567, 1000), (567, 1300)])).bounds[1]
L.H.append(hall((567, 1048), (567, _pt), w=16).difference(L.R["Escape Pods"])); L.door(567, round(_pt, 1), "h", both=False)
L.link("Battery P", (542, 1040))
L.R = decklib.finalize(L.R, L.H, list(L.R), L.TW, L.M, keep=WHL)
L.D = list(dict.fromkeys(L.D))
def crates(nm):   # two cargo stacks, kept well inside the room
    x0, y0, x1, y1 = L.R[nm].bounds; cx, cy = L.ctr(nm); w, h = (x1 - x0) * 0.12, (y1 - y0) * 0.16
    return [box(cx - 2.6 * w, cy - h, cx - 0.6 * w, cy + h), box(cx + 0.6 * w, cy - h, cx + 2.6 * w, cy + h)]
for nm in ("Cargo Hold A", "Bulk Hold P"): L.feat(nm, crates(nm))
L.feat("Cold Store", [ring(*L.ctr("Cold Store"), 6)])
for nm, sd, off, lab in [("Bulk Hold P", "n", 0, "console"), ("Cold Store", "w", 0, "shelves"), ("Cargo Hold A", "w", 0, "fuse box")]:
    L.wallniche(nm, sd, off, lab)
for a in (70, 90, 110):
    L.NICHE.append(("Escape Pods", (round(567 + 82 * math.cos(math.radians(a)), 1), round(1040 + 82 * math.sin(math.radians(a)), 1)), "s", "pod hatch"))
L.hatch((567, 540), "v"); L.hatch((567, 860), "v")
SHORT = {"Life Support": "Life Sup.", "Water Recycling": "Water", "Coolant Pumps": "Coolant", "Escape Pods": "Pods",
         "Fuel Tank P": "Fuel P", "Fuel Tank S": "Fuel S", "Bulk Hold P": "Bulk P", "Bulk Hold S": "Bulk S"}
bad += decklib.run(SID, HERE, SRC, AX, "lower", -1, L.R, L.H, L.D, [SHAFT], title="LOWER DECK - STORES", features=L.F, short=SHORT,
                   whole=WHL, niches=L.NICHE, hatches=L.HATCH, source=L.FROM, fits=L.FIT, anchor={"Escape Pods": (567, 1108)},
                   round_rooms={"Life Support", "Water Recycling", "Fuel Tank P", "Fuel Tank S", "Coolant Pumps", "Battery P", "Battery S", "Escape Pods"},
                   **dict(CHECKS, outline_style="close"))
decklib.both(os.path.join(HERE, "deck_upper.png"), os.path.join(HERE, "deck_lower.png"), os.path.join(HERE, "decks_plan.jpg"))
decklib.both(os.path.join(HERE, "deck_upper_on_map.jpg"), os.path.join(HERE, "deck_lower_on_map.jpg"), os.path.join(HERE, "decks_on_map.jpg"))
decklib.source_sheet([os.path.join(HERE, "deck_upper.json"), os.path.join(HERE, "deck_lower.json")], os.path.join(HERE, "decks_sources.jpg"))
print("TOTAL FAILURES (both decks):", len(bad))
sys.exit(1 if bad else 0)
