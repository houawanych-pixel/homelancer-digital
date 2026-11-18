#!/usr/bin/env python3
"""alien_lib_index.py MAPDIR [...] -> room_library/alien_rooms.json + room_library/alien_rooms_sheet.jpg
Gathers the rooms of every Alien: Isolation map (alien_lib.py output, MAPDIR/lib/pieces.json) into one room library:
each room moved to its own origin (top-left of its box = 0,0), with its door faces, its size in map px and in GRID
CELLS (the map's own background grid, measured per map, so every map is on one common scale), and where it came from.
The real size in metres is set later (owner: one grid cell = ? m)."""
import json, math, os, sys
import cv2, numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "room_library"); os.makedirs(OUT, exist_ok=True)

def grid_pitch(img):
    """The background grid's spacing in px: the strongest repeat of the faint grid lines (autocorrelation)."""
    g = img.astype(np.float32).mean(2)
    best = []
    for prof in (g.mean(0), g.mean(1)):
        p = prof - cv2.GaussianBlur(prof.reshape(1, -1), (0, 0), 6).ravel()
        p = p - p.mean(); ac = np.correlate(p, p, "full")[len(p) - 1:]
        ac[:12] = -1e9
        best.append(int(np.argmax(ac[:120])))
    return float(np.median(best))

rooms, sheet_items = [], []
for mdir in sys.argv[1:]:
    lib = json.load(open(os.path.join(mdir, "lib", "pieces.json")))
    y0, y1, x0, x1 = lib["crop"]
    src = cv2.imread(os.path.join(mdir, "source.png"))[y0:y1, x0:x1]
    pitch = grid_pitch(src)
    for p in lib["pieces"]:
        if p["kind"] != "room" or not p["bbox"]: continue
        bx, by = p["bbox"][0], p["bbox"][1]
        def mv(q): return [round(q[0] - bx, 2), round(q[1] - by, 2)]
        r = {"id": "%s/%s" % (lib["map"], p["id"]), "map": lib["map"], "source_room": p["id"],
             "w_px": round(p["bbox"][2] - p["bbox"][0], 1), "h_px": round(p["bbox"][3] - p["bbox"][1], 1),
             "grid_px": pitch, "w_cells": round((p["bbox"][2] - p["bbox"][0]) / pitch, 2), "h_cells": round((p["bbox"][3] - p["bbox"][1]) / pitch, 2),
             "area_cells": round(p["area"] / pitch / pitch, 2),
             "rings": [{"hole": rg["hole"], "pts": [mv(q) for q in rg["pts"]]} for rg in p["rings"]],
             "doors": [{"a": mv(d["a"]), "b": mv(d["b"]), "width_px": d["width"], "width_cells": round(d["width"] / pitch, 2),
                        "out": d["out"], "to": d["to"]} for d in p["doors"]]}
        rooms.append(r)
json.dump({"units": "map px (each room from 0,0); *_cells = the map's own grid cells", "count": len(rooms), "rooms": rooms},
          open(os.path.join(OUT, "alien_rooms.json"), "w"), indent=0)
# one sheet of every room, all on ONE scale (grid cells), so sizes compare
T, cols = 260, 8
cell = 26.0   # sheet px per grid cell
rows = math.ceil(len(rooms) / cols)
sheet = np.zeros((rows * T, cols * T, 3), np.uint8)
for k, r in enumerate(rooms):
    sc = min(cell / r["grid_px"], (T - 40) / max(r["w_px"], r["h_px"]))
    ox = (k % cols) * T + (T - r["w_px"] * sc) / 2; oy = (k // cols) * T + 24 + (T - 34 - r["h_px"] * sc) / 2
    def tf(q): return (int(ox + q[0] * sc), int(oy + q[1] * sc))
    for rg in r["rings"]: cv2.polylines(sheet, [np.array([tf(q) for q in rg["pts"]], np.int32)], True, (255, 150, 30), 2, cv2.LINE_AA)
    for d in r["doors"]: cv2.line(sheet, tf(d["a"]), tf(d["b"]), (40, 220, 255), 3, cv2.LINE_AA)
    lbl = "%d %s" % (k + 1, r["id"].replace("alien_", "").replace("/room_", " #"))
    cv2.putText(sheet, lbl[:34], ((k % cols) * T + 6, (k // cols) * T + 16), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (210, 210, 210), 1, cv2.LINE_AA)
    cv2.putText(sheet, "%.1fx%.1f cells" % (r["w_cells"], r["h_cells"]), ((k % cols) * T + 6, (k // cols + 1) * T - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.38, (150, 150, 150), 1, cv2.LINE_AA)
cv2.imwrite(os.path.join(OUT, "alien_rooms_sheet.jpg"), sheet, [cv2.IMWRITE_JPEG_QUALITY, 90])
print(len(rooms), "rooms")
