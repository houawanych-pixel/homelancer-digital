#!/usr/bin/env python3
"""Elyza Cruiser main deck, measured on the owner's HoloDeck sheet (1314 x 1197 px), mirrored about x 657.
10 px = 1 m. Command fore of a spine, the hangar amidships inside a ring, cargo hold (port) and vehicle bay
(starboard) as twins, the long swept wings (coolant, weapon bays), engineering, reactor and two engine rooms aft.
PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 657.0
M = mirror(AX)
R = {}
R["Bridge"] = circle(657, 199, 40)
R["Sensor Suite"] = box(614, 244, 700, 300)
R["CIC (Combat Information Center)"] = circle(657, 392, 52)
R["Hangar Bay"] = Polygon([(572, 593), (742, 593), (758, 609), (758, 710), (742, 726), (572, 726), (556, 710), (556, 609)])
R["Engineering Deck"] = box(592, 848, 722, 920)
R["Reactor Core"] = circle(657, 963, 40)
L = {
    "Crew Quarters": box(493, 340, 571, 475),
    "Galley & Mess": box(510, 486, 589, 555),
    "Armory": box(438, 664, 503, 760),
    "Coolant & Systems": box(291, 698, 406, 768),
    "Weapon Bay": Polygon([(155, 770), (200, 700), (287, 690), (287, 805), (200, 822)]),
    "Cargo Hold": box(498, 763, 644, 844),
    "Engine Room": box(484, 942, 563, 1028),
}
TWIN = {"Galley & Mess": "Medbay", "Cargo Hold": "Vehicle Bay"}
for k, g in L.items():
    R[k if k in TWIN else k + " (port)"] = g
    R[TWIN.get(k, k + " (starboard)")] = M(g)

LH = [
    hall((571, 394), (605, 394), w=16),                     # crew quarters -> CIC
    hall((589, 520), (645, 520), w=16),                     # galley -> spine
    hall((533, 565), (533, 760), w=20),                     # the hangar's port side
    hall((533, 575), (645, 575), w=16),                     # over the hangar
    hall((503, 700), (523, 700), w=16),                     # armory -> side run
    hall((406, 733), (438, 733), w=16),                     # coolant -> armory
    hall((506, 844), (506, 942), w=16),                     # cargo hold -> engine room
]
HALLS = [box(647, 300, 667, 340), box(645, 444, 669, 593), box(647, 726, 667, 848)] + LH + [M(h) for h in LH]

DC = [(657, 241, "h"), (657, 302, "h"), (657, 338, "h"), (657, 446, "h"), (657, 591, "h"), (657, 728, "h"), (657, 846, "h"), (657, 921, "h")]
DL = [(573, 394, "v"), (603, 394, "v"), (561, 480, "h"), (591, 520, "v"), (533, 557, "h"), (550, 665, "v"), (505, 700, "v"),
      (408, 733, "v"), (436, 733, "v"), (289, 733, "v"), (533, 762, "h"), (506, 846, "h"), (506, 940, "h")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("elyza_cruiser", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(657, 660))
if __name__ == "__main__":
    run(S)
