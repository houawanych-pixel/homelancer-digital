#!/usr/bin/env python3
"""Covenant Capital Ship main deck, measured on the owner's HoloDeck sheet (1054 x 1492 px), mirrored about x 527.
10 px = 1 m. The capital layout (bridge, CIC, hangar, vehicle bay, engineering, reactor) with the Covenant's
crescent wings: weapon bay, chapel & shrine and coolant plant on each arm, reached along the arm's corridor.
PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 527.0
M = mirror(AX)
R = {}
R["Bridge (Command Deck)"] = circle(527, 193, 52)
R["CIC (Combat Information Center)"] = circle(527, 403, 53)
R["Hangar Bay"] = Polygon([(445, 633), (609, 633), (631, 655), (631, 859), (609, 881), (445, 881), (423, 859), (423, 655)])
R["Vehicle Bay"] = box(435, 903, 619, 993)
R["Engineering Deck"] = box(452, 1025, 602, 1098)
R["Reactor Core"] = circle(527, 1166, 46)
R["Engine Room B"] = box(489, 1253, 565, 1336)
L = {
    "Sensors Suite": box(427, 265, 501, 335),
    "Crew Quarters": box(360, 400, 440, 523),
    "Lift": box(467, 476, 495, 504),
    "Galley & Mess": box(357, 547, 443, 619),
    "Armory": box(269, 717, 363, 798),
    "Cargo Hold": box(287, 847, 390, 1003),
    "Engine Room": box(381, 1227, 456, 1314),
    "Weapon Bay": box(68, 660, 149, 755),
    "Chapel & Shrine": box(79, 800, 164, 871),
    "Coolant Plant": box(43, 943, 136, 1021),
}
TWIN = {"Sensors Suite": ("Sensors Suite", "Briefing Room"), "Galley & Mess": ("Galley & Mess", "Medbay"),
        "Cargo Hold": ("Cargo Hold A", "Cargo Hold B"), "Engine Room": ("Engine Room A", "Engine Room C"),
        "Weapon Bay": ("Weapon Bay A", "Weapon Bay B"), "Chapel & Shrine": ("Chapel & Shrine A", "Chapel & Shrine B"),
        "Coolant Plant": ("Coolant Plant A", "Coolant Plant B")}
for k, g in L.items():
    a, b = TWIN.get(k, (k + " (port)", k + " (starboard)"))
    R[a] = g
    R[b] = M(g)

LH = [
    hall((452, 340), (452, 540), w=18),                     # beside the CIC (sensors, crew quarters, lift)
    hall((495, 490), (515, 490), w=16),                     # lift -> spine
    hall((443, 562), (515, 562), w=16),                     # galley -> spine
    hall((402, 621), (402, 1000), w=18),                    # down the hangar's port side
    hall((363, 730), (393, 730), w=16),                     # armory -> side run
    hall((164, 830), (393, 830), w=16),                     # the crescent arm's corridor (chapel)
    hall((411, 950), (435, 950), w=16),                     # side run -> vehicle bay
    hall((432, 1060), (452, 1060), w=16), hall((432, 1060), (432, 1227), w=16), hall((432, 1161), (481, 1161), w=16),   # aft side way
]
SMALL = [box(385, 523, 401, 547), box(497, 881, 517, 903), box(495, 993, 515, 1025), box(114, 755, 130, 800), box(118, 871, 134, 943)]
HALLS = [box(515, 246, 539, 350), box(515, 456, 539, 633), box(517, 1098, 537, 1120), box(517, 1212, 537, 1253)] \
    + SMALL + [M(b) for b in SMALL] + LH + [M(h) for h in LH]

DC = [(527, 248, "h"), (527, 348, "h"), (527, 458, "h"), (527, 631, "h"), (527, 1100, "h"), (527, 1118, "h"), (527, 1214, "h"), (527, 1251, "h")]
DL = [(503, 305, "v"), (452, 337, "h"), (467, 400, "v"), (444, 495, "v"), (464, 490, "v"), (497, 490, "v"), (393, 525, "h"),
      (393, 545, "h"), (445, 562, "v"), (402, 621, "h"), (417, 690, "v"), (365, 730, "v"), (392, 935, "v"), (166, 830, "v"),
      (122, 757, "h"), (122, 798, "h"), (126, 873, "h"), (126, 941, "h"), (507, 883, "h"), (507, 901, "h"), (433, 950, "v"),
      (505, 995, "h"), (505, 1023, "h"), (450, 1060, "v"), (432, 1225, "h"), (479, 1161, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("covenant_capital", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(527, 760), proposed=[(433, 950), (621, 950)])
if __name__ == "__main__":
    run(S)
