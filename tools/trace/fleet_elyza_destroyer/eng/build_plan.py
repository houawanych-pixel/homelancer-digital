#!/usr/bin/env python3
"""Elyza Destroyer main deck, measured on the owner's HoloDeck sheet (1024 x 1536 px), mirrored about x 511.
10 px = 1 m. Sensors in the nose, bridge, CIC; a centre spine past the launch bay, missile magazine and supply;
cargo holds and the weapon / coolant pods on the flanks; engineering, reactor and engine room aft.
PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 511.0
M = mirror(AX)
R = {}
R["Sensors"] = Polygon([(511, 120), (550, 160), (550, 184), (472, 184), (472, 160)])
R["Bridge"] = circle(511, 258, 36)
R["CIC"] = Polygon([(483, 350), (539, 350), (551, 362), (551, 452), (539, 464), (483, 464), (471, 452), (471, 362)])
R["Lift"] = box(497, 553, 525, 581)
R["Launch Bay"] = Polygon([(447, 613), (575, 613), (591, 629), (591, 713), (575, 729), (447, 729), (431, 713), (431, 629)])
R["Missile Magazine"] = Polygon([(440, 738), (582, 738), (598, 754), (598, 815), (582, 831), (440, 831), (424, 815), (424, 754)])
R["Supply"] = Polygon([(438, 856), (584, 856), (600, 872), (600, 930), (584, 946), (438, 946), (422, 930), (422, 872)])
R["Engineering"] = box(414, 975, 608, 1088)
R["Reactor Core"] = circle(511, 1172, 43)
R["Engine Room"] = box(437, 1244, 585, 1336)
L = {
    "Crew Quarters": Polygon([(358, 350), (390, 314), (456, 314), (456, 460), (358, 460)]),
    "Galley & Mess": box(358, 486, 466, 583),
    "Armory": box(318, 607, 408, 731),
    "Cargo Hold A": box(288, 777, 386, 936),
    "Weapon Systems": box(144, 900, 208, 1037),
    "Coolant": box(156, 1040, 220, 1181),
}
TWIN = {"Galley & Mess": "Medbay", "Cargo Hold A": "Cargo Hold B"}
for k, g in L.items():
    R[k if k in TWIN else k + " (port)"] = g
    R[TWIN.get(k, k + " (starboard)")] = M(g)

LH = [
    hall((466, 528), (499, 528), w=16),                     # galley -> spine
    hall((408, 638), (431, 638), w=16),                     # armory -> launch bay
    hall((364, 731), (364, 777), w=16),                     # armory -> cargo hold
    hall((386, 896), (422, 896), w=16),                     # cargo hold -> supply
    hall((170, 884), (288, 884), w=16),                     # weapon pod -> cargo hold
    hall((395, 1000), (395, 1290), w=16), hall((403, 1169), (468, 1169), w=16), hall((403, 1280), (437, 1280), w=16),   # aft side way
]
SMALL = [box(423, 460, 439, 486), box(381, 583, 397, 607), box(449, 831, 465, 856)]
HALLS = [box(501, 184, 521, 222), box(501, 294, 521, 350), box(499, 464, 523, 553), box(499, 581, 523, 613), box(501, 946, 521, 975),
         box(501, 1088, 521, 1129), box(501, 1215, 521, 1244)] + SMALL + [M(b) for b in SMALL] + LH + [M(h) for h in LH]

DC = [(511, 186, "h"), (511, 220, "h"), (511, 296, "h"), (511, 348, "h"), (511, 466, "h"), (511, 553, "h"), (511, 581, "h"),
      (511, 611, "h"), (511, 733, "h"), (511, 948, "h"), (511, 973, "h"), (511, 1090, "h"), (511, 1127, "h"), (511, 1217, "h"), (511, 1242, "h")]
DL = [(464, 366, "v"), (431, 462, "h"), (431, 484, "h"), (468, 528, "v"), (389, 585, "h"), (389, 605, "h"), (410, 638, "v"),
      (429, 638, "v"), (364, 733, "h"), (364, 775, "h"), (388, 896, "v"), (420, 896, "v"), (457, 833, "h"), (457, 854, "h"),
      (180, 898, "h"), (288, 884, "v"), (190, 1038, "h"), (410, 1019, "v"), (466, 1169, "v"), (435, 1280, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("elyza_destroyer", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(511, 680))
if __name__ == "__main__":
    run(S)
