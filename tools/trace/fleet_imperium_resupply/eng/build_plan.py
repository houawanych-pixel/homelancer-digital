#!/usr/bin/env python3
"""Imperium Resupply Ship main deck, measured on the owner's HoloDeck sheet (1024 x 1536 px), mirrored about x 512.
10 px = 1 m. Six cargo holds (A1-A3 port, B1-B3 starboard) round a central spine: transfer hub, vehicle / loader bay,
general storage. PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 512.0
M = mirror(AX)
R = {}
R["Bridge"] = Polygon([(486, 135), (538, 135), (555, 155), (555, 215), (469, 215), (469, 155)])
R["CIC"] = Polygon([(484, 290), (540, 290), (560, 310), (560, 350), (540, 370), (484, 370), (464, 350), (464, 310)])
R["Lift"] = box(497, 444, 527, 474)
R["Cargo Transfer Hub"] = circle(512, 608, 49)
R["Vehicle / Loader Bay"] = box(432, 705, 592, 968)
R["General Storage"] = box(449, 1003, 575, 1079)
R["Engineering Deck"] = Polygon([(365, 1110), (659, 1110), (679, 1130), (679, 1190), (345, 1190), (345, 1130)])
R["Reactor Core"] = circle(512, 1240, 42)
R["Engine Room"] = Polygon([(450, 1282), (574, 1282), (592, 1300), (592, 1361), (432, 1361), (432, 1300)])
L = {
    "Sensors Suite": Polygon([(383, 262), (430, 225), (479, 225), (479, 291), (383, 291)]),
    "Crew Quarters": box(280, 296, 441, 405),
    "Galley & Mess": box(279, 413, 441, 507),
    "Cargo Hold A1": box(200, 540, 388, 680), "Cargo Hold A2": box(200, 690, 388, 825), "Cargo Hold A3": box(200, 838, 388, 972),
    "Refrigerated Stores": box(260, 1002, 418, 1092),
    "Coolant / Systems A": Polygon([(197, 1110), (240, 1089), (290, 1089), (290, 1199), (220, 1199)]),
}
TWIN = {"Galley & Mess": "Medbay", "Cargo Hold A1": "Cargo Hold B1", "Cargo Hold A2": "Cargo Hold B2", "Cargo Hold A3": "Cargo Hold B3",
        "Refrigerated Stores": "Munitions Resupply", "Coolant / Systems A": "Coolant / Systems B"}
for k, g in L.items():
    R[k if k in TWIN else k + " (port)"] = g
    R[TWIN.get(k, k + " (starboard)")] = M(g)

LH = [
    hall((479, 248), (497, 248), w=16),                     # sensors -> the bridge corridor
    hall((441, 344), (464, 344), w=16),                     # crew quarters -> CIC
    hall((290, 1162), (321, 1162), w=16),                   # coolant -> its corridor
    hall((441, 452), (497, 452), w=16),                     # galley -> lift
    hall((300, 520), (497, 520), w=16),                     # under the galley
    hall((410, 520), (410, 995), w=30),                     # between the cargo holds and the vehicle bay
    hall((424, 607), (463, 607), w=16),                     # into the transfer hub
    hall((410, 985), (512, 985), w=16),                     # over general storage
    hall((418, 1039), (449, 1039), w=16),                   # refrigerated -> general storage
    hall((330, 1092), (330, 1175), w=18),                   # refrigerated -> coolant / engineering
    hall((408, 1190), (408, 1310), w=16), hall((408, 1226), (472, 1226), w=16),   # engineering's aft side way
]
HALLS = [box(497, 215, 527, 290), box(497, 370, 527, 444), box(497, 474, 527, 559), box(497, 657, 527, 705), box(497, 1079, 527, 1110),
         box(298, 972, 314, 1002)] + LH + [M(h) for h in LH] + [M(box(298, 972, 314, 1002))]

DC = [(512, 217, "h"), (512, 288, "h"), (512, 372, "h"), (512, 444, "h"), (512, 474, "h"), (512, 557, "h"), (512, 659, "h"),
      (512, 1081, "h"), (512, 1108, "h"), (512, 1194, "h"), (512, 1283, "h")]
DL = [(481, 248, "v"), (495, 248, "v"), (390, 293, "h"), (443, 344, "v"), (462, 344, "v"), (363, 409, "h"), (443, 452, "v"), (497, 455, "v"),
      (411, 509, "h"), (306, 530, "h"), (390, 606, "v"), (461, 607, "v"), (306, 685, "h"), (390, 755, "v"), (430, 800, "v"),
      (306, 831, "h"), (390, 902, "v"), (306, 974, "h"), (306, 1000, "h"), (490, 705, "h"), (478, 1001, "h"), (420, 1039, "v"),
      (447, 1039, "v"), (335, 1094, "h"), (292, 1162, "v"), (343, 1162, "v"), (408, 1188, "h"), (472, 1226, "v"), (424, 1300, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("imperium_resupply", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(512, 840))
if __name__ == "__main__":
    run(S)
