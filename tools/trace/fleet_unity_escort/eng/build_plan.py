#!/usr/bin/env python3
"""Unity Escort main deck, measured on the owner's HoloDeck sheet (993 x 1583 px), mirrored about x 497.
10 px = 1 m. Small: bridge, sensors, CIC fore; bunks / galley and armory / stores either side of one spine;
engineering, reactor and two engine rooms aft. PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 497.0
M = mirror(AX)
R = {}
R["Bridge"] = Polygon([(445, 223), (549, 223), (583, 257), (583, 343), (411, 343), (411, 257)])
R["Sensors"] = box(443, 369, 551, 470)
R["CIC Tactical"] = circle(497, 558, 62)
R["Engineering Deck"] = box(293, 925, 701, 1070)
R["Reactor Core"] = circle(497, 1128, 50)
L = {
    "Crew Bunks": box(300, 540, 433, 712),
    "Armory": box(300, 765, 470, 915),
    "Engine Room A": box(384, 1190, 487, 1300),
}
TWIN = {"Crew Bunks": "Galley / Med", "Armory": "Support & Stores", "Engine Room A": "Engine Room B"}
for k, g in L.items():
    R[k] = g
    R[TWIN[k]] = M(g)

LH = [
    hall((433, 667), (485, 667), w=16),                     # bunks -> spine
    hall((300, 728), (485, 728), w=16),                     # across, between bunks and armory
    hall((392, 1070), (392, 1190), w=16),                   # engineering -> engine room
]
SMALL = [box(378, 736, 394, 765)]
HALLS = [box(487, 343, 507, 369), box(487, 470, 507, 496), box(485, 620, 509, 925)] + SMALL + [M(b) for b in SMALL] + LH + [M(h) for h in LH]

DC = [(497, 345, "h"), (497, 367, "h"), (497, 472, "h"), (497, 494, "h"), (497, 620, "h"), (497, 925, "h"), (497, 1074, "h")]
DL = [(434, 558, "v"), (435, 667, "v"), (386, 716, "h"), (386, 738, "h"), (386, 763, "h"), (477, 800, "v"), (370, 920, "h"),
      (392, 1072, "h"), (392, 1188, "h")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("unity_escort", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(609, 840))
if __name__ == "__main__":
    run(S)
