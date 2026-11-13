#!/usr/bin/env python3
"""Imperium Troop Transport main deck as a clean engineering plan, measured on the owner's HoloDeck sheet
(source.jpg, 988 x 1591 px). Scale: the sheet's hallways are 20 px wide = 2 m, so 10 px = 1 m (ship ~153 m long).
One wall thickness T (0.4 m), one door width DOOR (1.6 m). The sheet mirrors about x = 494: the left half is drawn
and mirrored. Everything here is in source px. PROPOSED = not on the sheet (for the owner to X / O)."""
import json, os
import cv2, numpy as np
from shapely import affinity
from shapely.geometry import LineString, Point, Polygon, box, mapping
from shapely.ops import unary_union, substring

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "source.jpg")
PX_PER_M = 10.0
T, DOOR, CW = 4.0, 16.0, 20.0          # wall, door, hallway width (px)
AX = 494.0
M = lambda g: affinity.scale(g, -1, 1, origin=(AX, 0))

def hall(*pts, w=CW):
    return LineString(pts).buffer(w / 2, cap_style=2, join_style=2)
def ellipse(cx, cy, rx, ry):
    return affinity.scale(Point(cx, cy).buffer(1.0, 64), rx, ry)

# ---- rooms (left half + centre line pieces); name -> geometry ------------------------------------------------
R = {}
R["Bridge"] = ellipse(494, 147, 62, 50)
R["Sensors Suite"] = box(455, 197, 533, 285)
R["Command & Control"] = Point(494, 377).buffer(58, 64)
R["Troop Bay"] = box(380, 573, 608, 937)
R["Vehicle / Dropship Bay"] = box(268, 962, 720, 1095)
R["Engineering Deck"] = box(397, 1113, 591, 1240)
R["Reactor Core"] = Point(494, 1288).buffer(47, 64)
R["Engine Room"] = Polygon([(422, 1337), (566, 1337), (566, 1400), (530, 1462), (520, 1500), (468, 1500), (458, 1462), (422, 1400)])
L = {}                                   # left-side rooms (mirrored to B / right)
L["Sensor Store"] = Polygon([(402, 240), (452, 205), (452, 298), (402, 298)])
L["Briefing Room"] = Polygon([(340, 330), (350, 300), (412, 300), (412, 417), (340, 417)])
L["Armory"] = Polygon([(303, 465), (328, 442), (412, 442), (412, 553), (303, 553)])
L["Lift"] = box(440, 470, 478, 510)
L["Barracks"] = Polygon([(232, 620), (268, 575), (356, 575), (356, 730), (232, 730)])
L["Ready Room"] = box(232, 730, 356, 845)
L["Lockers"] = Polygon([(230, 848), (345, 848), (356, 859), (356, 940), (230, 940)])
L["Deploy Bay"] = Polygon([(130, 742), (180, 742), (190, 930), (110, 935), (100, 895)])
L["Maint. Bay"] = box(262, 1115, 372, 1230)
RIGHT_NAME = {"Sensor Store": "Sensor Store B", "Briefing Room": "Comms Center", "Armory": "Medbay", "Lift": "Lift B",
              "Barracks": "Barracks B", "Ready Room": "Ready Room B", "Lockers": "Lockers B", "Deploy Bay": "Deploy Bay B",
              "Maint. Bay": "Supply Depot"}
LEFT_NAME = {"Sensor Store": "Sensor Store A", "Lift": "Lift A", "Barracks": "Barracks A", "Ready Room": "Ready Room A",
             "Lockers": "Lockers A", "Deploy Bay": "Deploy Bay A"}
for k, g in L.items():
    R[LEFT_NAME.get(k, k)] = g
    R[RIGHT_NAME[k]] = M(g)

# ---- hallways --------------------------------------------------------------------------------------------------
HL = []
HL.append(box(484, 285, 504, 320))                        # sensors -> C&C
HL.append(box(458, 433, 530, 455))                        # lobby under C&C
HL.append(hall((424, 298), (424, 563)))                   # left spine (sensor store -> H2)
HL.append(hall((468, 455), (468, 470)))                   # lift corridor above the lift
HL.append(hall((468, 510), (468, 563)))                   # and below it
HL.append(hall((303, 563), (685, 563)))                   # H2 across the top of the troop bay
HL.append(hall((368, 563), (368, 951)))                   # beside the troop bay
HL.append(hall((217, 748), (217, 1065), (268, 1065)))     # outer side hall (ready room, lockers, vehicle bay)
HL.append(hall((217, 951), (771, 951)))                   # H3 across the bottom of the troop bay
HL.append(hall((262, 1104), (726, 1104), w=18))           # H4 under the vehicle bay
HL.append(hall((385, 1104), (385, 1272)))                 # down the side of engineering
HL.append(hall((375, 1272), (447, 1272)))                 # into the reactor's side door
HL.append(hall((186, 870), (207, 870), w=DOOR + 2 * T))   # PROPOSED: deploy bay -> outer side hall (sheet shows no door)
left_halls = HL[2:]
HALLS = HL[:2] + left_halls + [M(h) for h in left_halls]

# ---- doors: (x, y, 'h' wall runs horizontally | 'v' vertically); mirrored unless on the centre line ------------
D_CENTRE = [(494, 197, "h"), (494, 285, "h"), (494, 319, "h"), (494, 435, "h"), (494, 1095, "h"), (494, 1113, "h"),
            (494, 1240, "h"), (494, 1336, "h"), (470, 573, "h"), (470, 937, "h")]
