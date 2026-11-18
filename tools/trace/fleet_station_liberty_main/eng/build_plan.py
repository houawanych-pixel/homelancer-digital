#!/usr/bin/env python3
"""Liberty Hub MAIN HUB deck in the SHIP construction (owner, Nov 18 2026: a station is the fleet-ship structure and
gameplay with a station silhouette). Measured on the owner's district sheet (MAIN HUB panel, x4 zoom = source.jpg,
rooms traced by concept_districts/trace_rooms.py), at ship scale (planlib: 10 px = 1 m), mirrored about x 729.
The rooms on the sheet touch wall to wall; to give them walkways like the ships', they are set back a little:
  a RING hall round the Central Concourse (the mall), a SPINE up and down the middle (Observation Deck - Command Plaza -
  Concourse - Transit Hub - Security Checkpoint), a WEST / EAST hall past Customs and Market, a crew corridor behind
  the Markets, and a lane up each arm to a dock pad (every arm used)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, box
from shapely import affinity

HERE = os.path.dirname(os.path.abspath(__file__))
AX = 729.0
M = mirror(AX)
MW, PW = 28, 18        # mech hall / pilot hall widths (px)

def octo(x0, y0, x1, y1, c):
    return Polygon([(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)])

def slab(cx, cy, length, width, deg):
    return affinity.rotate(box(cx - length / 2, cy - width / 2, cx + length / 2, cy + width / 2), deg, origin=(cx, cy))

import json as _j
from shapely.geometry import shape as _sh
HULL = _sh(_j.load(open(os.path.join(HERE, "..", "..", "fleet_station_liberty_hub", "concept_districts", "main_hub_trace.json")))["hull"]).buffer(-8)
inhull = lambda g: g.intersection(HULL).simplify(1.0)      # rooms at the hull follow its wall
R = {}
# the middle (on the axis)
R["Observation Deck"] = octo(689, 80, 769, 160, 16)
R["Command Plaza"] = octo(600, 330, 858, 572, 40)
R["Central Concourse"] = box(530, 600, 928, 950)
R["Transit Hub"] = box(585, 978, 873, 1200)
R["Security Checkpoint"] = octo(585, 1228, 873, 1410, 40)
# one side (mirrored)
L = {
    "Docking A": inhull(slab(440, 255, 180, 90, 45)),
    "Customs A": box(312, 470, 474, 580),
    "Market & Services A": box(290, 670, 474, 946),
    "Lift (port)": box(502, 380, 556, 434),
    "Freight Lift (port)": box(420, 960, 474, 1014),
    "Dock Pad NW": inhull(box(190, 440, 300, 560)),          # at the root of the NW arm
    "Dock Pad W": inhull(octo(160, 960, 272, 1060, 14)),     # at the root of the W arm
    "Dock Pad SW": inhull(octo(300, 1300, 420, 1380, 14)),   # at the root of the SW arm
}
MIRROR_NAME = {"Docking A": "Docking B", "Customs A": "Customs B", "Market & Services A": "Market & Services B",
               "Lift (port)": "Lift (starboard)", "Freight Lift (port)": "Freight Lift (starboard)",
               "Dock Pad NW": "Dock Pad NE", "Dock Pad W": "Dock Pad E", "Dock Pad SW": "Dock Pad SE"}
for k, g in L.items():
    R[k] = g
    R[MIRROR_NAME[k]] = M(g)

from shapely.geometry import LineString
def door_at(room, a, b, o):          # where the lane's centre line crosses the room's wall
    q = room.exterior.intersection(LineString([a, b]))
    q = q if q.geom_type == "Point" else list(getattr(q, "geoms", [q]))[0]
    return (round(q.x, 1), round(q.y, 1), o)
D_DOCK = door_at(L["Docking A"], (488, 360), (488, 250), "h")
D_NW = (281.0, 560.0, "h")
D_W = (272.0, 1010.0, "v")
D_SW = (420.0, 1340.0, "v")
HC = [hall((729, 160), (729, 330), w=24),                               # spine: observation deck down to the plaza
      hall((516, 586), (942, 586), (942, 964), (516, 964), (516, 586), w=MW),   # the ring round the concourse
      hall((729, 1200), (729, 1228), w=MW)]                             # transit hub to the checkpoint
HL = [hall(D_DOCK[:2], (488, 1104), w=MW),                              # the west hall (docking A down to transit)
      hall((502, 450), (600, 450), w=MW),                               # west hall to the plaza
      hall((488, 1090), (585, 1090), w=MW),                             # west hall to the transit hub
      hall((474, 625), (272, 625), w=MW),                               # across under Customs
      hall((281, 560), (281, 1069), (488, 1069), w=PW),                 # the crew corridor behind the Market (NW / W pads)
      hall((488, 1104), (488, 1340), (420, 1340), w=MW)]                # on down to the SW pad
HALLS = HC + HL + [M(h) for h in HL]

DC = [(729, 160, "h"), (729, 330, "h"), (729, 572, "h"), (729, 600, "h"), (729, 950, "h"), (729, 978, "h"),
      (729, 1200, "h"), (729, 1228, "h")]
DL = [(600, 450, "v"), (530, 775, "v"), (585, 1090, "v"), (474, 525, "v"), (474, 808, "v"), (290, 808, "v"),
      (502, 407, "v"), (474, 987, "v"), D_DOCK, D_NW, D_W, D_SW]
# the arm rooms: one door each where its lane meets it
DOORS = DC + DL + [(round(2 * AX - x, 1), y, o) for x, y, o in DL]

S = Ship("station_liberty_main", HERE, os.path.join(HERE, "..", "source.jpg"), AX, R, HALLS, DOORS, start=(729, 775), center_y=775)
if __name__ == "__main__":
    bad = run(S)
    import json
    P = os.path.join(HERE, "overrides.json")
    MECH = ("Docking", "Dock Pad", "Command Plaza", "Central Concourse", "Transit Hub", "Security Checkpoint")
    json.dump({"entry": "Docking A", "kinds": {k: ("lift" if "Lift" in k else "mech" if k.startswith(MECH) else "pilot") for k in R}},
              open(P, "w"), indent=1)
    pt = lambda k: [int(R[k].representative_point().x), int(R[k].representative_point().y)]
    G = {"entry": {"room": "Docking A", "at": pt("Docking A")}, "locks": [], "guards": [], "wreck": [], "patrols": [],
         "targets": {}, "lifts": [{"room": k, "at": pt(k)} for k in R if "Lift" in k],
         "room_guards": {k: (2 if k.startswith(MECH) else 1) for k in R if "Lift" not in k}, "note": "Liberty Hub MAIN HUB deck"}
    if not os.path.exists(os.path.join(HERE, "gameplay.json")): json.dump(G, open(os.path.join(HERE, "gameplay.json"), "w"), indent=1)
    sys.exit(1 if bad else 0)
