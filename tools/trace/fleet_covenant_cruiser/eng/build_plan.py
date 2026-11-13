#!/usr/bin/env python3
"""Covenant Cruiser main deck, measured on the owner's HoloDeck sheet (1182 x 1330 px), mirrored about x 591.
10 px = 1 m. Bridge, sensors suite, CIC with its two console rooms, crew quarters, galley / medbay, hangar,
armories, cargo holds, vehicle bay, engineering, reactor, engine room, and on each crescent wing a weapon bay,
chapel / shrine and coolant plant. PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 591.0
M = mirror(AX)
R = {}
R["Bridge"] = circle(591, 175, 46)
R["Sensors Suite"] = box(556, 238, 626, 290)
R["CIC (Combat Information Center)"] = circle(591, 376, 54)
R["Hangar Bay"] = Polygon([(514, 601), (668, 601), (682, 615), (682, 768), (500, 768), (500, 615)])
R["Vehicle Bay"] = box(540, 784, 642, 881)
R["Engineering Deck"] = box(486, 904, 696, 958)
R["Reactor Core"] = circle(591, 1016, 44)
R["Engine Room"] = box(552, 1073, 630, 1171)
L = {
    "Console Room": box(483, 312, 517, 383),
    "Crew Quarters": box(457, 421, 536, 498),
    "Lift": box(553, 470, 583, 500),
    "Galley & Mess": box(457, 520, 551, 592),
    "Armory": box(402, 650, 481, 738),
    "Cargo Lift": box(437, 742, 465, 768),
    "Cargo Hold": box(449, 784, 527, 880),
    "Weapon Bay": box(80, 665, 178, 748),
    "Chapel / Shrine": box(206, 712, 382, 795),
    "Coolant Systems": box(70, 790, 178, 870),
}
TWIN = {"Galley & Mess": ("Galley & Mess", "Medbay")}
for k, g in L.items():
    a, b = TWIN.get(k, (k + " (port)", k + " (starboard)"))
    R[a] = g
    R[b] = M(g)

LH = [
    hall((517, 348), (547, 348), w=16),                     # console room -> CIC
    hall((500, 383), (500, 421), w=16),                     # console room -> crew quarters
    hall((551, 553), (583, 553), w=16),                     # galley -> spine
    hall((491, 592), (491, 776), w=18),                     # between the armory and the hangar
    hall((391, 634), (391, 776), w=18),                     # between the chapel and the armory
    hall((382, 642), (432, 642), w=16),                     # -> armory top door
    hall((178, 812), (298, 812), w=16), hall((290, 795), (290, 812), w=16),   # chapel -> coolant
    hall((477, 880), (477, 945), w=18),                     # cargo -> engineering side door
    hall((501, 958), (501, 1098), w=18), hall((501, 1016), (549, 1016), w=16), hall((501, 1098), (552, 1098), w=16),   # aft side way
]
SMALL = [box(178, 705, 206, 770), box(490, 498, 506, 520)]
HALLS = [box(583, 221, 599, 238), box(547, 290, 635, 306), box(559, 306, 623, 328), box(583, 430, 599, 602), box(382, 768, 800, 784),
         box(527, 822, 540, 838), box(642, 822, 655, 838), box(583, 881, 599, 904), box(583, 958, 599, 973),
         box(583, 1060, 599, 1073)] + SMALL + [M(b) for b in SMALL] + LH + [M(h) for h in LH]

DC = [(591, 222, "h"), (591, 237, "h"), (591, 291, "h"), (591, 431, "h"), (591, 602, "h"), (591, 882, "h"), (591, 903, "h"),
      (591, 959, "h"), (591, 972, "h"), (591, 1061, "h"), (591, 1072, "h")]
DL = [(567, 327, "h"), (544, 348, "v"), (518, 348, "v"), (500, 384, "h"), (500, 420, "h"), (498, 499, "h"), (498, 519, "h"),
      (582, 485, "v"), (552, 553, "v"), (491, 593, "h"), (482, 709, "v"), (500, 673, "v"), (500, 742, "v"), (423, 649, "h"),
      (383, 759, "v"), (179, 719, "v"), (205, 760, "v"), (290, 796, "h"), (179, 812, "v"), (451, 767, "h"), (493, 785, "h"),
      (562, 767, "h"), (562, 785, "h"), (528, 830, "v"), (539, 830, "v"), (477, 881, "h"), (487, 936, "v"), (501, 959, "h"),
      (547, 1016, "v"), (553, 1098, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]
PROP = [(500, 420), (682, 420), (582, 485), (600, 485), (491, 593), (691, 593), (451, 767), (731, 767)]

S = Ship("covenant_cruiser", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(591, 690), proposed=PROP)
if __name__ == "__main__":
    run(S)
