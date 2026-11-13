#!/usr/bin/env python3
"""Imperium Destroyer main deck, measured on the owner's HoloDeck sheet (1024 x 1536 px), mirrored about x 512.
10 px = 1 m. Long and narrow: a centre spine fore and aft of the launch bay, an outer run each side, weapon pods on
the flanks. PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 512.0
M = mirror(AX)
R = {}
R["Bridge"] = Polygon([(490, 166), (534, 166), (553, 190), (553, 251), (471, 251), (471, 190)])
R["Sensor Suite"] = box(471, 259, 553, 321)
R["CIC (Combat Information Center)"] = circle(512, 398, 50)
R["Launch Bay"] = Polygon([(480, 685), (544, 685), (561, 702), (561, 861), (544, 878), (480, 878), (463, 861), (463, 702)])
R["Engineering Deck"] = Polygon([(433, 1016), (591, 1016), (591, 1085), (569, 1107), (455, 1107), (433, 1085)])
R["Reactor Core"] = circle(512, 1160, 46)
R["Engine Control"] = box(456, 1234, 568, 1312)
L = {
    "Crew Quarters": Polygon([(360, 500), (380, 470), (455, 470), (455, 568), (360, 568)]),
    "Lift": box(470, 478, 498, 506),
    "Galley & Mess": box(379, 572, 494, 652),
    "Armory": box(355, 680, 425, 780),
    "Cargo Hold": box(350, 888, 488, 986),
    "Weapon Room": box(237, 835, 287, 900),
    "Magazine": box(237, 905, 287, 994),
    "Coolant": box(237, 1002, 287, 1075),
    "Engine Room": box(400, 1316, 490, 1380),
}
TWIN = {"Galley & Mess": "Medbay", "Cargo Hold": "Missile Magazine", "Engine Room": "Engine Room (R)"}
LNAME = {"Engine Room": "Engine Room (L)"}
for k, g in L.items():
    R[LNAME.get(k, k if k in TWIN else k + " (port)")] = g
    R[TWIN.get(k, k + " (starboard)")] = M(g)

LH = [
    hall((440, 390), (440, 470), w=16),                     # beside the CIC to the crew quarters
    hall((455, 552), (500, 552), w=14),                     # crew quarters -> spine
    hall((345, 600), (345, 1060), w=16),                    # the outer run
    hall((345, 666), (500, 666), w=16),                     # galley / armory -> spine
    hall((443, 676), (443, 880), w=26),                     # between the armory and the launch bay
    hall((390, 780), (390, 848), w=14), hall((345, 848), (456, 848), w=16), hall((394, 856), (394, 888), w=14),
    hall((287, 944), (337, 944), w=16),                     # weapon pod -> outer run
    hall((490, 944), (502, 944), w=16),
    hall((345, 1000), (502, 1000), w=16),                   # under the cargo hold
    hall((345, 1055), (435, 1055), w=16),                   # outer run -> engineering
    hall((430, 1107), (430, 1316), w=16), hall((438, 1162), (466, 1162), w=16),   # aft side way: reactor, engine control
]
HALLS = [box(502, 321, 522, 350), box(500, 450, 524, 685), box(502, 878, 522, 1016), box(502, 1206, 522, 1234)] + LH + [M(h) for h in LH]

DC = [(512, 255, "h"), (512, 323, "h"), (512, 348, "h"), (512, 449, "h"), (512, 683, "h"), (512, 880, "h"), (512, 1014, "h"),
      (512, 1208, "h"), (512, 1232, "h")]
DL = [(448, 400, "v"), (439, 468, "h"), (455, 556, "v"), (498, 492, "v"), (432, 570, "h"), (497, 611, "v"), (377, 613, "v"),
      (392, 654, "h"), (393, 678, "h"), (427, 718, "v"), (461, 722, "v"), (390, 782, "h"), (394, 886, "h"), (350, 944, "v"),
      (490, 944, "v"), (289, 944, "v"), (262, 902, "h"), (262, 998, "h"), (455, 988, "h"), (473, 1014, "h"), (437, 1055, "v"),
      (494, 1112, "h"), (464, 1162, "v"), (456, 1277, "v"), (478, 1314, "h"), (430, 1316, "h")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("imperium_destroyer", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(512, 780))
if __name__ == "__main__":
    run(S)
