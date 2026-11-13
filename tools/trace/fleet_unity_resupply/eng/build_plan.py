#!/usr/bin/env python3
"""Unity Resupply Ship main deck, measured on the owner's HoloDeck sheet (1024 x 1536 px), mirrored about x 514.
10 px = 1 m. Two long cargo holds either side of the loader & vehicle bay, stores on the flanks, the transfer hub
across the stern. PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 514.0
M = mirror(AX)
R = {}
R["Bridge"] = box(471, 151, 557, 207)
R["Sensors Suite"] = box(481, 238, 547, 314)
R["CIC"] = Polygon([(486, 322), (542, 322), (562, 342), (562, 390), (542, 410), (486, 410), (466, 390), (466, 342)])
R["Cargo Control"] = Polygon([(486, 533), (542, 533), (558, 549), (558, 574), (542, 590), (486, 590), (470, 574), (470, 549)])
R["Loader & Vehicle Bay"] = box(467, 645, 561, 963)
R["Cargo Transfer Hub"] = box(380, 980, 648, 1040)
R["Engineering Deck"] = box(467, 1046, 561, 1140)
R["Reactor Core"] = circle(514, 1196, 40)
R["Engine Room"] = box(472, 1256, 556, 1328)
L = {
    "Crew Quarters": box(337, 324, 418, 446),
    "Galley & Mess": box(314, 454, 420, 550),
    "Lift": box(460, 450, 486, 478),
    "Cargo Hold A": box(294, 631, 443, 963),
    "Supplies Storage": box(188, 664, 263, 817),
    "Refrigerated Stores": box(188, 826, 263, 991),
    "Workshop & Maintenance": box(270, 1048, 376, 1142),
}
TWIN = {"Galley & Mess": "Medbay", "Cargo Hold A": "Cargo Hold B", "Supplies Storage": "Munitions Resupply",
        "Refrigerated Stores": "Spare Parts & Equipment", "Workshop & Maintenance": "Logistics Office"}
for k, g in L.items():
    R[k if k in TWIN else k + " (port)"] = g
    R[TWIN.get(k, k + " (starboard)")] = M(g)

LH = [
    hall((284, 318), (466, 318), w=12),                     # over the crew quarters
    hall((284, 318), (284, 1008), w=16),                    # the port run, bow to stern
    hall((292, 364), (337, 364), w=16),                     # -> crew quarters
    hall((420, 464), (460, 464), w=16), hall((486, 464), (502, 464), w=16),   # galley -> lift -> spine
    hall((284, 608), (514, 608), w=16),                     # across the top of the holds
    hall((455, 616), (455, 975), w=14),                     # beside the loader bay
    hall((284, 1008), (380, 1008), w=16),                   # -> transfer hub
    hall((376, 1130), (467, 1130), w=16),                   # workshop -> engineering
]
SMALL = [box(365, 550, 381, 600)]
HALLS = [box(504, 207, 524, 238), box(502, 410, 526, 533), box(504, 590, 524, 645), box(504, 963, 524, 980), box(504, 1236, 524, 1256)] \
    + SMALL + [M(b) for b in SMALL] + LH + [M(h) for h in LH]

DC = [(514, 209, "h"), (514, 236, "h"), (514, 318, "h"), (514, 412, "h"), (514, 531, "h"), (514, 592, "h"), (514, 643, "h"),
      (514, 965, "h"), (514, 978, "h"), (514, 1043, "h"), (514, 1148, "h"), (514, 1238, "h"), (514, 1254, "h")]
DL = [(403, 322, "h"), (335, 364, "v"), (361, 450, "h"), (422, 464, "v"), (460, 464, "v"), (486, 464, "v"), (373, 552, "h"),
      (373, 598, "h"), (418, 626, "h"), (269, 791, "v"), (293, 791, "v"), (269, 933, "v"), (465, 919, "v"), (465, 966, "v"),
      (382, 1008, "v"), (365, 1044, "h"), (378, 1130, "v"), (465, 1130, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("unity_resupply", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(514, 800))
if __name__ == "__main__":
    run(S)
