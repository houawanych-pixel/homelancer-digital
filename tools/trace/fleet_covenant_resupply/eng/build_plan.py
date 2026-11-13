#!/usr/bin/env python3
"""Covenant Resupply Ship main deck, measured on the owner's HoloDeck sheet (1128 x 1394 px), mirrored about x 567.
10 px = 1 m. Bridge, sensors suite / CIC, crew quarters, galley / medbay, the lift in the spine, cargo transfer hub,
vehicle / loader bay with its two lifts, the two long cargo holds, coolant & systems on the wings, storage /
refrigerated stores, munitions resupply, engineering, reactor and engine room. PROPOSED = not on the sheet."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 567.0
M = mirror(AX)
R = {}
R["Bridge"] = circle(567, 157, 40)
R["Lift"] = box(555, 378, 579, 400)
R["Cargo Transfer Hub"] = Polygon([(525, 533), (609, 533), (633, 557), (633, 627), (609, 651), (525, 651), (501, 627), (501, 557)])
R["Vehicle / Loader Bay"] = box(468, 668, 666, 858)
R["Munitions Resupply"] = box(472, 876, 662, 954)
R["Engineering Deck"] = Polygon([(394, 976), (740, 976), (760, 996), (760, 1048), (374, 1048), (374, 996)])
R["Reactor Core"] = circle(567, 1104, 46)
R["Engine Room"] = box(512, 1170, 622, 1238)
L = {
    "Sensors Suite": box(463, 198, 547, 250),
    "Crew Quarters": box(449, 258, 547, 372),
    "Galley & Mess": box(449, 400, 547, 505),
    "Cargo Hold": Polygon([(317, 282), (391, 282), (411, 302), (411, 750), (391, 770), (317, 770), (297, 750), (297, 302)]),
    "Coolant & Systems": box(106, 650, 202, 780),
    "Cargo Lift": box(420, 760, 448, 790),
    "Storage & Supplies": box(310, 830, 448, 946),
}
TWIN = {"Sensors Suite": ("Sensors Suite", "CIC"), "Galley & Mess": ("Galley & Mess", "Medbay"),
        "Cargo Hold": ("Cargo Hold A", "Cargo Hold B"), "Storage & Supplies": ("Storage & Supplies", "Refrigerated Stores")}
for k, g in L.items():
    a, b = TWIN.get(k, (k + " (port)", k + " (starboard)"))
    R[a] = g
    R[b] = M(g)

LH = [
    hall((439, 400), (439, 589), w=20),                     # beside cargo hold A: galley -> cross hall
    hall((409, 589), (501, 589), w=20),                     # cross hall: cargo hold -> hub
    hall((458, 579), (458, 976), w=20),                     # beside the vehicle bay: lift, storage -> engineering
    hall((202, 705), (297, 705), w=16),                     # coolant -> cargo hold
    hall((490, 1048), (490, 1104), w=18), hall((490, 1104), (523, 1104), w=16),   # engineering -> reactor side
]
HALLS = [box(547, 197, 587, 533), box(531, 372, 603, 400), box(559, 651, 575, 668), box(559, 858, 575, 876), box(448, 958, 686, 976),
         box(559, 1048, 575, 1060), box(559, 1150, 575, 1170), box(343, 770, 359, 830), box(486, 372, 502, 400)] + LH + [M(h) for h in LH] + [M(box(343, 770, 359, 830)), M(box(486, 372, 502, 400))]

DC = [(567, 197, "h"), (567, 379, "h"), (567, 534, "h"), (567, 652, "h"), (567, 667, "h"), (567, 859, "h"), (567, 875, "h"),
      (567, 1049, "h"), (567, 1059, "h"), (567, 1151, "h"), (567, 1169, "h")]
DL = [(547, 225, "v"), (497, 254, "h"), (547, 308, "v"), (494, 373, "h"), (494, 399, "h"), (547, 458, "v"), (449, 421, "v"),
      (501, 589, "v"), (410, 589, "v"), (297, 705, "v"), (203, 705, "v"), (351, 771, "h"), (351, 829, "h"), (448, 775, "v"),
      (468, 723, "v"), (448, 880, "v"), (540, 977, "h"), (490, 1049, "h"), (522, 1104, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]
PROP = [(567, 379)]

S = Ship("covenant_resupply", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(567, 760), proposed=PROP)
if __name__ == "__main__":
    run(S)
