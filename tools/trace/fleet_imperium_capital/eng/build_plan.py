#!/usr/bin/env python3
"""Imperium Capital Ship main deck, measured on the owner's HoloDeck sheet (1012 x 1555 px), mirrored about x 506.
10 px = 1 m (the sheet's hallways are ~16-20 px). Unlabelled hull compartments (wing equipment bays) are hull, not
rooms, unless a green door opens into them. PROPOSED = not on the sheet (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 506.0
M = mirror(AX)
R = {}
R["Bridge Command Deck"] = circle(506, 191, 57)
R["Command Corridor"] = box(492, 248, 520, 336)
R["CIC (Combat Information Center)"] = circle(506, 392, 57)
R["Hangar Bay"] = Polygon([(396, 623), (616, 623), (636, 643), (636, 873), (616, 893), (396, 893), (376, 873), (376, 643)])
R["Vehicle Bay"] = Polygon([(362, 900), (650, 900), (650, 978), (628, 1000), (384, 1000), (362, 978)])
R["Engineering Deck"] = Polygon([(424, 1019), (588, 1019), (588, 1120), (560, 1148), (452, 1148), (424, 1120)])
R["Reactor Core"] = circle(506, 1206, 52)
R["Engine Room"] = Polygon([(440, 1260), (572, 1260), (591, 1279), (591, 1330), (560, 1361), (452, 1361), (422, 1330), (422, 1279)])
L = {
    "Sensors Suite": Polygon([(394, 262), (448, 244), (486, 256), (486, 312), (394, 312)]),
    "Sensor Lockers": box(380, 316, 440, 384),
    "Crew Quarters": Polygon([(318, 440), (350, 393), (424, 393), (424, 501), (318, 501)]),
    "Lift": box(450, 462, 482, 494),
    "Galley & Mess": Polygon([(323, 530), (336, 517), (410, 517), (423, 530), (423, 597), (323, 597)]),
    "Weapon Control": box(213, 613, 310, 700),
    "Armory": box(229, 716, 311, 793),
    "Barracks Lockers": box(112, 702, 190, 780),
    "Barracks": Polygon([(75, 830), (110, 796), (190, 784), (190, 894), (75, 894)]),
    "Cargo Hold": box(232, 917, 320, 1050),
    "Coolant Plant": Polygon([(180, 1062), (290, 1062), (290, 1150), (215, 1150), (180, 1115)]),
    "Aft Lift": box(326, 845, 356, 877),
}
RIGHT = {"Sensors Suite": "Briefing Room", "Galley & Mess": "Medbay"}
for k, g in L.items():
    side = k in ("Sensors Suite", "Galley & Mess")
    R[k if side else k + " (port)" if k not in ("Cargo Hold",) else "Cargo Hold A"] = g
    R[RIGHT[k] if side else k + " (starboard)" if k not in ("Cargo Hold",) else "Cargo Hold B"] = M(g)

HL = [hall((506, 336), (506, 340), w=28)]
LH = [
    hall((439, 400), (439, 553), w=18),             # beside the crew quarters, down to the spine passages
    hall((439, 523), (489, 523), w=16), hall((439, 553), (489, 553), w=16),
    hall((205, 605), (489, 605), w=16),             # across the top of the hangar
    hall((324, 605), (324, 830), w=16),             # down the hangar's side (weapon control, armory)
    hall((205, 605), (205, 1056), w=16),            # the outer run (barracks, cargo, coolant)
    hall((213, 708), (316, 708), w=16),             # between weapon control and the armory
    hall((324, 830), (341, 830), (341, 845), w=16), # to the aft lift
    hall((344, 877), (344, 1009), w=22),            # down past the cargo hold to the vehicle bay
    hall((340, 1009), (489, 1009), w=16),           # under the vehicle bay to engineering
    hall((356, 823), (376, 823), w=16),             # into the hangar's side door
]
HALLS = HL + [box(489, 450, 523, 623)] + LH + [M(h) for h in LH]

DC = [(506, 248, "h"), (506, 336, "h"), (506, 450, "h"), (506, 622, "h"), (464, 896, "h"), (548, 896, "h"), (506, 1150, "h"), (506, 1258, "h")]
DL = [(486, 286, "v"), (415, 388, "h"), (424, 433, "v"), (482, 478, "v"), (348, 509, "h"), (339, 597, "h"), (397, 597, "h"),
      (300, 613, "h"), (310, 690, "v"), (311, 740, "v"), (213, 708, "v"), (159, 788, "h"), (190, 840, "v"),
      (326, 939, "v"), (358, 969, "v"), (406, 1000, "h"), (487, 1019, "h"), (205, 1056, "h"), (341, 845, "h"), (376, 823, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]
PROPOSED = [(506, 1150)]

S = Ship("imperium_capital", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(506, 760), proposed=PROPOSED)
if __name__ == "__main__":
    run(S)
