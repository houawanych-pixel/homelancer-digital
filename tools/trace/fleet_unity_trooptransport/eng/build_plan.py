#!/usr/bin/env python3
"""Unity Troop Transport main deck, measured on the owner's HoloDeck sheet (927 x 1697 px), mirrored about x 464.
10 px = 1 m. The long troop bay down the middle with a run either side of it; command fore, engineering aft.
PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 464.0
M = mirror(AX)
R = {}
R["Bridge"] = Polygon([(432, 165), (496, 165), (518, 187), (518, 262), (410, 262), (410, 187)])
R["Sensors & Comms"] = box(387, 272, 541, 340)
R["Troop Bay"] = box(398, 490, 530, 1078)
R["Engineering"] = box(336, 1104, 592, 1228)
R["Reactor Core"] = circle(464, 1333, 58)
L = {
    "Lift": box(344, 490, 370, 516),
    "Briefing Room": box(317, 354, 426, 464),
    "Barracks": box(254, 522, 362, 751),
    "Armory": box(240, 785, 360, 902),
    "Vehicle Bay": box(240, 944, 370, 1079),
}
TWIN = {"Briefing Room": "Medbay", "Armory": "Lockers", "Vehicle Bay": "Ready Room"}
for k, g in L.items():
    R[k if k in TWIN else k + " (port)"] = g
    R[TWIN.get(k, k + " (starboard)")] = M(g)

LH = [
    hall((374, 480), (444, 480), w=14),                     # from the command corridor to the troop bay's side run
    hall((381, 473), (381, 1090), w=14),                    # down the troop bay's side
]
HALLS = [box(442, 343, 486, 488), box(454, 1078, 474, 1104), box(454, 1228, 474, 1275), box(290, 751, 306, 785)] \
    + LH + [M(h) for h in LH] + [M(box(290, 751, 306, 785))]

DC = [(464, 266, "h"), (464, 342, "h"), (464, 489, "h"), (464, 1080, "h"), (464, 1102, "h"), (464, 1230, "h"), (464, 1273, "h")]
DL = [(372, 503, "v"), (434, 410, "v"), (367, 635, "v"), (392, 700, "v"), (392, 940, "v"), (298, 753, "h"), (298, 783, "h"), (367, 824, "v"),
      (372, 990, "v"), (381, 1100, "h")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("unity_trooptransport", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(305, 1010), proposed=[(464, 1230), (372, 503)])
if __name__ == "__main__":
    run(S)
