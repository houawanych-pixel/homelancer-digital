#!/usr/bin/env python3
"""Library piece: WING PIE (owner, Nov 18 2026): the wing the owner drew in red on the SWTOR station map
(markup.jpg) - "use this shape as the inner pie shape". The red loop is filled (red_fill.png, dashes joined), then
redrawn clean in polar form about the station's middle (the centre of the map's own curved walls, fitted: 870, 1010):
every edge is either an ARC (constant radius, radii merged to a few levels) or a RADIAL wall (constant angle), so the
cabin teeth on the rim and the notches on the inner side come out as true arcs and straight radial cuts.
Output: piece.json (polygon in map px + polar form), piece.png (white on black), piece_on_map.jpg (blue on the map)."""
import json, math, os
import cv2, numpy as np
from shapely.geometry import Polygon, mapping

HERE = os.path.dirname(os.path.abspath(__file__))
CX, CY = 870.0, 1010.0
f = cv2.imread(os.path.join(HERE, "red_fill.png"), 0) > 0
cs, _ = cv2.findContours(f.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
c = max(cs, key=cv2.contourArea).reshape(-1, 2).astype(float)
th = np.degrees(np.arctan2(c[:, 1] - CY, c[:, 0] - CX)); r = np.hypot(c[:, 0] - CX, c[:, 1] - CY)
RM = float(np.median(r)); K = RM * math.pi / 180          # px per degree at the middle radius
P = np.stack([th * K, r], 1).astype(np.float32)
s = cv2.approxPolyDP(P.reshape(-1, 1, 2), 7.0, True).reshape(-1, 2).astype(float)
v = np.stack([s[:, 0] / K, s[:, 1]], 1)                    # (deg, r)
n = len(v)
# classify each edge: radial (r changes more than the arc length) or arc
kind = []
for i in range(n):
    a, b = v[i], v[(i + 1) % n]
    kind.append("R" if abs(b[1] - a[1]) > abs(b[0] - a[0]) * K else "A")
# merge radii of arcs into levels (within 10 px), merge angles of radials that are within 0.6 deg of each other
arcs = sorted((v[i][1] + v[(i + 1) % n][1]) / 2 for i in range(n) if kind[i] == "A")
levels = []
for x in arcs:
    if levels and x - levels[-1][-1] < 10: levels[-1].append(x)
    else: levels.append([x])
LV = [float(np.mean(l)) for l in levels]
snapr = lambda x: min(LV, key=lambda L: abs(L - x))
# rebuild vertices: each vertex = (angle of its radial edge, radius of its arc edge)
out = []
for i in range(n):
    e0, e1 = kind[i - 1], kind[i]           # edge before, edge after vertex i
    a_prev, a_next = v[i - 1], v[(i + 1) % n]
    if e0 == "A" and e1 == "R":
        ang = (v[i][0] + a_next[0]) / 2; rad = snapr((a_prev[1] + v[i][1]) / 2)
    elif e0 == "R" and e1 == "A":
        ang = (a_prev[0] + v[i][0]) / 2; rad = snapr((v[i][1] + a_next[1]) / 2)
    elif e0 == "A" and e1 == "A":           # two arcs meet at a step: keep the vertex angle, a radial joint is implied
        ang = v[i][0]; rad = snapr((a_prev[1] + v[i][1]) / 2); out.append((ang, rad)); rad = snapr((v[i][1] + a_next[1]) / 2)
    else:
        ang = v[i][0]; rad = v[i][1]
    out.append((ang, rad))
# sample: arcs every 0.5 deg
pts = []
for i in range(len(out)):
    a, b = out[i], out[(i + 1) % len(out)]
    if abs(a[1] - b[1]) < 0.5 and abs(a[0] - b[0]) > 0.5:
        for t in np.linspace(a[0], b[0], max(2, int(abs(b[0] - a[0]) / 0.5)), endpoint=False):
            pts.append((CX + a[1] * math.cos(math.radians(t)), CY + a[1] * math.sin(math.radians(t))))
    else:
        pts.append((CX + a[1] * math.cos(math.radians(a[0])), CY + a[1] * math.sin(math.radians(a[0]))))
poly = Polygon(pts).buffer(0)
if poly.geom_type != "Polygon": poly = max(poly.geoms, key=lambda q: q.area)
src = cv2.imread(os.path.join(HERE, "markup.jpg"))
plan = np.zeros_like(src); ov = (src * 0.45).astype(np.uint8)
ring = np.array(poly.exterior.coords, np.int32)
cv2.polylines(plan, [ring], True, (255, 255, 255), 3, cv2.LINE_AA)
cv2.polylines(ov, [ring], True, (255, 150, 30), 4, cv2.LINE_AA)
x0, y0, x1, y1 = [int(q) for q in poly.bounds]
cv2.imwrite(os.path.join(HERE, "piece.png"), plan[max(0, y0 - 30):y1 + 30, max(0, x0 - 30):x1 + 30])
cv2.imwrite(os.path.join(HERE, "piece_on_map.jpg"), ov[max(0, y0 - 30):y1 + 30, max(0, x0 - 30):x1 + 30], [cv2.IMWRITE_JPEG_QUALITY, 90])
json.dump({"name": "wing_pie_01", "source": "owner's red markup on the SWTOR station map, Nov 18 2026", "centre": [CX, CY],
           "radius_levels": LV, "polar": [[round(a, 3), round(b, 2)] for a, b in out], "shape": mapping(poly), "units": "markup px"},
          open(os.path.join(HERE, "piece.json"), "w"))
print("vertices", len(out), "arc levels", [round(x) for x in LV], "angle span", round(min(o[0] for o in out), 1), round(max(o[0] for o in out), 1))
