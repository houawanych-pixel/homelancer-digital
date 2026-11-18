#!/usr/bin/env python3
"""Liberty Hub (st3d_veranthos_customs) MAIN HUB floor - station formula step 2 (owner, Nov 17 2026: "nest the rooms
from the library, good walkways and hallways, then the formula ... the same as the ships"). Built exactly like the
capital ships' composed decks (fleet_compose.py): traced LIBRARY rooms (decklib.lib / decklib.fit), placed in the
floor's own clean silhouette (station_silhouette.py -> station_source.py, 140 m across), halls as centre line + width
with junctions, rooms settled / finalized so they share one wall, mirrored about the middle line, decklib.run's checks.
The MAIN HUB in the middle, the services round it on a hall loop, a spoke hall out into every arm to a docking port,
the DOCKING BAY at the foot.  PROPOSED (owner marks X / O).
(Positions are written on a 95 m layout grid, x 512 / y 790 = the middle, and scaled by K onto the 140 m sheet.)"""
import os, sys, math, json
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import decklib
from decklib import lib, fit, Deck
from planlib import hall
from fleet_compose import junction, ring
from shapely.geometry import box
from shapely import affinity

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "source.jpg")
AX = 800.0
K = 140.0 / 95.0
def X(x): return round(800 + (x - 512) * K, 1)
def Y(y): return round(800 + (y - 768) * K, 1)
def P(x, y): return (X(x), Y(y))
def at(g, cx, cy):
    """a library room centred (its box) on cx, cy (layout grid)"""
    if isinstance(g, tuple): return (at(g[0], cx, cy), g[1])
    x0, y0, x1, y1 = g.bounds
    return affinity.translate(g, X(cx) - (x0 + x1) / 2, Y(cy) - (y0 + y1) / 2)
def F(tags, cx, cy, w, h): return at(fit(tags, X(cx), Y(cy), w * K, h * K), cx, cy)
def H(*pts, w=18): return hall(*[P(*p) for p in pts], w=w)
def FA(tags, x, y, w, h):   # (sheet px, the room's size in metres)
    g = fit(tags, x, y, w, h)
    x0, y0, x1, y1 = g[0].bounds
    return (affinity.translate(g[0], x - (x0 + x1) / 2, y - (y0 + y1) / 2), g[1])

D = Deck(AX)
D.room("Main Hub", at(lib("tianjin_14", 0, 0, w=18.0 * K, h=18.0 * K), 512, 790), "tianjin_14 round CIC (the station's atrium)")
D.room("Station Control", F(["command", "bridge"], 512, 420, 6.0, 6.6), "the command spire")
D.room("Customs", F(["office", "vestibule"], 436, 532, 11.0, 8.0), twin="Security Office")
D.room("Mission Center", F(["office", "quarters"], 308, 668, 13.0, 6.2), twin="Shipyard")
D.room("Supplies", F(["cargo", "closet"], 300, 742, 14.0, 7.0), twin="Mech Dealer")
D.room("Medical Bay", F(["medbay"], 300, 828, 14.0, 7.0), twin="Armory")
D.room("Pilots' Lounge", F(["quarters", "office"], 305, 912, 13.0, 6.5), twin="Galley")
D.room("Comms", F(["office", "quarters"], 455, 648, 7.0, 6.0), twin="Records")
lc = P(455, 934)
D.room("Lift", box(lc[0] - 14, lc[1] - 14, lc[0] + 14, lc[1] + 14), "lift car (the main lift)")
D.room("Docking Bay", F(["cargo"], 512, 1058, 30.0, 10.0), "the hangar you dock in")
D.room("North Dock", FA(["vestibule", "office"], 467, 240, 4.4, 4.4), twin="North Dock (east)")     # the arm tips (the hull's own)
D.room("West Dock", FA(["vestibule", "office"], 221, 463, 4.4, 4.4), twin="East Dock")
D.room("Cargo Dock", FA(["vestibule", "office"], 264, 1212, 4.4, 4.4), twin="Cargo Dock (east)")
D.room("South Dock", FA(["vestibule", "office"], 361, 1410, 3.6, 3.6), twin="South Dock (east)")
# ---- halls (widths never scale)
HUB_R = (D.R["Main Hub"].bounds[2] - D.R["Main Hub"].bounds[0]) / 2
HC = Y(790)
hub_top, hub_bot = HC - HUB_R, HC + HUB_R
D.H += [hall((800, Y(455)), (800, hub_top), w=24), hall((800, hub_bot), (800, Y(1008)), w=24), junction(*P(512, 600)), junction(*P(512, 990))]
D.hall(H((400, 600), (400, 990)))                       # the run down the services
D.hall(H((400, 600), (512, 600)))                       # across the top to the spine
D.hall(H((400, 990), (512, 990)))                       # across the foot to the spine
D.hall(hall((X(400) + 9, HC), (800 - HUB_R, HC), w=16))   # into the hub's side
D.hall(hall((626, 552), (560, 440), (490, 280), w=16))      # the north spoke, up the top arm
D.hall(hall((626, 560), (420, 560), (262, 485), w=16))      # the west spoke, out along the side arm
D.hall(hall((635, 1126), (470, 1190), (300, 1200), w=16))   # the south-west spoke
D.hall(hall((635, 1126), (500, 1300), (400, 1410), w=16))   # the south spoke, down the foot arm
WH = {"Main Hub", "Lift"}
D.R = decklib.settle(D.R, D.H, whole=WH, twins=D.TW, mirror_fn=D.M, mode="close")
D.door(800, hub_top, "h", both=False); D.door(800, hub_bot, "h", both=False); D.door(800 - HUB_R, HC, "v")
D.link("Station Control", (800, Y(470)), both=False); D.link("Customs", (788, Y(532))); D.link("Mission Center", (X(400) - 9, Y(668)))
D.link("Supplies", (X(400) - 9, Y(742))); D.link("Medical Bay", (X(400) - 9, Y(828))); D.link("Pilots' Lounge", (X(400) - 9, Y(912)))
D.link("Comms", (788, Y(648))); D.link("Lift", (788, lc[1]), both=False); D.link("Docking Bay", (800, Y(1000)), both=False)
D.link("North Dock", (490, 280)); D.link("West Dock", (262, 485)); D.link("Cargo Dock", (300, 1200)); D.link("South Dock", (400, 1410))
D.D = list(dict.fromkeys(D.D))
D.R = decklib.finalize(D.R, D.H, list(D.R), D.TW, D.M, keep=WH)
D.feat("Main Hub", [ring(800, HC, HUB_R * 0.55), ring(800, HC, HUB_R * 0.25)])
SHORT = {"Station Control": "Control", "Security Office": "Security", "Mission Center": "Missions", "Pilots' Lounge": "Lounge",
         "North Dock (east)": "North Dock", "Cargo Dock (east)": "Cargo Dock", "South Dock (east)": "South Dock"}
if __name__ == "__main__":
    pj = os.path.join(HERE, "plan.json")
    json.dump({"floor": {"type": "Polygon", "coordinates": [[[0, 0], [1, 0], [1, 1], [0, 0]]]}}, open(pj, "w"))
    bad = decklib.run("station_veranthos_customs", HERE, SRC, AX, "main", 0, D.R, D.H, D.D, [lc], start=P(512, 1058),
                      fin=6, title="MAIN HUB", features=D.F, short=SHORT, whole=WH, source=D.FROM, round_rooms={"Main Hub"})
    print("failures:", bad)
