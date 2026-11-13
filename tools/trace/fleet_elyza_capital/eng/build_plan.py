#!/usr/bin/env python3
"""Elyza Capital Ship main deck (the same layout as the Unity Capital, measured on its own sheet), measured on the owner's HoloDeck sheet (1024 x 1536 px), mirrored about x 510.
10 px = 1 m. A hangar inside a ring of hallways; command fore (bridge, CIC), engineering aft. Unlabelled hull
compartments are hull. PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 510.0
M = mirror(AX)
R = {}
R["Bridge Command Deck"] = circle(510, 190, 48)
R["CIC (Combat Information Center)"] = circle(510, 399, 55)
R["Hangar Bay"] = Polygon([(414, 634), (606, 634), (624, 652), (624, 865), (606, 883), (414, 883), (396, 865), (396, 652)])
R["Vehicle Bay"] = box(386, 895, 634, 974)
R["Engineering Deck"] = Polygon([(330, 1030), (690, 1030), (690, 1110), (672, 1125), (348, 1125), (330, 1110)])
R["Reactor Core"] = circle(510, 1197, 47)
R["Engine Room"] = box(458, 1272, 562, 1358)
L = {
    "Sensors Suite": box(415, 270, 491, 330),
    "Crew Quarters": box(335, 403, 408, 500),
    "Galley & Mess": Polygon([(323, 519), (408, 519), (408, 585), (393, 600), (323, 600)]),
    "Lift": box(468, 480, 496, 508),
    "Armory": box(237, 730, 330, 812),
    "Cargo Hold": Polygon([(213, 856), (233, 836), (344, 836), (344, 978), (213, 978)]),
}
TWIN = {"Sensors Suite": "Briefing Room", "Galley & Mess": "Medbay", "Cargo Hold": "Cargo Hold B", "Crew Quarters": "Crew Quarters B"}
LN = {"Cargo Hold": "Cargo Hold A", "Crew Quarters": "Crew Quarters A"}
for k, g in L.items():
    R[LN.get(k, k if k in TWIN else k + " (port)")] = g
    R[TWIN.get(k, k + " (starboard)")] = M(g)

LH = [
    hall((428, 330), (428, 512), w=18),                     # sensors / crew quarters / CIC
    hall((365, 612), (510, 612), w=18),                     # the ring round the hangar: top (under the galley)
    hall((365, 612), (365, 985), w=18),                     # port side
    hall((365, 985), (510, 985), w=16),                     # bottom
    hall((330, 740), (356, 740), w=16),                     # armory -> ring
    hall((374, 806), (396, 806), w=16),                     # ring -> hangar side door
    hall((428, 1125), (428, 1300), w=18), hall((437, 1197), (465, 1197), w=16), hall((437, 1300), (458, 1300), w=16),   # aft side way
]
HALLS = [box(498, 238, 522, 344), box(498, 454, 522, 612), box(262, 812, 278, 836), box(354, 500, 370, 519), box(478, 993, 494, 1030),
         box(498, 1244, 522, 1272)] + LH + [M(h) for h in LH] + [M(box(262, 812, 278, 836)), M(box(354, 500, 370, 519)), M(box(478, 993, 494, 1030))]

DC = [(510, 240, "h"), (510, 342, "h"), (510, 456, "h"), (510, 632, "h"), (510, 1246, "h"), (510, 1270, "h")]
DL = [(496, 300, "v"), (430, 332, "h"), (416, 450, "v"), (453, 399, "v"), (362, 502, "h"), (362, 517, "h"), (496, 494, "v"),
      (332, 740, "v"), (394, 806, "v"), (270, 814, "h"), (270, 834, "h"), (349, 921, "v"), (380, 951, "v"), (463, 893, "h"),
      (463, 976, "h"), (486, 995, "h"), (486, 1028, "h"), (494, 1137, "h"), (426, 1127, "h"), (465, 1197, "v"), (458, 1300, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("elyza_capital", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(510, 760))
if __name__ == "__main__":
    run(S)
