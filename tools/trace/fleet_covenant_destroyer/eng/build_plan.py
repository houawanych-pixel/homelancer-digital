#!/usr/bin/env python3
"""Covenant Destroyer main deck, measured on the owner's HoloDeck sheet (1024 x 1536 px), mirrored about x 512.
10 px = 1 m. Bridge, twin sensors, CIC with its locker rooms, crew quarters, galley / medbay, armory, launch bay,
weapons bays, missile magazine, cargo holds, engineering, reactor, machine rooms and engine rooms.
PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 512.0
M = mirror(AX)
R = {}
R["Bridge"] = Polygon([(486, 172), (538, 172), (552, 186), (552, 238), (538, 250), (486, 250), (472, 238), (472, 186)])
R["CIC"] = circle(512, 377, 50)
R["Armory"] = box(462, 548, 562, 618)
R["Launch Bay"] = Polygon([(431, 656), (593, 656), (609, 672), (609, 784), (415, 784), (415, 672)])
R["Missile Magazine"] = box(440, 802, 584, 872)
R["Engineering"] = Polygon([(448, 980), (576, 980), (592, 996), (592, 1052), (432, 1052), (432, 996)])
R["Reactor Core"] = circle(512, 1110, 52)
L = {
    "Sensors": box(426, 256, 504, 316),
    "Locker Room": box(410, 346, 457, 406),
    "Crew Quarters": box(372, 410, 458, 490),
    "Galley & Mess": box(372, 494, 458, 586),
    "Weapons Bay": box(262, 662, 395, 770),
    "Cargo Hold": box(360, 877, 447, 975),
    "Engine Room": box(368, 1120, 452, 1185),
    "Lift": box(468, 468, 496, 500),
}
TWIN = {"Galley & Mess": ("Galley & Mess", "Medbay")}
for k, g in L.items():
    a, b = TWIN.get(k, (k + " (port)", k + " (starboard)"))
    R[a] = g
    R[b] = M(g)

LH = [
    hall((457, 376), (464, 376), w=16),                     # locker room -> CIC
    hall((458, 454), (500, 454), w=16),                     # crew quarters -> spine
    hall((458, 516), (500, 516), w=16),                     # galley -> spine
    hall((405, 586), (405, 872), w=20),                     # side corridor: galley, weapons bay, launch bay, magazine, cargo
    hall((415, 833), (440, 833), w=16),                     # -> missile magazine
    hall((401, 975), (401, 1048), w=18), hall((410, 1024), (432, 1024), w=16),   # aft side way -> engineering
    box(368, 1048, 450, 1116),                              # machine room (engine room's fore half)
    hall((450, 1108), (464, 1108), w=16),                   # -> reactor
]
HALLS = [box(504, 250, 520, 327), box(500, 427, 524, 548), box(504, 618, 520, 656), box(504, 784, 520, 802),
         box(452, 878, 572, 975), box(504, 1052, 520, 1060)] + LH + [M(h) for h in LH]

DC = [(512, 251, "h"), (512, 326, "h"), (512, 427, "h"), (512, 548, "h"), (512, 619, "h"), (512, 655, "h"), (512, 785, "h"), (512, 801, "h"),
      (512, 875, "h"), (512, 978, "h"), (512, 1055, "h")]
DL = [(504, 291, "v"), (460, 376, "v"), (418, 408, "h"), (459, 454, "v"), (415, 492, "h"), (459, 516, "v"), (460, 582, "v"),
      (405, 587, "h"), (395, 727, "v"), (415, 781, "v"), (439, 833, "v"), (405, 875, "h"), (449, 930, "v"), (401, 976, "h"),
      (431, 1024, "v"), (461, 1108, "v"), (411, 1118, "h"), (498, 484, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("covenant_destroyer", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(512, 720), proposed=[(498, 484), (526, 484)])
if __name__ == "__main__":
    run(S)
