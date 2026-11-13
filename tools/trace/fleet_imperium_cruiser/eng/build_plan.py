#!/usr/bin/env python3
"""Imperium Cruiser main deck, measured on the owner's HoloDeck sheet (1174 x 1340 px), mirrored about x 587.
10 px = 1 m. Rooms at their measured boxes (tools/trace/auto_plan.py measure + by eye); hallways are the channels
between them. Unlabelled hull compartments are hull. PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 587.0
M = mirror(AX)
R = {}
R["Bridge"] = Polygon([(565, 148), (609, 148), (627, 175), (627, 223), (547, 223), (547, 175)])
R["Sensors Suite"] = ellipse(587, 288, 38, 43)
R["CIC (Combat Information Center)"] = circle(587, 414, 54)
R["Hangar Bay"] = Polygon([(507, 644), (667, 644), (689, 666), (689, 780), (667, 802), (507, 802), (485, 780), (485, 666)])
R["Vehicle Bay"] = box(516, 826, 658, 904)
R["Engineering Deck"] = Polygon([(452, 931), (722, 931), (722, 985), (700, 1008), (474, 1008), (452, 985)])
R["Reactor Core"] = circle(587, 1066, 43)
R["Engine Room"] = box(542, 1123, 632, 1187)
L = {
    "Crew Quarters": Polygon([(438, 500), (470, 464), (521, 464), (521, 545), (438, 545)]),
    "CIC Annex": box(492, 365, 528, 444),
    "Sensor Console": box(512, 307, 545, 355),
    "Lift": box(543, 522, 569, 556),
    "Galley & Mess": box(421, 550, 508, 625),
    "Armory": box(322, 664, 431, 724),
    "Aft Lift": box(432, 732, 456, 762),
    "Barracks": Polygon([(233, 770), (300, 742), (400, 742), (400, 839), (233, 839)]),
    "Weapon Systems": Polygon([(115, 861), (180, 775), (226, 762), (226, 861)]),
    "Coolant & Systems": Polygon([(92, 923), (120, 866), (201, 866), (201, 923)]),
    "Cargo Hold": box(402, 826, 490, 905),
}
TWIN = {"Galley & Mess": "Medbay"}
for k, g in L.items():
    R[k + " (port)" if k not in TWIN else k] = g
    R[k + " (starboard)" if k not in TWIN else TWIN[k]] = M(g)

LH = [
    hall((572, 222), (572, 250), w=16),                     # bridge -> sensors, each side
    hall((545, 345), (568, 345), w=16),                     # sensor console -> centre passage
    hall((537, 446), (537, 586), w=16),                     # down beside the CIC (crew quarters, lift)
    hall((508, 578), (587, 578), w=16),                     # across under the lifts (galley, spine)
    hall((547, 586), (547, 644), w=16),                     # down to the hangar's head doors
    hall((400, 648), (520, 648), w=16),                     # along the hangar's head (galley, armory)
    hall((444, 648), (444, 732), w=20), hall((444, 762), (444, 822), w=20),   # down past the armory to the aft lift and on
    hall((454, 684), (484, 684), w=16), hall((454, 733), (484, 733), w=16),   # into the hangar's port doors
    hall((322, 733), (434, 733), w=14),                     # between armory and barracks
    hall((402, 814), (587, 814), w=16),                     # under the hangar (cargo, vehicle bay)
    hall((503, 822), (503, 925), w=18),                     # between cargo hold and vehicle bay
    hall((500, 917), (587, 917), w=14),                     # over engineering
    hall((354, 839), (354, 893), w=14), hall((203, 893), (402, 893), w=16),   # barracks -> the wing run (coolant, cargo)
    hall((512, 1008), (512, 1066), (545, 1066), w=16),      # engineering's side way to the reactor
]
HALLS = [box(568, 335, 606, 362), box(573, 468, 601, 586)] + LH + [M(h) for h in LH]

DC = [(587, 333, "h"), (587, 360, "h"), (587, 470, "h"), (587, 824, "h"), (587, 906, "h"), (587, 1016, "h")]
DL = [(572, 224, "h"), (572, 248, "h"), (547, 345, "v"), (530, 395, "v"), (537, 448, "h"), (526, 505, "v"), (543, 539, "v"),
      (569, 539, "v"), (510, 578, "v"), (547, 642, "h"), (467, 632, "h"), (407, 660, "h"), (433, 703, "v"), (444, 732, "h"),
      (444, 762, "h"), (486, 684, "v"), (486, 733, "v"), (351, 740, "h"), (229, 790, "v"), (148, 863, "h"), (203, 893, "v"),
      (400, 893, "v"), (354, 840, "h"), (568, 803, "h"), (465, 824, "h"), (491, 884, "v"), (548, 929, "h"), (513, 1006, "h"),
      (545, 1066, "v"), (575, 1117, "h")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("imperium_cruiser", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(587, 720), proposed=[(587, 1016)])
if __name__ == "__main__":
    run(S)
