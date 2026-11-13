#!/usr/bin/env python3
"""Imperium Troop Transport: PROPOSED upper (command) deck and lower (hold) deck, composed inside the hull, centre
mass, mirrored about x 494. Lift A (main <-> upper) and Lift B (main <-> lower) stand where they are on the main deck.

v2 (owner's DECK PLAN RULES, 13 Nov 2026): every room's shape comes from its job, the way the traced SWTOR ships do
it: command rooms round / octagonal with a railing ring; chart rooms long with a holo-table and chamfered corners;
comms / gunnery wedges and half-rounds facing the hull; quarters along the hull with an entry nook; lounges rounded,
galleys L-shaped round a counter; bays big with chamfered corners and pods in a row; the brig a cell corridor with one
guarded entry; machine rooms round round a central machine; turret / pod-launch rooms angled out to the hull; escape
pods a curved corridor. Corridors: a central spine and an octagonal loop (45-degree corners), round junctions.
v3 (owner: "no room may overlap another room, a corridor, a lift or the hull"): the round / octagonal / lift / cell
rooms ("whole") get their own space first and are never cut; the others wrap them on one shared wall; furniture sits
0.3 m inside its room; labels fit inside their room; decklib.check() must print 0 failures.
Walls 0.4 m, doors 1.6 m, corridors 2 m, 10 px = 1 m."""
import math, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import hall, mirror, circle
import decklib
from shapely.geometry import Polygon, LineString, box
from shapely.ops import unary_union

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "source.jpg")
AX = 494.0
M = mirror(AX)
LIFT_A, LIFT_B = (459, 490), (529, 490)        # Lift A goes UP (main <-> upper), Lift B goes DOWN (main <-> lower)
IN = decklib.hull(SRC, AX).buffer(-26, join_style=2)

def octa(x0, y0, x1, y1, c):
    return Polygon([(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)])
def big(g): return max(getattr(g, "geoms", [g]), key=lambda q: q.area)
def clip(g): return big(g.intersection(IN)).simplify(1.0)      # an outer room: its outside wall is the hull's curve
def rounded(g, r): return g.buffer(-r, join_style=2).buffer(r, 32)
def arc(cx, cy, r, a0, a1, n=24):
    return LineString([(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)])
def sector(cx, cy, r0, r1, a0, a1):
    return Polygon(list(arc(cx, cy, r1, a0, a1).coords) + list(arc(cx, cy, r0, a1, a0).coords))
def ring(cx, cy, r): return circle(cx, cy, r).exterior
def mir(DL): return DL + [(2 * AX - x, y, o) for x, y, o in DL]
def pair(R, L, TWIN):
    for k, g in L.items():
        a, b = TWIN.get(k, (k + " (port)", k + " (starboard)"))
        R[a] = g; R[b] = M(g)
def pair_f(F, FL, TWIN):
    for k, fs in FL.items():
        a, b = TWIN.get(k, (k + " (port)", k + " (starboard)"))
        F[a] = fs; F[b] = [M(f) for f in fs]

# ===================================================================== UPPER DECK - COMMAND
LOOP = hall((494, 380), (430, 380), (400, 410), (400, 850), (430, 880), (494, 880), w=20)
HALLS = [hall((494, 352), (494, 892), w=20), LOOP, M(LOOP), hall((400, 620), (588, 620), w=20),
         circle(494, 380, 20), circle(494, 620, 20), circle(494, 880, 20), box(478, 462, 510, 520)]
R = {"Observation Lounge": unary_union([circle(494, 302, 50), box(444, 302, 544, 352)]),
     "Gunnery Control": circle(494, 900, 46).intersection(box(430, 900, 560, 960)),
     "Lift A": box(440, 470, 478, 510)}
TWIN = {"Officers' Quarters": ("Officers' Quarters A", "Officers' Quarters B"), "Officer Cabins": ("Officer Cabins A", "Officer Cabins B"),
        "Galley": ("Galley", "Wardroom"), "Shield Control": ("Shield Control", "Fire Control"),
        "Security Office": ("Security Office", "Weapons Locker"), "War Room": ("War Room", "Navigation Room"),
        "Captain's Quarters": ("Captain's Quarters", "Captain's Office"), "Comms Array": ("Comms Array", "Sensor Station")}
pair(R, {"Star Chart Room": octa(350, 300, 440, 370, 12),
         "War Room": octa(412, 530, 484, 610, 10),
         "Captain's Quarters": octa(412, 630, 484, 760, 14),
         "Turret Access": clip(Polygon([(230, 892), (330, 892), (370, 935), (370, 992), (230, 992)])),
         "Officers' Quarters": clip(box(240, 412, 390, 522)).difference(box(372, 412, 392, 452)),   # (the entry nook)
         "Officer Cabins": clip(box(200, 522, 390, 640)),
         "Officers' Lounge": clip(rounded(box(200, 640, 390, 758), 18)),
         "Galley": clip(box(200, 760, 390, 888)).difference(box(326, 760, 392, 806)),              # an L round the counter
         "Shield Control": Polygon([(322, 892), (452, 892), (452, 972), (366, 972), (366, 926)]),
         "Security Office": unary_union([box(410, 392, 484, 462), box(410, 462, 440, 520)]),
         "Comms Array": box(412, 772, 484, 870)}, TWIN)
