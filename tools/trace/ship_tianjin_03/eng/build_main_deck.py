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
CY, T, DOOR = 1160.0, 12.0, 56.0   # mirror line from paired rooms (548/1782, 649/1681)
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
pod_walls = [wall((2145, 785), (2310, 785), []),    # owner O: comm room / side room closed wall((2310, 615), (2310, 970), [85, 310]),
             wall((2515, 636), (2515, 913), [135]), wall((2650, 640), (2650, 875), [118]),
             wall((2190, 900), (2190, 985), [])]
corridor = unary_union([LineString([(2120, CY), (2625, CY)]).buffer(50, cap_style=2),
                        Polygon([(2250, CY), (2330, 1060), (2510, 1060), (2580, CY), (2510, 1250), (2330, 1250)])])
bay = unary_union([box(2620, 1010, 2800, 1300), box(2800, 1030, 2855, 1280)])
bay_walls = [wall((2620, 1010), (2620, 1300), [145]), wall((2800, 1030), (2800, 1280), [125])]

# ---- section 2: the room column between the pods and the CIC (boxes measured on the x4 deck, top half; mirrored)
G = 11   # half the wall gap between neighbouring rooms: rooms grow to the wall centre line
rooms2 = [box(1972, 548, 2086, 627), box(2041, 649, 2134, 841), unary_union([box(1927, 673, 2025, 760), box(1912, 751, 2022, 851)]),
          box(1967, 861, 2120, 1037)]
centre = box(1883, 1056, 2119, 2 * CY - 1056)
col = unary_union([r.buffer(G, join_style=2) for r in rooms2])
col = unary_union([col, mirror(col), centre.buffer(G, join_style=2)])
s2_walls = [wall((1901, 638), (2150, 638), [168]),     # owner X: escape-pod room opens into the lobby                 # escape-pod room / lobby row, door into the side room
            wall((2033, 638), (2033, 853), [122]),                 # side room / lobby
            wall((1901, 853), (2150, 853), [189]),     # owner O: side room / ready room closed             # to the ready room
            wall((1872, 1047), (2131, 1047), [117]),               # ready room / centre room
            wall((2145, 638), (2145, 853), [122])]                 # lobby / pod (the pod's aft door)
s2_walls = s2_walls + [mirror(w) for w in s2_walls] + [
            wall((2120, 1047), (2120, 2 * CY - 1047), [CY - 1047]),   # centre room / forward corridor
            wall((1872, 1047), (1872, 2 * CY - 1047), [CY - 1047])]   # centre room / CIC (next section)
# ---- section 3: round CIC (circle fit R 201 about (1640, 1161)), the spine aft, two octagon rooms on links
from shapely.geometry import Point
def octagon(cx, cy, a):   # regular octagon, flat top/bottom/sides, apothem a
    r = a / np.cos(np.pi / 8)
    return Polygon([(cx + r * np.cos(np.pi / 8 + k * np.pi / 4), cy + r * np.sin(np.pi / 8 + k * np.pi / 4)) for k in range(8)])
cic3 = Point(1640, CY).buffer(201, 128)
spine = box(900, CY - 42, 1445, CY + 42)                       # wall centres 1118 / 1202 (measured 1122 / 1205)
cic_link = box(1835, CY - DOOR / 2 - 14, 1885, CY + DOOR / 2 + 14)
octa = octagon(1273, 915, 120)
olink = box(1216, 1030, 1288, CY - 30)                         # octagon down to the spine
stub = box(1604, 860, 1676, 970)                                # CIC up to the Galley wedge (next section)
s3_walls = [wall((1216, 1031), (1288, 1031), [36]), wall((1216, CY - 42), (1288, CY - 42), [36])]   # framed doors at both ends
s3_walls = s3_walls + [mirror(w) for w in s3_walls] + [
    wall((1445, CY - 42), (1445, CY + 42), [42]),               # spine into the CIC
    wall((1604, 965), (1676, 965), [36]), mirror(wall((1604, 965), (1676, 965), [36]))]
s3 = unary_union([cic3, spine, cic_link, octa, mirror(octa), olink, mirror(olink), stub, mirror(stub)])
floor = unary_union([pod, mirror(pod), corridor, bay, col, s3])
walls = floor.buffer(T / 2, join_style=2).difference(floor.buffer(-T / 2, join_style=2))
inner = unary_union(pod_walls + [mirror(w) for w in pod_walls] + bay_walls + s2_walls + s3_walls).intersection(floor.buffer(T / 2, join_style=2))   # no stubs outside
walls = unary_union([walls, inner])
for o in [box(880, CY - 36, 912, CY + 36),                            # spine runs on aft (next section)
          box(1610, 850, 1670, 868), mirror(box(1610, 850, 1670, 868))]:   # CIC stubs run on (next section)
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
cv2.imwrite(os.path.join(HERE, "main_s3_big.jpg"), cv2.resize(ov[600:1720, 860:1900], None, fx=1.3, fy=1.3, interpolation=cv2.INTER_CUBIC), [cv2.IMWRITE_JPEG_QUALITY, 90])
cv2.imwrite(os.path.join(HERE, "main_s2_big.jpg"), cv2.resize(ov[500:1830, 1820:2340], None, fx=1.6, fy=1.6, interpolation=cv2.INTER_CUBIC), [cv2.IMWRITE_JPEG_QUALITY, 90])
json.dump({"units": "x4 main-deck px", "mirror_y": CY, "thickness": T, "door": DOOR, "floor": mapping(floor), "walls": mapping(walls)},
          open(os.path.join(HERE, "main_plan.json"), "w"))
print("ok")
