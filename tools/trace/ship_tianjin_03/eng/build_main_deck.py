#!/usr/bin/env python3
"""UPP Tianjin main deck as a clean engineering plan, built section by section (measured on part_main_deck_x4.jpg,
EDSR x4 of the sheet, px). The deck mirrors about y = CY. Floors are polygons from the measured wall lines; walls =
floor edge +/- T/2; interior walls are centre lines with standard doors (DOOR clear). Section 1: forward (Communication
Centre pod, mirrored Gunnery pod, forward corridor with its bulge, Forward Missile Bay)."""
import json, os
import cv2, numpy as np
from shapely.geometry import LineString, Polygon, box, mapping
from shapely.ops import unary_union, substring
from shapely import affinity

HERE = os.path.dirname(os.path.abspath(__file__))
CY, T, DOOR = 1155.0, 12.0, 56.0
def mirror(g): return affinity.scale(g, yfact=-1, origin=(0, CY))
def wall(p0, p1, doors=()):
    L = LineString([p0, p1]); cuts = [0.0]
    for d in doors: cuts += [d - DOOR / 2, d + DOOR / 2]
    cuts.append(L.length)
    return unary_union([substring(L, cuts[i], cuts[i + 1]).buffer(T / 2, cap_style=2) for i in range(0, len(cuts), 2) if cuts[i + 1] > cuts[i]])

# ---- section 1: forward
pod = unary_union([
    box(2145, 605, 2310, 900), box(2190, 860, 2310, 985),                         # comm room, side room
    Polygon([(2310, 615), (2650, 650), (2650, 875), (2310, 970)]),               # tapered main hall
    Polygon([(2650, 640), (2725, 640), (2765, 690), (2765, 815), (2725, 870), (2650, 870)]),   # nose cap
])
pod_walls = [wall((2145, 785), (2310, 785), [85]), wall((2310, 615), (2310, 970), [85, 310]),
             wall((2515, 636), (2515, 913), [135]), wall((2650, 640), (2650, 875), [118]),
             wall((2190, 900), (2190, 985), [])]
corridor = unary_union([LineString([(2120, CY), (2625, CY)]).buffer(50, cap_style=2),
                        Polygon([(2250, CY), (2330, 1060), (2510, 1060), (2580, CY), (2510, 1250), (2330, 1250)])])
bay = unary_union([box(2620, 1010, 2800, 1300), box(2800, 1030, 2855, 1280)])
bay_walls = [wall((2620, 1010), (2620, 1300), [145]), wall((2800, 1030), (2800, 1280), [125])]

floor = unary_union([pod, mirror(pod), corridor, bay])
walls = floor.buffer(T / 2, join_style=2).difference(floor.buffer(-T / 2, join_style=2))
inner = unary_union(pod_walls + [mirror(w) for w in pod_walls] + bay_walls)
walls = unary_union([walls, inner])
for o in [box(2100, CY - 44, 2128, CY + 44),                          # corridor runs on aft (next section)
          box(2130, 800, 2160, 856), mirror(box(2130, 800, 2160, 856))]:   # pod doors aft (next section)
    walls = walls.difference(o)

src = cv2.imread(os.path.join(HERE, "..", "part_main_deck_x4.jpg")); H, W = src.shape[:2]
mask = np.zeros((H, W), np.uint8)
for p in getattr(walls, "geoms", [walls]):
    m1 = np.zeros_like(mask); cv2.fillPoly(m1, [np.array(p.exterior.coords, np.int32)], 255)
    for r in p.interiors: cv2.fillPoly(m1, [np.array(r.coords, np.int32)], 0)
    mask |= m1
cs, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
plan = np.zeros_like(src); ov = (src * 0.5).astype(np.uint8)
for im in (plan, ov): cv2.drawContours(im, cs, -1, (255, 255, 255), 3, cv2.LINE_AA)
cv2.imwrite(os.path.join(HERE, "main_plan.png"), plan)
cv2.imwrite(os.path.join(HERE, "main_plan_on_map.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 88])
cv2.imwrite(os.path.join(HERE, "main_plan_section1.jpg"), ov[520:1800, 1900:2950], [cv2.IMWRITE_JPEG_QUALITY, 90])
json.dump({"units": "x4 main-deck px", "mirror_y": CY, "thickness": T, "door": DOOR, "floor": mapping(floor), "walls": mapping(walls)},
          open(os.path.join(HERE, "main_plan.json"), "w"))
print("ok")
