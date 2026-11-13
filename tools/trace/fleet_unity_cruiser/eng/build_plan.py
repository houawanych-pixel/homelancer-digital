#!/usr/bin/env python3
"""Unity Cruiser main deck, measured on the owner's HoloDeck sheet (1254 x 1254 px), mirrored about x 627.
10 px = 1 m. A centre spine bow to stern; the cargo hold (port) and vehicle bay (starboard) are twins in shape.
The long wing pods (coolant & utility) are hull past their side corridors. PROPOSED = not on the sheet."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 627.0
M = mirror(AX)
R = {}
R["Bridge"] = circle(627, 216, 40)
R["Sensors Suite"] = box(590, 271, 664, 331)
R["CIC (Combat Information Center)"] = circle(627, 422, 51)
R["Launch Bay (Hangar)"] = Polygon([(585, 647), (669, 647), (684, 662), (684, 784), (669, 799), (585, 799), (570, 784), (570, 662)])
R["Engineering Deck"] = box(500, 918, 754, 995)
R["Reactor Core"] = circle(627, 1043, 40)
R["Engine Room"] = box(589, 1101, 665, 1206)
L = {
    "Crew Quarters": box(484, 385, 555, 505),
    "Lift": box(575, 490, 600, 516),
    "Galley & Mess": Polygon([(458, 545), (480, 524), (554, 524), (554, 597), (458, 597)]),
    "Armory": Polygon([(441, 655), (463, 633), (523, 633), (523, 688), (441, 688)]),
    "Weapon Bay": Polygon([(367, 690), (395, 662), (441, 662), (441, 734), (367, 734)]),
    "Cargo Hold": Polygon([(462, 820), (479, 803), (603, 803), (603, 898), (462, 898)]),
}
TWIN = {"Galley & Mess": "Medbay", "Cargo Hold": "Vehicle Bay"}
for k, g in L.items():
    R[k if k in TWIN else k + " (port)"] = g
    R[TWIN.get(k, k + " (starboard)")] = M(g)

LH = [
    hall((548, 354), (627, 354), w=16),                     # across, over the CIC
    hall((565, 354), (565, 505), w=16),                     # beside the CIC (crew quarters, lift)
    hall((554, 564), (615, 564), w=16),                     # galley -> spine
    hall((547, 640), (547, 800), w=20),                     # beside the launch bay (armory)
    hall((470, 797), (557, 797), w=14),                     # over the cargo hold
    hall((350, 700), (350, 1000), w=16),                    # the wing pod's run
    hall((358, 710), (367, 710), w=16),
    hall((572, 995), (572, 1049), (587, 1049), w=16),       # engineering's side way to the reactor
]
HALLS = [box(615, 331, 639, 371), box(615, 473, 639, 647), box(615, 799, 639, 918), box(617, 1083, 637, 1101),
         box(494, 505, 510, 524), box(499, 597, 515, 633)] + LH + [M(h) for h in LH] + [M(box(494, 505, 510, 524)), M(box(499, 597, 515, 633))]

DC = [(627, 263, "h"), (627, 333, "h"), (627, 369, "h"), (627, 475, "h"), (627, 645, "h"), (627, 801, "h"), (627, 918, "h"),
      (627, 999, "h"), (627, 1085, "h"), (627, 1099, "h")]
DL = [(556, 420, "v"), (574, 420, "v"), (574, 503, "v"), (607, 503, "v"), (502, 507, "h"), (502, 522, "h"), (556, 564, "v"),
      (507, 599, "h"), (507, 631, "h"), (441, 675, "v"), (530, 678, "v"), (562, 680, "v"), (562, 772, "v"), (365, 710, "v"),
      (508, 801, "h"), (609, 872, "v"), (572, 997, "h"), (587, 1049, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("unity_cruiser", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(627, 720))
if __name__ == "__main__":
    run(S)
