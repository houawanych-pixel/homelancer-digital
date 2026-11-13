#!/usr/bin/env python3
"""Unity Destroyer main deck, measured on the owner's HoloDeck sheet (1024 x 1536 px), mirrored about x 512.
10 px = 1 m. Long and narrow: one centre spine; engine pods on the flanks (engine access, coolant, power core).
PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 512.0
M = mirror(AX)
R = {}
R["Bridge"] = circle(512, 182, 42)
R["Sensors Suite"] = box(476, 249, 548, 301)
R["CIC (Combat Information Center)"] = circle(512, 407, 52)
R["Lift"] = box(498, 583, 526, 611)
R["Launch Bay"] = box(474, 730, 550, 925)
R["Engineering Deck"] = box(400, 1018, 624, 1120)
R["Reactor Core"] = circle(512, 1197, 44)
R["Engine Room"] = box(458, 1270, 566, 1350)
L = {
    "Crew Quarters": Polygon([(381, 430), (405, 404), (457, 404), (457, 531), (381, 531)]),
    "Galley & Mess": box(381, 558, 460, 656),
    "Armory": box(370, 679, 442, 765),
    "Cargo Hold": Polygon([(358, 880), (375, 863), (432, 863), (432, 996), (358, 996)]),
    "Engine Access": box(252, 696, 318, 773),
    "Coolant System": box(252, 802, 318, 872),
    "Power Core": box(252, 901, 318, 990),
}
TWIN = {"Galley & Mess": "Medbay", "Cargo Hold": "Missile Magazine"}
for k, g in L.items():
    R[k if k in TWIN else k + " (port)"] = g
    R[TWIN.get(k, k + " (starboard)")] = M(g)

LH = [
    hall((457, 510), (500, 510), w=16),                     # crew quarters -> spine
    hall((405, 765), (405, 863), w=16),                     # armory -> cargo hold
    hall((318, 823), (405, 823), w=16),                     # engine pod -> centre
    hall((432, 978), (500, 978), w=16),                     # cargo hold -> aft spine
    hall((432, 1120), (432, 1240), w=16), hall((440, 1197), (468, 1197), w=16),   # engineering's side way to the reactor
]
SMALL = [box(414, 531, 430, 558), box(400, 656, 416, 679), box(276, 773, 292, 802), box(276, 872, 292, 901)]
HALLS = [box(502, 224, 522, 249), box(502, 301, 522, 355), box(500, 459, 524, 583), box(500, 611, 524, 730), box(500, 925, 524, 1018),
         box(502, 1120, 522, 1153), box(502, 1241, 522, 1270)] + SMALL + [M(b) for b in SMALL] + LH + [M(h) for h in LH]

DC = [(512, 226, "h"), (512, 247, "h"), (512, 303, "h"), (512, 353, "h"), (512, 461, "h"), (512, 583, "h"), (512, 611, "h"),
      (512, 728, "h"), (512, 927, "h"), (512, 1016, "h"), (512, 1122, "h"), (512, 1151, "h"), (512, 1243, "h"), (512, 1268, "h")]
DL = [(459, 510, "v"), (422, 533, "h"), (422, 556, "h"), (408, 658, "h"), (408, 677, "h"), (405, 767, "h"), (405, 861, "h"),
      (320, 823, "v"), (284, 775, "h"), (284, 800, "h"), (284, 874, "h"), (284, 899, "h"), (434, 978, "v"), (432, 1122, "h"),
      (468, 1197, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("unity_destroyer", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(512, 830))
if __name__ == "__main__":
    run(S)
