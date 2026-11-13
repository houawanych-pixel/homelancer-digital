#!/usr/bin/env python3
"""Elyza Resupply Ship main deck, measured on the owner's HoloDeck sheet (1024 x 1536 px), mirrored about x 515.
10 px = 1 m. Six cargo holds (A-F) either side of the long loading / vehicle bay; stores below them; engineering,
reactor and engine room aft. Sensors (port) and CIC (starboard) are twins in shape. PROPOSED = not on the sheet."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 515.0
M = mirror(AX)
R = {}
R["Bridge"] = Polygon([(490, 150), (540, 150), (566, 175), (566, 224), (464, 224), (464, 175)])
R["Loading / Vehicle Bay"] = box(476, 505, 554, 930)
R["Engineering Deck"] = box(414, 1047, 616, 1139)
R["Reactor Core"] = circle(515, 1195, 46)
R["Engine Room"] = box(443, 1274, 587, 1375)
L = {
    "Sensors Suite": box(436, 236, 500, 300),
    "Crew Quarters": box(365, 321, 451, 402),
    "Galley / Mess": box(355, 410, 498, 466),
    "Cargo Hold A": box(245, 480, 403, 600), "Cargo Hold C": box(256, 631, 402, 759), "Cargo Hold E": box(254, 791, 401, 929),
    "General Storage": box(324, 935, 498, 983),
    "Munitions Resupply": box(328, 990, 498, 1035),
}
TWIN = {"Sensors Suite": "CIC", "Galley / Mess": "Medbay", "Cargo Hold A": "Cargo Hold B", "Cargo Hold C": "Cargo Hold D",
        "Cargo Hold E": "Cargo Hold F", "General Storage": "Refrigerated Stores", "Munitions Resupply": "Spare Parts"}
for k, g in L.items():
    R[k if k in TWIN else k + " (port)"] = g
    R[TWIN.get(k, k + " (starboard)")] = M(g)

LH = [
    hall((451, 387), (503, 387), w=16),                     # crew quarters -> centre corridor
    hall((331, 440), (355, 440), w=16), hall((331, 440), (331, 480), w=16),   # galley -> cargo hold A
    hall((440, 490), (440, 930), w=50),                     # beside the loading bay (cargo holds)
]
SMALL = [box(314, 600, 330, 631), box(314, 759, 330, 791)]
HALLS = [box(503, 224, 527, 505), box(503, 930, 527, 1047), box(505, 1241, 525, 1274)] + SMALL + [M(b) for b in SMALL] + LH + [M(h) for h in LH]

DC = [(515, 226, "h"), (515, 505, "h"), (515, 1047, "h"), (515, 1144, "h"), (515, 1243, "h"), (515, 1272, "h")]
DL = [(501, 265, "v"), (453, 387, "v"), (500, 447, "v"), (357, 440, "v"), (331, 478, "h"), (322, 602, "h"), (322, 629, "h"),
      (322, 761, "h"), (322, 789, "h"), (408, 533, "v"), (408, 695, "v"), (408, 853, "v"), (470, 607, "v"), (470, 736, "v"),
      (470, 856, "v"), (455, 932, "h"), (500, 964, "v"), (500, 1012, "v"), (430, 1041, "h")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("elyza_resupply", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(515, 700))
if __name__ == "__main__":
    run(S)
