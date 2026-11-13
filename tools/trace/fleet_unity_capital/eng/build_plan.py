#!/usr/bin/env python3
"""Unity Capital Ship main deck, measured on the owner's HoloDeck sheet (1024 x 1536 px), mirrored about x 512.
10 px = 1 m. A hangar inside a ring of hallways; command fore (bridge, CIC), engineering aft. Unlabelled hull
compartments are hull. PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 512.0
M = mirror(AX)
R = {}
R["Bridge"] = circle(512, 168, 50)
R["CIC (Combat Information Center)"] = circle(512, 378, 56)
R["Hangar Bay"] = Polygon([(414, 609), (610, 609), (629, 628), (629, 868), (610, 888), (414, 888), (395, 868), (395, 628)])
R["Vehicle Bay"] = box(389, 894, 635, 975)
R["Engineering Deck"] = Polygon([(330, 1010), (694, 1010), (694, 1110), (675, 1125), (349, 1125), (330, 1110)])
R["Reactor Core"] = circle(512, 1188, 45)
R["Engine Room"] = box(470, 1270, 554, 1355)
L = {
    "Sensors Suite": box(403, 240, 493, 305),
    "Crew Quarters": box(325, 374, 412, 476),
    "Galley & Mess": Polygon([(324, 495), (411, 495), (411, 562), (396, 577), (324, 577)]),
    "Lift": box(468, 460, 498, 490),
    "Armory": box(244, 690, 330, 806),
    "Cargo Hold": Polygon([(225, 850), (245, 830), (346, 830), (346, 980), (225, 980)]),
}
TWIN = {"Sensors Suite": "Briefing Room", "Galley & Mess": "Medbay", "Cargo Hold": "Cargo Hold B"}
LN = {"Cargo Hold": "Cargo Hold A"}
for k, g in L.items():
    R[LN.get(k, k if k in TWIN else k + " (port)")] = g
    R[TWIN.get(k, k + " (starboard)")] = M(g)

LH = [
    hall((432, 305), (432, 500), w=18),                     # sensors / crew quarters / CIC
    hall((365, 590), (512, 590), w=18),                     # the ring round the hangar: top (under the galley)
    hall((365, 590), (365, 985), w=18),                     # port side
    hall((365, 985), (512, 985), w=16),                     # bottom
    hall((330, 711), (356, 711), w=16),                     # armory -> ring
    hall((374, 806), (396, 806), w=16),                     # ring -> hangar side door
    hall((430, 1125), (430, 1300), w=18), hall((439, 1194), (468, 1194), w=16), hall((439, 1300), (470, 1300), w=16),   # aft side way
]
HALLS = [box(500, 218, 524, 322), box(500, 434, 524, 590), box(356, 476, 372, 495), box(480, 993, 496, 1010), box(274, 806, 290, 830), box(500, 1233, 524, 1270)] \
    + LH + [M(h) for h in LH] + [M(box(274, 806, 290, 830)), M(box(356, 476, 372, 495)), M(box(480, 993, 496, 1010))]

DC = [(512, 219, "h"), (512, 320, "h"), (512, 436, "h"), (512, 609, "h"), (512, 1235, "h"), (512, 1268, "h")]
DL = [(496, 244, "v"), (496, 281, "v"), (429, 307, "h"), (418, 421, "v"), (450, 370, "v"), (364, 478, "h"), (364, 493, "h"), (498, 475, "v"),
      (332, 711, "v"), (394, 806, "v"), (282, 808, "h"), (282, 828, "h"), (349, 925, "v"), (380, 955, "v"), (473, 891, "h"),
      (464, 977, "h"), (488, 995, "h"), (488, 1008, "h"), (495, 1136, "h"), (428, 1127, "h"), (469, 1194, "v"), (468, 1300, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("unity_capital", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(512, 760))
if __name__ == "__main__":
    run(S)