R["Weapons Locker"] = unary_union([M(box(410, 392, 484, 462)), box(510, 462, 578, 520)])   # (Lift B doesn't stop here)
WHOLE = {"Observation Lounge", "Gunnery Control", "Lift A", "Star Chart Room (port)", "Star Chart Room (starboard)",
         "War Room", "Navigation Room", "Captain's Quarters", "Captain's Office", "Turret Access (port)", "Turret Access (starboard)"}
R = decklib.settle(R, HALLS, whole=WHOLE)
DC = [(494, 352, "h"), (494, 901, "h"), (588, 695, "v")]
DL = [(390, 490, "v"), (390, 582, "v"), (390, 700, "v"), (390, 840, "v"), (436, 369, "h"), (434, 891, "h"), (373, 955, "v"),
      (280, 887, "h"), (484, 427, "v"), (410, 440, "v"), (478, 490, "v"), (484, 570, "v"), (410, 570, "v"), (484, 695, "v"),
      (410, 800, "v"), (484, 816, "v")]
F = {"Observation Lounge": [ring(494, 300, 32), ring(494, 300, 14)], "Gunnery Control": [arc(494, 900, 32, 25, 155)],
     "Captain's Office": [ring(540, 695, 18)]}
pair_f(F, {"Star Chart Room": [ring(395, 334, 12)], "War Room": [ring(448, 570, 12)],
           "Officers' Quarters": [box(330, 470, 375, 484), box(330, 494, 375, 508)],
           "Officer Cabins": [LineString([(290, 562), (360, 562)]), LineString([(280, 601), (360, 601)])],
           "Officers' Lounge": [arc(300, 700, 34, 120, 240)], "Galley": [LineString([(250, 812), (310, 812)])],
           "Comms Array": [arc(448, 860, 40, 240, 300)]}, TWIN)
F["Captain's Quarters"] = [box(425, 650, 470, 690)]
SHORT = {"Star Chart Room (port)": "Star Chart P", "Star Chart Room (starboard)": "Star Chart S",
         "Officers' Lounge (port)": "Lounge P", "Officers' Lounge (starboard)": "Lounge S",
         "Turret Access (port)": "Turret P", "Turret Access (starboard)": "Turret S",
         "Officers' Quarters A": "Officers A", "Officers' Quarters B": "Officers B", "Officer Cabins A": "Cabins A",
         "Officer Cabins B": "Cabins B", "Observation Lounge": "Observation", "Gunnery Control": "Gunnery",
         "Captain's Quarters": "Captain's Qtrs", "Captain's Office": "Capt. Office", "Navigation Room": "Navigation",
         "Security Office": "Security", "Weapons Locker": "Weapons", "Shield Control": "Shields", "Fire Control": "Fire Ctrl",
         "Sensor Station": "Sensors", "Comms Array": "Comms"}
bad = decklib.run("imperium_trooptransport", HERE, SRC, AX, "upper", 1, R, HALLS, DC + mir(DL), [LIFT_A],
                  title="UPPER DECK - COMMAND", features=F, short=SHORT, whole=WHOLE)

# ===================================================================== LOWER DECK - HOLD
LOOP = hall((494, 570), (410, 570), (380, 600), (380, 1080), (410, 1110), (494, 1110), w=20)
HALLS = [hall((494, 460), (494, 582), w=20), hall((494, 828), (494, 1122), w=20), LOOP, M(LOOP),
         hall((380, 840), (608, 840), w=20), circle(494, 570, 20), circle(494, 840, 20), circle(494, 1110, 20),
         box(500, 470, 510, 510), hall((472, 520), (484, 520), w=16), hall((504, 540), (584, 540), w=16)]
R = {"Brig": box(476, 592, 512, 820)}                                                   # the cell corridor
for i in range(4): R["Holding Cell %d" % (i + 1)] = box(512, 592 + i * 57, 584, 592 + (i + 1) * 57)
R["Detention Office"] = box(404, 592, 476, 700)
R["Holding Cell 5"] = box(404, 700, 476, 760)
R["Holding Cell 6"] = box(404, 760, 476, 820)
R["Coolant Pumps"] = circle(494, 1170, 40)
R["Escape Pods"] = sector(494, 1150, 66, 90, 30, 150)
R["Water Recycling"] = circle(430, 510, 42)
R["Life Support"] = circle(585, 498, 30)
R["Lift B"] = box(510, 470, 548, 510)
TWIN = {"Spare Parts": ("Spare Parts", "Medical Store"), "Drop Pod Bay": ("Drop Pod Bay A", "Drop Pod Bay B"),
        "Cargo Hold": ("Cargo Hold A", "Cargo Hold B"), "Machine Shop": ("Machine Shop", "Fuel Store"),
        "Battery Room": ("Battery Room", "Shield Generator")}
