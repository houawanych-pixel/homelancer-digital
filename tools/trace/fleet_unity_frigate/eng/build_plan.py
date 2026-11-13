#!/usr/bin/env python3
"""Unity Frigate main deck, measured on the owner's HoloDeck sheet (1024 x 1536 px), mirrored about x 512.
10 px = 1 m. Bridge, sensors and CIC fore; crew quarters and galley / medbay either side of the spine; the craft bay
amidships; engineering, reactor and engine room aft. PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 512.0
M = mirror(AX)
R = {}
R["Bridge"] = Polygon([(460, 157), (564, 157), (594, 187), (594, 282), (430, 282), (430, 187)])
R["Sensors Suite"] = box(461, 290, 563, 370)
R["CIC (Combat Information Center)"] = circle(512, 457, 62)
R["Craft Bay"] = box(462, 799, 562, 927)
R["Engineering Deck"] = box(340, 962, 684, 1066)
R["Reactor Core"] = circle(512, 1128, 46)
R["Engine Room"] = box(450, 1200, 574, 1320)
L = {
    "Crew Quarters": box(308, 389, 409, 593),
    "Lift": box(462, 553, 488, 583),
    "Galley & Mess": box(286, 602, 466, 745),
    "Armory": box(286, 760, 428, 915),
}
TWIN = {"Crew Quarters": ("Crew Quarters A", "Crew Quarters B"), "Galley & Mess": ("Galley & Mess", "Medbay"), "Armory": ("Armory", "Weapons Magazine")}
for k, g in L.items():
    a, b = TWIN.get(k, (k + " (port)", k + " (starboard)"))
    R[a] = g
    R[b] = M(g)

LH = [
    hall((428, 280), (428, 600), w=16),                     # beside the CIC (crew quarters)
    hall((436, 430), (452, 430), w=16),                     # -> CIC
    hall((466, 700), (492, 700), w=16),                     # galley -> spine
    hall((428, 784), (492, 784), w=16),                     # armory -> spine
    hall((428, 880), (462, 880), w=16),                     # armory -> craft bay
    hall((370, 915), (370, 962), w=16),                     # armory -> engineering
    hall((433, 1066), (433, 1260), w=16), hall((441, 1128), (466, 1128), w=16),   # engineering's aft side way
]
HALLS = [box(502, 370, 522, 395), box(492, 519, 532, 799), box(502, 927, 522, 962), box(502, 1174, 522, 1200)] + LH + [M(h) for h in LH]

DC = [(512, 286, "h"), (512, 372, "h"), (512, 393, "h"), (512, 521, "h"), (512, 799, "h"), (512, 929, "h"), (512, 960, "h"),
      (512, 1074, "h"), (512, 1176, "h"), (512, 1198, "h")]
DL = [(414, 461, "v"), (446, 430, "v"), (367, 597, "h"), (428, 600, "h"), (488, 568, "v"), (468, 700, "v"), (367, 753, "h"),
      (430, 784, "v"), (430, 880, "v"), (460, 880, "v"), (370, 917, "h"), (370, 960, "h"), (433, 1068, "h"), (464, 1128, "v"),
      (446, 1220, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("unity_frigate", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(512, 860))
if __name__ == "__main__":
    run(S)