D_LEFT = [(454, 257, "v"), (424, 298, "h"), (412, 330, "v"), (436, 377, "v"), (412, 452, "v"), (368, 553, "h"),
          (468, 470, "h"), (468, 510, "h"), (356, 615, "v"), (330, 730, "h"), (232, 785, "v"), (356, 780, "v"),
          (230, 877, "v"), (356, 897, "v"), (380, 650, "v"), (380, 752, "v"), (380, 867, "v"), (268, 1065, "v"),
          (310, 962, "h"), (310, 1115, "h"), (372, 1168, "v"), (397, 1168, "v"), (410, 1113, "h"), (447, 1272, "v"),
          (190, 870, "v")]
DOORS = D_CENTRE + D_LEFT + [(2 * AX - x, y, o) for x, y, o in D_LEFT if abs(x - AX) > 1]
PROPOSED_DOORS = [(190, 870), (2 * AX - 190, 870)]

def door_box(x, y, o, depth):
    return box(x - DOOR / 2, y - depth, x + DOOR / 2, y + depth) if o == "h" else box(x - depth, y - DOOR / 2, x + depth, y + DOOR / 2)

def build():
    floor = unary_union(list(R.values()) + HALLS + [door_box(x, y, o, T * 2.6) for x, y, o in DOORS]).buffer(0.5).buffer(-0.5)
    # every room outline is a wall; then cut one standard door at each door point
    # every room outline is a wall; the hallways are one network (their union), so halls meet with no wall between
    halls = unary_union(HALLS)
    rings = [g.exterior.buffer(T / 2, join_style=2) for g in R.values()]
    for p in getattr(halls, "geoms", [halls]):
        rings.append(p.exterior.buffer(T / 2, join_style=2))
        rings += [r.buffer(T / 2, join_style=2) for r in p.interiors]
    walls = unary_union(rings)
    cut = [door_box(x, y, o, T * 2.6) for x, y, o in DOORS]
    walls = walls.difference(unary_union(cut))
    walls = walls.intersection(floor.buffer(T / 2, join_style=2))
    walls = unary_union([p for p in getattr(walls, "geoms", [walls]) if p.area > 8])
    return floor, walls

def raster(g, shape):
    """fill a (multi)polygon with its holes cut out"""
    out = np.zeros(shape, np.uint8)
    for p in getattr(g, "geoms", [g]):
        m1 = np.zeros(shape, np.uint8)
        cv2.fillPoly(m1, [np.array(p.exterior.coords, np.int32)], 1)
        for r in p.interiors: cv2.fillPoly(m1, [np.array(r.coords, np.int32)], 0)
        out |= m1
    return out

def reach(floor, walls, start):
    """flood fill on a 1 px grid: every room centre must be reachable from start"""
    W, H = 988, 1591
    m = np.zeros((H, W), np.uint8)
    m[raster(floor, (H, W)) > 0] = 1
    m[raster(walls, (H, W)) > 0] = 0
    n, lab = cv2.connectedComponents(m, connectivity=4)
    s = lab[int(start[1]), int(start[0])]
    out = {}
    for k, g in R.items():
        c = g.representative_point()
        out[k] = bool(lab[int(c.y), int(c.x)] == s and s != 0)
    return out

def draw(floor, walls, path_png, path_jpg):
    src = cv2.imread(SRC)
    plan = np.zeros_like(src); ov = (src * 0.4).astype(np.uint8)
    for p in getattr(walls, "geoms", [walls]):
        pts = np.array(p.exterior.coords, np.int32)
        for im in (plan, ov): cv2.fillPoly(im, [pts], (255, 255, 255))
        for r in p.interiors:
            for im, base in ((plan, None), (ov, src)):
                mk = np.zeros(im.shape[:2], np.uint8); cv2.fillPoly(mk, [np.array(r.coords, np.int32)], 1)
                im[mk > 0] = 0 if base is None else (base[mk > 0] * 0.4).astype(np.uint8)
    for x, y in PROPOSED_DOORS:
        for im in (plan, ov): cv2.circle(im, (int(x), int(y)), 14, (0, 200, 255), 2, cv2.LINE_AA)
    for k, g in R.items():
        c = g.representative_point(); t = k.upper()
        (w, h), _ = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, 0.32, 1)
        cv2.putText(plan, t, (int(c.x - w / 2), int(c.y + h / 2)), cv2.FONT_HERSHEY_SIMPLEX, 0.32, (255, 220, 120), 1, cv2.LINE_AA)
    cv2.imwrite(path_png, plan); cv2.imwrite(path_jpg, ov, [cv2.IMWRITE_JPEG_QUALITY, 88])

if __name__ == "__main__":
    floor, walls = build()
    START = (150, 840)   # Deploy Bay A: the airlock you board through
    rc = reach(floor, walls, START)
    bad = [k for k, v in rc.items() if not v]
    print("rooms", len(R), "unreachable:", bad)
    draw(floor, walls, os.path.join(HERE, "plan.png"), os.path.join(HERE, "plan_on_map.jpg"))
    json.dump({"ship": "imperium_trooptransport", "units": "source px", "px_per_m": PX_PER_M, "thickness": T, "door": DOOR,
               "mirror_x": AX, "start": START, "rooms": {k: mapping(g) for k, g in R.items()},
               "doors": DOORS, "proposed_doors": PROPOSED_DOORS, "floor": mapping(floor), "walls": mapping(walls)},
              open(os.path.join(HERE, "plan.json"), "w"))
