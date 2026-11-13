#!/usr/bin/env python3
"""Imperium Troop Transport: PROPOSED upper (command) deck and lower (hold) deck, composed inside the hull, centre
mass, mirrored about x 494. Lift A (main <-> upper) and Lift B (main <-> lower) stand where they are on the main deck.

v2 (owner's DECK PLAN RULES, 13 Nov 2026: "not only squares, unique shapes like the traced ships, by function and
purpose"): every room's shape comes from its job, the way the traced SWTOR ships do it (Kasparov, Defender, Fury,
Malgus command deck, Carrick station):
  command rooms round / octagonal with a railing ring and a raised stage; briefing / chart rooms long with a round
  holo-table and chamfered corners; comms / gunnery wedges and half-rounds fanning to the hull; quarters a row along
  the hull with an entry nook; lounges rounded, galleys L-shaped with a counter; bays big with chamfered corners and
  pods in a row; the brig a cell corridor with one guarded entry; machine rooms round round a central machine with a
  ring walkway; turret / pod-launch rooms angled out to the hull; escape pods a curved corridor along the hull.
  Corridors: a central spine and an octagonal loop (45-degree corners), round junctions where they meet.
Walls 0.4 m, doors 1.6 m, corridors 2 m, 10 px = 1 m. Function lines (railings, tables, bunks, cells, pods) are drawn
thin and blue: they are furniture, not walls."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import hall, mirror, circle
import decklib
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "source.jpg")
AX = 494.0
M = mirror(AX)
LIFT_A, LIFT_B = (459, 490), (529, 490)        # Lift A goes UP (main <-> upper), Lift B goes DOWN (main <-> lower)
IN = decklib.hull(SRC, AX).buffer(-26, join_style=2)

def octa(x0, y0, x1, y1, c):
    return Polygon([(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)])
def big(g):
    return max(getattr(g, "geoms", [g]), key=lambda q: q.area)
def clip(g):                                   # an outer room: its outside wall is the hull's curve
    return big(g.intersection(IN)).simplify(1.0)
def rounded(g, r):
    return g.buffer(-r, join_style=2).buffer(r, 32)
def arc(cx, cy, r, a0, a1, n=24):
    import math
    return LineString([(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)])
def sector(cx, cy, r0, r1, a0, a1):
    o = list(arc(cx, cy, r1, a0, a1).coords); i = list(arc(cx, cy, r0, a1, a0).coords)
    return Polygon(o + i)
def mir(DL): return DL + [(2 * AX - x, y, o) for x, y, o in DL]
def mf(fs): return fs + [M(f) for f in fs]

# ===================================================================== UPPER DECK - COMMAND
LOOP = hall((494, 380), (430, 380), (400, 410), (400, 850), (430, 880), (494, 880), w=20)
HALLS = [hall((494, 352), (494, 892), w=20), LOOP, M(LOOP), hall((400, 620), (588, 620), w=20),
         circle(494, 380, 20), circle(494, 620, 20), circle(494, 880, 20), box(478, 462, 510, 520)]
HU = unary_union(HALLS)
core = lambda g: big(g.difference(HU))
R = {}
R["Observation Lounge"] = unary_union([circle(494, 302, 50), box(444, 302, 544, 352)])
R["Gunnery Control"] = circle(494, 902, 46).intersection(box(430, 902, 560, 960))
L = {
    "Star Chart Room": clip(octa(350, 300, 446, 368, 12)),
    "Officers' Quarters": core(clip(box(240, 412, 390, 522)).difference(box(372, 412, 392, 452))),   # (the entry nook)
    "Officer Cabins": core(clip(box(200, 524, 390, 640))),
    "Officers' Lounge": core(clip(rounded(box(200, 642, 390, 758), 18))),
    "Galley": core(clip(box(200, 760, 390, 882)).difference(box(326, 760, 392, 806))),             # an L round the counter
    "Turret Access": clip(Polygon([(230, 892), (330, 892), (370, 935), (370, 992), (230, 992)])),
    "Shield Control": Polygon([(334, 892), (444, 892), (444, 972), (376, 972), (376, 932)]),
    "Security Office": core(unary_union([box(410, 392, 484, 462), box(410, 462, 440, 520)])),
    "War Room": core(octa(412, 530, 484, 610, 10)),
    "Captain's Quarters": core(octa(412, 630, 484, 760, 14)),
    "Comms Array": core(box(412, 772, 484, 870)),
}
TWIN = {"Officers' Quarters": ("Officers' Quarters A", "Officers' Quarters B"), "Officer Cabins": ("Officer Cabins A", "Officer Cabins B"),
        "Galley": ("Galley", "Wardroom"), "Shield Control": ("Shield Control", "Fire Control"),
        "Security Office": ("Security Office", "Weapons Locker"), "War Room": ("War Room", "Navigation Room"),
        "Captain's Quarters": ("Captain's Quarters", "Captain's Office"), "Comms Array": ("Comms Array", "Sensor Station")}
for k, g in L.items():
    a, b = TWIN.get(k, (k + " (port)", k + " (starboard)"))
    R[a] = g; R[b] = M(g)
R["Lift A"] = box(440, 470, 478, 510)
R["Weapons Locker"] = core(unary_union([M(box(410, 392, 484, 462)), box(510, 462, 578, 520)]))   # (Lift B doesn't stop here)
DC = [(494, 352, "h"), (494, 901, "h"), (588, 695, "v")]
DL = [(390, 490, "v"), (390, 582, "v"), (390, 700, "v"), (390, 840, "v"), (436, 369, "h"), (434, 891, "h"), (373, 955, "v"),
      (280, 887, "h"), (484, 427, "v"), (410, 440, "v"), (478, 490, "v"), (484, 570, "v"), (410, 570, "v"), (484, 695, "v"),
      (410, 800, "v"), (484, 816, "v")]
FEAT = [circle(494, 300, 32).exterior, circle(494, 300, 14).exterior] + mf([
    circle(398, 334, 12).exterior,                                          # star chart holo-table
    circle(448, 570, 12).exterior,                                          # war room holo-table
    box(300, 440, 360, 470).exterior, box(300, 480, 360, 510).exterior,     # officers' bunks
    LineString([(250, 563), (360, 563)]), LineString([(240, 601), (360, 601)]),   # three cabins
    arc(300, 700, 34, 120, 240),                                            # lounge bar
    LineString([(250, 800), (320, 800)]),                                   # galley counter
    arc(494, 902, 34, 20, 160),                                             # gunnery consoles
    box(425, 650, 470, 690).exterior,                                       # the captain's bed
    arc(440, 860, 50, 230, 310),                                            # comms consoles
])
FEAT.append(circle(540, 695, 18).exterior)                                  # captain's office console ring
R = decklib.settle(R, HALLS, keep=("Lift A",))
bad = decklib.run("imperium_trooptransport", HERE, SRC, AX, "upper", 1, R, HALLS, DC + mir(DL), [LIFT_A],
                  title="UPPER DECK - COMMAND", features=FEAT)

# ===================================================================== LOWER DECK - HOLD
LOOP = hall((494, 570), (410, 570), (380, 600), (380, 1080), (410, 1110), (494, 1110), w=20)
HALLS = [hall((494, 460), (494, 582), w=20), hall((494, 828), (494, 1122), w=20), LOOP, M(LOOP),
         hall((380, 840), (608, 840), w=20), circle(494, 570, 20), circle(494, 840, 20), circle(494, 1110, 20),
         box(500, 470, 510, 510), hall((468, 520), (484, 520), w=16), hall((504, 540), (584, 540), w=16),
         hall((356, 1105), (402, 1105), w=16), M(hall((356, 1105), (402, 1105), w=16))]
HU = unary_union(HALLS)
core = lambda g: big(g.difference(HU))
R = {}
R["Brig"] = box(476, 592, 512, 820)                                                    # the cell corridor
for i in range(4): R["Holding Cell %d" % (i + 1)] = box(512, 592 + i * 57, 596, 592 + (i + 1) * 57)
R["Detention Office"] = box(392, 592, 476, 700)
R["Holding Cell 5"] = box(392, 700, 476, 760)
R["Holding Cell 6"] = box(392, 760, 476, 820)
R["Coolant Pumps"] = circle(494, 1172, 40)
R["Escape Pods"] = sector(494, 1150, 66, 84, 30, 150)
R["Water Recycling"] = circle(430, 510, 42)
R["Life Support"] = circle(585, 498, 30)
R["Lift B"] = box(510, 470, 548, 510)
L = {
    "Ammo Store": core(clip(box(250, 452, 370, 640))),
    "Guard Post": core(clip(octa(250, 642, 370, 740, 12))),
    "Spare Parts": core(clip(box(220, 742, 370, 860))),
    "Drop Pod Bay": core(clip(octa(200, 862, 370, 1000, 14))),
    "Pod Launch Control": core(clip(Polygon([(370, 1002), (370, 1078), (290, 1078), (240, 1002)]))),
    "Cargo Hold": core(octa(392, 852, 484, 1098, 16)),
    "Machine Shop": octa(392, 1122, 452, 1180, 12),
    "Battery Room": core(clip(circle(320, 1132, 40))),
}
TWIN = {"Spare Parts": ("Spare Parts", "Medical Store"), "Drop Pod Bay": ("Drop Pod Bay A", "Drop Pod Bay B"),
        "Cargo Hold": ("Cargo Hold A", "Cargo Hold B"), "Machine Shop": ("Machine Shop", "Fuel Store"),
        "Battery Room": ("Battery Room", "Shield Generator")}
for k, g in L.items():
    a, b = TWIN.get(k, (k + " (port)", k + " (starboard)"))
    R[a] = g; R[b] = M(g)
DC = [(494, 591, "h"), (494, 1131, "h"), (494, 1214, "h"), (510, 490, "v"), (585, 530, "h"), (476, 646, "v"), (476, 730, "v"),
      (476, 790, "v")] + [(512, 620 + i * 57, "v") for i in range(4)]
DL = [(470, 520, "v"), (370, 625, "v"), (370, 690, "v"), (370, 800, "v"), (370, 930, "v"), (370, 1040, "v"), (484, 970, "v"),
      (391, 970, "v"), (422, 1121, "h"), (358, 1105, "v")]
FEAT = [circle(430, 510, 28).exterior, circle(430, 510, 12).exterior, circle(585, 498, 19).exterior, circle(585, 498, 8).exterior,
        circle(494, 1172, 26).exterior, circle(494, 1172, 12).exterior] + mf([
    box(260, 760, 360, 768).exterior, box(260, 800, 360, 808).exterior, box(260, 840, 360, 848).exterior,   # shelves
    circle(422, 1151, 12).exterior,                                                                      # the machine
    box(410, 880, 440, 910).exterior, box(410, 930, 440, 960).exterior, box(410, 1040, 440, 1070).exterior,   # crates
    circle(320, 1132, 18).exterior,                                                                      # the battery stack
    arc(300, 700, 26, 0, 360),                                                                           # guard desk
]) + [circle(225 + 0, 900 + i * 30, 9).exterior for i in range(4)] + [M(circle(225, 900 + i * 30, 9)).exterior for i in range(4)] \
   + [LineString([(512, 592 + i * 57 + 8), (512, 592 + i * 57 + 49)]) for i in range(4)]
R = decklib.settle(R, HALLS, keep=("Lift B",))
bad += decklib.run("imperium_trooptransport", HERE, SRC, AX, "lower", -1, R, HALLS, DC + mir(DL), [LIFT_B],
                   title="LOWER DECK - HOLD", features=FEAT)
decklib.both(os.path.join(HERE, "deck_upper_on_map.jpg"), os.path.join(HERE, "deck_lower_on_map.jpg"), os.path.join(HERE, "decks_on_map.jpg"))
decklib.both(os.path.join(HERE, "deck_upper.png"), os.path.join(HERE, "deck_lower.png"), os.path.join(HERE, "decks_plan.jpg"))
sys.exit(1 if bad else 0)
