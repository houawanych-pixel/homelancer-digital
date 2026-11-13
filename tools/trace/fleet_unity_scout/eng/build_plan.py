#!/usr/bin/env python3
"""Unity Scout main deck, measured on the owner's HoloDeck sheet (1024 x 1536 px), mirrored about x 512.
10 px = 1 m. The smallest: cockpit, the round sensors / recon suite, sensor arrays in the wings, bunk and med,
the mission room, engineering, the engine room and an engine access pod each side. No reactor: the sabotage target
is the engine room's drive. PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 512.0
M = mirror(AX)
R = {}
R["Bridge (Cockpit)"] = Polygon([(512, 303), (575, 370), (575, 457), (449, 457), (449, 370)])
R["Sensors / Recon Suite"] = circle(512, 560, 84)
R["Mission / Data Room"] = box(411, 825, 613, 945)
R["Engineering"] = box(381, 952, 643, 1064)
R["Engine Room"] = box(431, 1075, 593, 1136)
L = {
    "Sensor Array": Polygon([(149, 680), (160, 665), (384, 632), (384, 684), (160, 684)]),
    "Bunk (4)": box(389, 686, 486, 780),
    "Lift": box(458, 786, 486, 814),
    "Engine Access": box(232, 953, 299, 1294),
}
TWIN = {"Sensor Array": ("Sensor Array (port)", "Sensor Array (starboard)"), "Bunk (4)": ("Bunk (4)", "Med / Galley"), "Lift": ("Lift (port)", "Lift (starboard)"),
        "Engine Access": ("Engine Access (L)", "Engine Access (R)")}
for k, g in L.items():
    a, b = TWIN[k]
    R[a] = g
    R[b] = M(g)

LH = [
    hall((384, 668), (512, 668), w=14),                     # under the sensors suite: arrays, bunk, med
    hall((299, 1001), (381, 1001), w=16),                   # engine access pod -> engineering
]
HALLS = [box(502, 457, 522, 476), box(502, 644, 522, 661), box(496, 675, 528, 825)] + LH + [M(h) for h in LH]

DC = [(512, 459, "h"), (512, 474, "h"), (512, 646, "h"), (512, 659, "h"), (512, 825, "h"), (512, 948, "h"), (512, 1069, "h")]
DL = [(386, 668, "v"), (457, 680, "h"), (491, 747, "v"), (491, 800, "v"), (301, 1001, "v"), (379, 1001, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("unity_scout", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(265, 1100), proposed=[(491, 800), (533, 800)])
if __name__ == "__main__":
    run(S)
