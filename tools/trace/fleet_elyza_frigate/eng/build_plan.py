#!/usr/bin/env python3
"""Elyza Frigate main deck, measured on the owner's HoloDeck sheet (1024 x 1536 px), mirrored about x 512.
10 px = 1 m. Bridge, sensors, CIC fore; crew quarters, galley / medbay and armory / magazine either side of a spine
with two lifts; the craft bay amidships; engineering, reactor and engine room aft. PROPOSED = not on the sheet."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 512.0
M = mirror(AX)
R = {}
R["Bridge"] = Polygon([(480, 211), (544, 211), (566, 233), (566, 305), (458, 305), (458, 233)])
R["Sensors Suite"] = box(461, 336, 563, 415)
R["CIC (Combat Information Center)"] = circle(512, 511, 56)
R["Lift A"] = box(498, 650, 526, 678)
R["Lift B"] = box(498, 815, 526, 843)
R["Craft Bay"] = Polygon([(480, 878), (544, 878), (561, 895), (561, 960), (544, 977), (480, 977), (463, 960), (463, 895)])
R["Engineering Deck"] = box(431, 1000, 593, 1083)
R["Reactor Core"] = circle(512, 1158, 44)
R["Engine Room"] = box(452, 1229, 572, 1305)
L = {
    "Crew Quarters": box(353, 440, 433, 590),
    "Galley & Mess": box(340, 629, 456, 762),
    "Armory": box(307, 811, 425, 960),
}
TWIN = {"Crew Quarters": ("Crew Quarters A", "Crew Quarters B"), "Galley & Mess": ("Galley & Mess", "Medbay"), "Armory": ("Armory", "Magazine (Ordnance)")}
for k, g in L.items():
    a, b = TWIN[k]
    R[a] = g
    R[b] = M(g)

LH = [
    hall((433, 500), (456, 500), w=16),                     # crew quarters -> CIC
    hall((456, 726), (500, 726), w=16),                     # galley -> spine
    hall((330, 786), (500, 786), w=14),                     # across, between galley and armory
    hall((425, 850), (500, 850), w=16),                     # armory -> spine (lift B)
    hall((363, 960), (363, 1043), (431, 1043), w=16),       # armory -> engineering
    hall((420, 1083), (420, 1240), w=16), hall((428, 1158), (468, 1158), w=16), hall((428, 1240), (452, 1240), w=16),   # aft side way
]
SMALL = [box(412, 590, 428, 629), box(369, 793, 385, 811)]
HALLS = [box(502, 305, 522, 336), box(502, 415, 522, 455), box(500, 567, 524, 650), box(500, 678, 524, 815), box(500, 843, 524, 878),
         box(502, 977, 522, 1000), box(502, 1083, 522, 1114), box(502, 1202, 522, 1229)] + SMALL + [M(b) for b in SMALL] + LH + [M(h) for h in LH]

DC = [(512, 307, "h"), (512, 334, "h"), (512, 417, "h"), (512, 453, "h"), (512, 569, "h"), (512, 650, "h"), (512, 678, "h"),
      (512, 815, "h"), (512, 843, "h"), (512, 876, "h"), (512, 979, "h"), (512, 998, "h"), (512, 1085, "h"), (512, 1112, "h"),
      (512, 1204, "h"), (512, 1227, "h")]
DL = [(435, 500, "v"), (455, 500, "v"), (420, 592, "h"), (420, 627, "h"), (458, 726, "v"), (377, 772, "h"), (377, 795, "h"),
      (377, 809, "h"), (427, 850, "v"), (363, 962, "h"), (429, 1043, "v"), (420, 1085, "h"), (466, 1158, "v"),
      (450, 1240, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("elyza_frigate", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(512, 925))
if __name__ == "__main__":
    run(S)
