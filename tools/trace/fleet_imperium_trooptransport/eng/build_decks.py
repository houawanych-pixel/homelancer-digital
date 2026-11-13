#!/usr/bin/env python3
"""Imperium Troop Transport: PROPOSED upper (command) deck and lower (hold) deck, composed inside the hull, centre
mass, mirrored about x 494, the two lift shafts (Lift A / Lift B) where they stand on the main deck.
UPPER: observation lounge, officers' quarters, security office / weapons locker, war room, captain's quarters
(capture target), captain's office, officers' mess, comms array / navigation, gunnery control - two side halls and
three cross halls make loops round the middle.
LOWER: water recycling / life support, brig with detention office and holding cells (rescue target), cargo holds,
drop pod bays, machine shop / fuel store, coolant pumps, escape pods."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import hall, mirror
import decklib
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "source.jpg")
AX = 494.0
M = mirror(AX)
LIFTS = [(459, 490), (529, 490)]
IN = decklib.hull(SRC, AX).buffer(-26, join_style=2)        # the hull, one wall-and-a-bit in: outer rooms follow it
def clip(g):                                                 # an outer room: its outside wall follows the hull
    c = g.intersection(IN)
    c = max(getattr(c, "geoms", [c]), key=lambda q: q.area)
    return c.simplify(1.5)
def octa(x0, y0, x1, y1, c):
    return Polygon([(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)])
def pair(R, L, twin):
    for k, g in L.items():
        a, b = twin.get(k, (k + " (port)", k + " (starboard)"))
        R[a] = g; R[b] = M(g)
def mir(DL): return DL + [(2 * AX - x, y, o) for x, y, o in DL]

# ---------------- UPPER (command deck)
R = {"Observation Lounge": octa(434, 250, 554, 360, 26), "Captain's Quarters": octa(442, 550, 546, 660, 16),
     "Officers' Mess": box(374, 680, 614, 790), "Gunnery Control": octa(434, 900, 554, 990, 22)}
pair(R, {"Officers' Quarters": box(374, 372, 482, 462), "Lift": box(440, 470, 478, 510),
         "Security Office": box(374, 462, 440, 530), "War Room": box(374, 550, 442, 660),
         "Comms Array": box(374, 790, 484, 880)},
     {"Officers' Quarters": ("Officers' Quarters A", "Officers' Quarters B"), "Lift": ("Lift A", "Lift B"),
      "Security Office": ("Security Office", "Weapons Locker"), "War Room": ("War Room", "Captain's Office"),
      "Comms Array": ("Comms Array", "Navigation Room")})
pair(R, {"Star Chart Room": clip(box(250, 300, 434, 372)), "Officer Cabins": clip(box(200, 372, 352, 530)),
         "Officers' Lounge": clip(box(200, 530, 352, 680)), "Galley": clip(box(200, 680, 352, 790)),
         "Shield Control": clip(box(200, 790, 352, 900)), "Turret Access": clip(box(200, 900, 352, 1010))},
     {"Officer Cabins": ("Officer Cabins A", "Officer Cabins B"), "Galley": ("Galley", "Wardroom"),
      "Shield Control": ("Shield Control", "Fire Control")})
LH = [box(352, 372, 374, 880), hall((363, 870), (363, 945), w=22), hall((363, 945), (434, 945), w=20)]
HALLS = [box(482, 360, 506, 462), box(478, 462, 510, 530), box(352, 530, 636, 550), box(352, 660, 636, 680),
         box(484, 790, 504, 900)] + LH + [M(h) for h in LH]
DC = [(494, 359, "h"), (494, 550, "h"), (494, 790, "h"), (494, 900, "h")]
DL = [(482, 417, "v"), (374, 417, "v"), (478, 490, "v"), (374, 496, "v"), (407, 530, "h"), (408, 550, "h"), (374, 605, "v"),
      (440, 680, "h"), (374, 735, "v"), (484, 840, "v"), (374, 840, "v"), (434, 945, "v"),
      (400, 372, "h"), (352, 450, "v"), (352, 605, "v"), (352, 735, "v"), (352, 845, "v"), (300, 530, "h"), (300, 790, "h"),
      (352, 925, "v")]
bad = decklib.run("imperium_trooptransport", HERE, SRC, AX, "upper", 1, R, HALLS, DC + mir(DL), LIFTS,
                  title="UPPER DECK - COMMAND")

# ---------------- LOWER (hold deck)
R = {"Brig": box(420, 580, 568, 700), "Coolant Pumps": octa(450, 1020, 538, 1140, 18), "Escape Pods": box(420, 1160, 568, 1220)}
pair(R, {"Lift": box(440, 470, 478, 510), "Water Recycling": box(360, 450, 440, 560), "Detention Office": box(360, 580, 420, 700),
         "Cargo Hold": box(360, 720, 484, 900), "Drop Pod Bay": box(360, 900, 484, 1000), "Machine Shop": box(360, 1020, 450, 1140)},
     {"Lift": ("Lift A", "Lift B"), "Water Recycling": ("Water Recycling", "Life Support"),
      "Detention Office": ("Detention Office", "Holding Cells"), "Cargo Hold": ("Cargo Hold A", "Cargo Hold B"),
      "Drop Pod Bay": ("Drop Pod Bay A", "Drop Pod Bay B"), "Machine Shop": ("Machine Shop", "Fuel Store")})
pair(R, {"Ammo Store": clip(box(200, 450, 340, 580)), "Guard Post": clip(box(200, 580, 340, 720)),
         "Spare Parts": clip(box(200, 720, 340, 900)), "Pod Launch Control": clip(box(200, 900, 340, 1020)),
         "Battery Room": clip(box(200, 1020, 340, 1160))},
     {"Spare Parts": ("Spare Parts", "Medical Store"), "Battery Room": ("Battery Room", "Shield Generator")})
LH = [box(340, 450, 360, 1160)]
HALLS = [box(478, 450, 510, 560), box(340, 560, 648, 580), box(340, 700, 648, 720), box(484, 720, 504, 1000),
         box(340, 1000, 648, 1020), box(340, 1140, 648, 1160)] + LH + [M(h) for h in LH]
DC = [(494, 580, "h"), (494, 1020, "h"), (494, 1160, "h")]
DL = [(478, 490, "v"), (360, 505, "v"), (400, 560, "h"), (420, 640, "v"), (360, 640, "v"), (405, 720, "h"), (484, 810, "v"),
      (360, 810, "v"), (422, 900, "h"), (484, 950, "v"), (405, 1000, "h"), (405, 1020, "h"), (360, 1080, "v"), (450, 1080, "v"),
      (340, 515, "v"), (340, 650, "v"), (340, 810, "v"), (340, 960, "v"), (340, 1090, "v"), (290, 580, "h"), (290, 900, "h")]
bad += decklib.run("imperium_trooptransport", HERE, SRC, AX, "lower", -1, R, HALLS, DC + mir(DL), LIFTS,
                   title="LOWER DECK - HOLD")
decklib.both(os.path.join(HERE, "deck_upper_on_map.jpg"), os.path.join(HERE, "deck_lower_on_map.jpg"), os.path.join(HERE, "decks_on_map.jpg"))
sys.exit(1 if bad else 0)