pair(R, {"Machine Shop": octa(392, 1120, 450, 1176, 12),
         "Battery Room": clip(octa(296, 1044, 370, 1118, 14)),
         "Cargo Hold": octa(392, 852, 484, 1098, 16),
         "Ammo Store": clip(box(250, 452, 370, 640)),
         "Guard Post": clip(octa(250, 642, 370, 740, 12)),
         "Spare Parts": clip(box(220, 742, 370, 860)),
         "Drop Pod Bay": clip(octa(200, 862, 370, 1000, 14)),
         "Pod Launch Control": clip(Polygon([(370, 1002), (370, 1040), (270, 1040), (240, 1002)]))}, TWIN)
WHOLE = {"Brig", "Coolant Pumps", "Escape Pods", "Water Recycling", "Life Support", "Lift B",
         "Machine Shop", "Fuel Store", "Battery Room", "Shield Generator"} | {"Holding Cell %d" % i for i in range(2, 7)}
R = decklib.settle(R, HALLS, whole=WHOLE)
DC = [(494, 591, "h"), (494, 1130, "h"), (494, 1214, "h"), (510, 490, "v"), (585, 530, "h"), (476, 646, "v"), (476, 730, "v"),
      (476, 790, "v")] + [(512, 620 + i * 57, "v") for i in range(4)]
DL = [(471, 520, "v"), (370, 625, "v"), (370, 690, "v"), (370, 800, "v"), (370, 930, "v"), (370, 1020, "v"), (370, 1078, "v"), (484, 970, "v"),
      (391, 970, "v"), (422, 1120, "h")]
F = {"Water Recycling": [ring(430, 510, 28), ring(430, 510, 12)], "Life Support": [ring(585, 498, 19), ring(585, 498, 8)],
     "Coolant Pumps": [ring(494, 1170, 26), ring(494, 1170, 12)]}
for i in range(4): F["Holding Cell %d" % (i + 1)] = [box(548, 600 + i * 57, 576, 612 + i * 57)]        # the bunk
for k, y in (("Holding Cell 5", 708), ("Holding Cell 6", 768)): F[k] = [box(412, y, 440, y + 12)]
pair_f(F, {"Spare Parts": [box(262, 760, 360, 768), box(262, 800, 360, 808), box(262, 838, 360, 846)],
           "Machine Shop": [ring(421, 1149, 10)],
           "Cargo Hold": [box(410, 880, 440, 910), box(410, 930, 440, 960), box(410, 1040, 440, 1070)],
           "Battery Room": [ring(333, 1081, 16)],
           "Guard Post": [ring(305, 692, 16)],
           "Drop Pod Bay": [ring(232, 900 + i * 30, 9) for i in range(4)]}, TWIN)
SHORT = {"Pod Launch Control (port)": "Pod Launch P", "Pod Launch Control (starboard)": "Pod Launch S",
         "Ammo Store (port)": "Ammo P", "Ammo Store (starboard)": "Ammo S", "Guard Post (port)": "Guard P",
         "Guard Post (starboard)": "Guard S", "Water Recycling": "Water", "Life Support": "Life Sup.",
         "Detention Office": "Detention", "Shield Generator": "Shield Gen", "Coolant Pumps": "Coolant",
         "Machine Shop": "Machine", "Fuel Store": "Fuel", "Battery Room": "Battery", "Escape Pods": "Pods",
         "Medical Store": "Med Store", "Drop Pod Bay A": "Drop Pods A", "Drop Pod Bay B": "Drop Pods B"}
SHORT.update({"Holding Cell %d" % i: "Cell %d" % i for i in range(1, 7)})
bad += decklib.run("imperium_trooptransport", HERE, SRC, AX, "lower", -1, R, HALLS, DC + mir(DL), [LIFT_B],
                   title="LOWER DECK - HOLD", features=F, short=SHORT, whole=WHOLE,
                   anchor={"Escape Pods": (494, 1228)})
decklib.both(os.path.join(HERE, "deck_upper_on_map.jpg"), os.path.join(HERE, "deck_lower_on_map.jpg"), os.path.join(HERE, "decks_on_map.jpg"))
decklib.both(os.path.join(HERE, "deck_upper.png"), os.path.join(HERE, "deck_lower.png"), os.path.join(HERE, "decks_plan.jpg"))
print("TOTAL FAILURES:", len(bad))
sys.exit(1 if bad else 0)
