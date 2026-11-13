#!/usr/bin/env python3
"""Covenant Troop Transport main deck, measured on the owner's HoloDeck sheet (1024 x 1535 px), mirrored about x 512.
10 px = 1 m. Bridge, sensors suite with console rooms, command & control, briefing room, lifts, troop bay, the
side rooms (ready rooms, barracks A-D, lockers & gear), deployment bays, armory / medbay, deployment corridors,
vehicle / dropship bay, engineering with its machine rooms, reactor and engine room. PROPOSED = not on the sheet."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 512.0
M = mirror(AX)
R = {}
R["Bridge"] = Polygon([(488, 164), (536, 164), (552, 180), (552, 224), (538, 238), (486, 238), (472, 224), (472, 180)])
R["Sensors Suite"] = box(470, 242, 554, 308)
R["Command & Control"] = circle(512, 377, 52)
R["Briefing Room"] = box(446, 432, 578, 500)
R["Troop Bay (Deployment Deck)"] = box(430, 535, 594, 886)
R["Vehicle / Dropship Bay"] = box(398, 902, 626, 1054)
R["Engineering Deck"] = box(440, 1072, 584, 1156)
R["Reactor Core"] = circle(512, 1217, 46)
R["Engine Room"] = box(456, 1300, 568, 1375)
L = {
    "Console Room": box(390, 282, 448, 342),
    "Deployment Bay": Polygon([(340, 350), (410, 350), (410, 505), (290, 505)]),
    "Lift": box(430, 503, 458, 531),
    "Ready Room": box(303, 536, 410, 606),
    "Barracks A": box(303, 610, 410, 694),
    "Barracks B": box(303, 698, 410, 782),
    "Lockers & Gear": box(303, 786, 410, 866),
    "Armory": box(258, 897, 360, 1015),
    "Deployment Corridor": box(170, 980, 254, 1048),
    "Lower Lift": box(350, 1020, 378, 1050),
    "Machine Room": box(345, 1068, 440, 1160),
}
TWIN = {"Barracks A": ("Barracks A", "Barracks C"), "Barracks B": ("Barracks B", "Barracks D"), "Armory": ("Armory", "Medbay")}
for k, g in L.items():
    a, b = TWIN.get(k, (k + " (port)", k + " (starboard)"))
    R[a] = g
    R[b] = M(g)

LH = [
    hall((448, 296), (470, 296), w=16),                     # console room -> sensors
    hall((420, 342), (420, 890), w=20),                     # side corridor down the troop bay
    hall((430, 385), (462, 385), w=16),                     # -> command & control
    hall((430, 455), (446, 455), w=16),                     # -> briefing room
    box(378, 870, 430, 890), hall((388, 870), (388, 1060), w=20),   # lower side corridor: armory, dropship bay, lift
    hall((360, 967), (378, 967), w=16),                     # -> armory
    box(312, 866, 328, 897),                                # lockers -> armory
    hall((437, 1160), (437, 1322), w=16), hall((437, 1212), (468, 1212), w=16), hall((437, 1322), (456, 1322), w=16),   # aft side way
]
HALLS = [box(504, 308, 520, 326), box(458, 500, 566, 535), box(504, 886, 520, 902), box(504, 1054, 520, 1072),
         box(504, 1156, 520, 1171), box(504, 1263, 520, 1300)] + LH + [M(h) for h in LH]

DC = [(512, 240, "h"), (512, 309, "h"), (512, 325, "h"), (512, 431, "h"), (512, 501, "h"), (512, 535, "h"), (512, 887, "h"),
      (512, 901, "h"), (512, 1055, "h"), (512, 1071, "h"), (512, 1157, "h"), (512, 1170, "h"), (512, 1264, "h"), (512, 1299, "h")]
DL = [(449, 296, "v"), (469, 296, "v"), (420, 343, "h"), (461, 385, "v"), (446, 455, "v"), (410, 435, "v"), (430, 517, "v"),
      (410, 574, "v"), (410, 652, "v"), (410, 740, "v"), (410, 825, "v"), (345, 608, "h"), (345, 696, "h"), (345, 784, "h"),
      (430, 607, "v"), (430, 782, "v"), (320, 867, "h"), (320, 896, "h"), (360, 967, "v"), (398, 967, "v"), (378, 1035, "v"),
      (256, 1000, "v"), (388, 1066, "h"), (440, 1126, "v"), (437, 1161, "h"), (467, 1212, "v"), (456, 1322, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]
PROP = [(256, 1000), (768, 1000)]

S = Ship("covenant_trooptransport", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(512, 980), proposed=PROP)
if __name__ == "__main__":
    run(S)
