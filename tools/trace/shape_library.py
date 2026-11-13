#!/usr/bin/env python3
"""Room shape library from the traced reference ships and stations (owner, 13 Nov 2026, deck design pass 2: "use the
traced shapes"). Each traced plan's walkable floor (floor minus walls) is cut into separate rooms at the door gaps
(shrink by half a door so the pieces part at every doorway, grow back inside the floor), every piece is measured in
metres, and the function tags in shape_tags.json (looked up by hand on each reference picture) are added.

  python3 -I tools/trace/shape_library.py          -> tools/trace/shape_library.json + shape_library_sheet.jpg

Each entry: id, source, tag (function), name, w_m, h_m, area_m2, kind (round / angled / rect / L / wedge / long),
poly (metres, centred on 0,0; +y aft as in the plan)."""
import json, math, os, sys
import cv2, numpy as np
from shapely.geometry import shape, mapping, Polygon
from shapely import affinity
from shapely.ops import unary_union

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = [("fury", "ship_fury_07/eng/plan.json"), ("defender_flight", "ship_defender_05/eng/flight_plan.json"),
       ("defender_lower", "ship_defender_05/eng/lower_plan.json"), ("kasparov_a", "ship_kasparov_04/eng/deck_a_plan.json"),
       ("kasparov_b", "ship_kasparov_04/eng/deck_b_plan.json"), ("malgus", "station_republic_06/eng/plan.json"),
       ("carrick", "station_ring_08/eng/plan.json"), ("tianjin", "ship_tianjin_03/eng/main_plan.json")]

def scale_of(P):
    if "px_per_m" in P: return float(P["px_per_m"])
    return float(P.get("door", 56.0)) / 1.4          # (x4 traces: a reference door is about 1.4 m)

def kind_of(g):
    x0, y0, x1, y1 = g.bounds; w, h = x1 - x0, y1 - y0
    fill = g.area / max(1e-6, w * h)
    circ = 4 * math.pi * g.area / max(1e-6, g.length ** 2)
    if circ > 0.8: return "round"
    if max(w, h) / max(1e-6, min(w, h)) > 3.2: return "long"
    if fill > 0.97: return "rect"
    if fill > 0.85: return "angled"
    if fill > 0.6: return "L"
    return "wedge"

def split(P):
    floor, walls = shape(P["floor"]), shape(P["walls"])
    walk = floor.difference(walls)
    d = float(P.get("door", 56.0)) / 2.0 + 2.0
    core = walk.buffer(-d, join_style=2)
    out = []
    for c in getattr(core, "geoms", [core]):
        if c.area < 4: continue
        g = c.buffer(d, join_style=2).intersection(walk)
        g = max(getattr(g, "geoms", [g]), key=lambda q: q.area)
        out.append(g.simplify(1.0))
    return out

def main():
    tags = json.load(open(os.path.join(HERE, "shape_tags.json"))) if os.path.exists(os.path.join(HERE, "shape_tags.json")) else {}
    lib = []
    sheet_cells = []
    for src, rel in SRC:
        p = os.path.join(HERE, rel)
        if not os.path.exists(p): print("missing", rel); continue
        P = json.load(open(p)); s = scale_of(P)
        pieces = sorted(split(P), key=lambda g: (round(g.centroid.y / 200), g.centroid.x))
        for i, g in enumerate(pieces, 1):
            rid = "%s_%02d" % (src, i)
            t = tags.get(rid, {})
            m = affinity.scale(affinity.translate(g, -g.centroid.x, -g.centroid.y), 1 / s, 1 / s, origin=(0, 0))
            x0, y0, x1, y1 = m.bounds
            lib.append({"id": rid, "source": rel, "tag": t.get("tag", "untagged"), "name": t.get("name", ""),
                        "w_m": round(x1 - x0, 2), "h_m": round(y1 - y0, 2), "area_m2": round(m.area, 1), "kind": kind_of(m),
                        "poly": [[round(x, 2), round(y, 2)] for x, y in m.exterior.coords]})
            sheet_cells.append((rid, m, t.get("tag", "?"), t.get("name", "")))
    json.dump({"units": "m", "rooms": lib}, open(os.path.join(HERE, "shape_library.json"), "w"), indent=0)
    # the preview sheet: every room at one scale (8 px per m), id + function under it
    C = 150; cols = 10; rows = (len(sheet_cells) + cols - 1) // cols
    img = np.zeros((rows * C, cols * C, 3), np.uint8)
    for n, (rid, m, tag, name) in enumerate(sheet_cells):
        cx, cy = (n % cols) * C + C // 2, (n // cols) * C + C // 2 - 10
        x0, y0, x1, y1 = m.bounds; k = min(8.0, 110.0 / max(1e-6, max(x1 - x0, y1 - y0)))
        pts = np.array([[cx + x * k, cy + y * k] for x, y in m.exterior.coords], np.int32)
        cv2.fillPoly(img, [pts], (70, 38, 12)); cv2.polylines(img, [pts], True, (255, 255, 255), 1, cv2.LINE_AA)
        cv2.putText(img, rid, ((n % cols) * C + 4, (n // cols + 1) * C - 22), cv2.FONT_HERSHEY_SIMPLEX, 0.33, (200, 200, 200), 1, cv2.LINE_AA)
        cv2.putText(img, (tag + (" " + name if name else ""))[:26], ((n % cols) * C + 4, (n // cols + 1) * C - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.33, (120, 220, 255), 1, cv2.LINE_AA)
    cv2.imwrite(os.path.join(HERE, "shape_library_sheet.jpg"), img, [cv2.IMWRITE_JPEG_QUALITY, 85])
    from collections import Counter
    print(len(lib), "rooms", Counter(r["source"].split("/")[0] for r in lib), Counter(r["tag"] for r in lib))

if __name__ == "__main__":
    main()
