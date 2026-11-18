#!/usr/bin/env python3
"""Liberty Hub (st3d_veranthos_customs) MAIN HUB deck, laid out like the fleet capital ships (owner, Nov 17 2026:
"make the space station's map look more designed like the capital ships ... rooms, different ways, the same graybox,
the pathways ... the same structure, the same build"). Same planlib as every fleet ship: rooms R, hallways HALLS,
doors DOORS, mirrored about x 512; 10 px = 1 m. The station seen from above (source.jpg = its own outline): the
command dome in the top spire, the MAIN HUB in the middle (like the capital's CIC), the DOCKING BAY below it (like the
hangar) with a hall loop round it, the services down both sides, a spoke hall out to a DOCKING PORT in every arm,
engineering and the reactor at the foot. PROPOSED (owner marks X / O)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
import decklib
from shapely.geometry import Polygon, box

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "source.jpg")
AX = 512.0
M = mirror(AX)
HULL = decklib.hull(SRC, AX).buffer(-6)

def fit(g):
    """a room kept inside the hull (its biggest piece)"""
    g = g.intersection(HULL)
    return max(getattr(g, "geoms", [g]), key=lambda q: q.area)

R = {}
R["Command Center"] = fit(circle(512, 432, 30))
R["Main Hub"] = circle(512, 680, 66)
R["Docking Bay"] = Polygon([(432, 820), (592, 820), (612, 840), (612, 960), (592, 980), (432, 980), (412, 960), (412, 840)])
R["Engineering"] = Polygon([(452, 1012), (572, 1012), (572, 1066), (552, 1086), (472, 1086), (452, 1066)])
L = {   # the port side; mirrored to starboard
    "Station Security": box(410, 520, 490, 588),
    "Lift": box(462, 760, 490, 788),
    "Mission Center": box(298, 610, 384, 690),
    "Supplies": box(298, 700, 384, 776),
    "Pilots' Lounge": box(282, 820, 384, 900),
    "Armory": box(262, 910, 384, 990),
    "Docking Port": fit(Polygon([(150, 545), (205, 560), (215, 615), (165, 630), (128, 585)])),          # the side arm
    "Upper Port": fit(Polygon([(282, 395), (330, 380), (352, 440), (318, 470), (292, 450)])),            # the top arm
    "Cargo Hold": fit(box(180, 1012, 300, 1086)),
    "Cargo Port": fit(Polygon([(250, 1105), (320, 1095), (350, 1140), (300, 1165), (240, 1150)])),      # the foot arm
}
RIGHT = {"Station Security": "Comms", "Mission Center": "Shipyard", "Supplies": "Medical Bay", "Pilots' Lounge": "Mech Dealer",
         "Armory": "Detention", "Docking Port": "Docking Port (east)", "Upper Port": "Upper Port (east)", "Cargo Port": "Cargo Port (east)", "Cargo Hold": "Cargo Hold (east)",
         "Lift": "Lift (starboard)"}
for k, g in L.items():
    R[k if k != "Lift" else "Lift (port)"] = g
    R[RIGHT[k]] = M(g)

SP = [hall((512, 462), (512, 614), w=24),     # the spine: command -> security band -> hub
      hall((512, 746), (512, 820), w=28), hall((512, 980), (512, 1012), w=28)]     # hub -> bay -> engineering
LH = [
    hall((400, 600), (400, 1000), w=20),               # the run down the services, beside the hub and the bay
    hall((400, 600), (492, 600), w=18),                # across under the security band to the spine
    hall((400, 680), (446, 680), w=18),                # into the hub's side
    hall((400, 1000), (452, 1000), (452, 1012), w=20), # under the bay to engineering
    hall((400, 800), (412, 800), w=18),                # to the bay's side door
    hall((490, 774), (500, 774), w=14),                # the lift to the spine
    hall((400, 610), (300, 560), (215, 590), w=18),    # the west spoke, out to the side docking port
    hall((400, 600), (376, 520), (345, 450), w=18),    # the north-west spoke, up the top arm
    hall((400, 1000), (360, 1060), (320, 1120), w=18), # the south-west spoke, down the foot arm
    hall((300, 1060), (355, 1060), w=16),              # into the cargo hold
]
HALLS = SP + LH + [M(h) for h in LH]

DC = [(512, 462, "h"), (512, 614, "h"), (512, 746, "h"), (512, 820, "h"), (512, 980, "h"), (512, 1012, "h")]
DL = [(495, 554, "v"), (384, 650, "v"), (384, 738, "v"), (384, 860, "v"), (384, 950, "v"), (446, 680, "v"), (412, 800, "v"),
      (490, 774, "v"), (212, 592, "v"), (345, 452, "h"), (322, 1110, "h"), (300, 1060, "v")]
DOORS = DC + DL + [(2 * AX - x, y, o) for x, y, o in DL]

S = Ship("station_veranthos_customs", HERE, SRC, AX, R, HALLS, DOORS, start=(512, 900), proposed=[d[:2] for d in DOORS])
if __name__ == "__main__":
    bad = run(S)
    out = [k for k, g in R.items() if not g.within(HULL.buffer(8))]
    print("outside the hull:", out)
