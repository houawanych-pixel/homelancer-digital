#!/usr/bin/env python3
"""Wall-only trace of a glowing blueprint / game-map floor plan (owner-approved method, 11 Nov 2026).

Rule from the owner: the outside silhouette is automatically wall, a hard trace line. Inside it, everything is floor
(furniture, pillars, consoles, labels vanish); big dark enclosed voids (open courts) are holes.
  1. wall lines = thin bright cyan lines: a top-hat (bright vs its surroundings, so dim walls on a bright floor still
     show), coloured (saturation), minus white text / number circles and full-width phone UI bars;
  2. gaps in the outline are sealed (closing --seal px; doors are bridged too: they are added later);
  3. outside = what touches the picture edge; the solid = everything else; voids larger than --court px and darker
     than --dark become holes; the largest piece is the station;
  4. the outline is straightened (approxPolyDP) and drawn white on black, plus a red overlay on the source.
Two styles of map (--mode):
  line  (default) thin bright walls on a lit floor, many separate rooms (temple_02).
  glow  one glowing outline on a dark floor (hub_hex_01): the walls are simply pixels brighter than --bright, outside =
        what touches the edge, the enclosed voids other than the main floor larger than --court become holes.
Output (OUTDIR): source_crop.png, walls_trace.png, walls_overlay.jpg, walls_px.json (polygons in crop pixels).

usage: python3 -I wall_trace.py IMAGE OUTDIR [--crop y0:y1,x0:x1] [--seal 17] [--court 30000] [--dark 65]
"""
import argparse, json, os
import cv2, numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("image"); ap.add_argument("out")
ap.add_argument("--crop", default="")
ap.add_argument("--line", type=int, default=25, help="top-hat level of a wall line")
ap.add_argument("--sat", type=int, default=90, help="min saturation of a wall line (white text is below)")
ap.add_argument("--seal", type=int, default=17, help="closes gaps in the outline up to this many px")
ap.add_argument("--court", type=int, default=30000, help="min area (px) of an open court (hole)")
ap.add_argument("--dark", type=int, default=65, help="max mean brightness of an open court")
ap.add_argument("--mode", default="line", choices=["line", "glow"])
ap.add_argument("--bright", type=int, default=140, help="glow mode: brightness of the outline")
ap.add_argument("--notch", type=int, default=9, help="glow mode: closes desk / console bites up to this many px")
ap.add_argument("--eps", type=float, default=2.5); ap.add_argument("--scale", type=int, default=2)
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)
src = cv2.imread(a.image)
if a.crop:
    ys, xs = a.crop.split(","); y0, y1 = map(int, ys.split(":")); x0, x1 = map(int, xs.split(":"))
    src = src[y0:y1, x0:x1]
else:   # drop the black letterbox of a phone screenshot
    rows = np.where(src.mean(axis=(1, 2)) > 12)[0]; cols = np.where(src.mean(axis=(0, 2)) > 12)[0]
    src = src[rows[0]:rows[-1] + 1, cols[0]:cols[-1] + 1]
cv2.imwrite(os.path.join(a.out, "source_crop.png"), src)
def glow_solid():
    v = cv2.cvtColor(src, cv2.COLOR_BGR2HSV)[:, :, 2]
    seal = cv2.dilate((v > a.bright).astype(np.uint8), np.ones((3, 3), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(1 - seal, 4)
    border = (set(lab[0, :]) | set(lab[-1, :]) | set(lab[:, 0]) | set(lab[:, -1])) - {0}
    inside = [i for i in range(1, n) if i not in border]
    if not inside: raise SystemExit("no enclosed floor: the outline is broken. Lower --bright.")
    solid = (~np.isin(lab, list(border))).astype(np.uint8)
    n2, l2, s2, _ = cv2.connectedComponentsWithStats(solid, 8)
    solid = (l2 == 1 + np.argmax(s2[1:, 4])).astype(np.uint8)
    floor = max(inside, key=lambda i: st[i, 4])
    courts = np.zeros_like(solid)
    for i in inside:
        if i != floor and st[i, 4] > a.court: courts[lab == i] = 1
    solid[cv2.dilate(courts, np.ones((3, 3), np.uint8)) > 0] = 0
    solid = cv2.morphologyEx(solid, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    return cv2.morphologyEx(solid, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_RECT, (a.notch, a.notch)))

def line_solid():
    hsv = cv2.cvtColor(src, cv2.COLOR_BGR2HSV); v = hsv[:, :, 2]; sat = hsv[:, :, 1]
    th = cv2.morphologyEx(v, cv2.MORPH_TOPHAT, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11)))
    line = ((th > a.line) & (sat > a.sat)).astype(np.uint8)
    text = ((v > 140) & (sat < a.sat)).astype(np.uint8)                     # labels, number circles
    line[cv2.dilate(text, np.ones((9, 9), np.uint8)) > 0] = 0
    line[np.where(line.mean(axis=1) > 0.6)[0]] = 0                           # phone UI bars
    seal = cv2.morphologyEx(line, cv2.MORPH_CLOSE, np.ones((a.seal, a.seal), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(1 - seal, 4)
    border = (set(lab[0, :]) | set(lab[-1, :]) | set(lab[:, 0]) | set(lab[:, -1])) - {0}
    solid = (~np.isin(lab, list(border))).astype(np.uint8)
    courts = np.zeros_like(solid)
    for i in range(1, n):
        if i not in border and st[i, 4] > a.court and v[lab == i].mean() < a.dark: courts[lab == i] = 1
    solid[cv2.dilate(courts, np.ones((5, 5), np.uint8)) > 0] = 0
    solid = cv2.morphologyEx(solid, cv2.MORPH_OPEN, np.ones((9, 9), np.uint8))
    n2, l2, s2, _ = cv2.connectedComponentsWithStats(solid, 8)
    solid = (l2 == 1 + np.argmax(s2[1:, 4])).astype(np.uint8)
    return solid

if a.mode == "glow":
    if a.court == 30000: a.court = 5000
    if a.eps == 2.5: a.eps = 2.2
    solid = glow_solid()
else: solid = line_solid()
cs, h = cv2.findContours(solid, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
s = a.scale
wl = np.zeros((solid.shape[0] * s, solid.shape[1] * s, 3), np.uint8)
ov = cv2.resize((src * 0.5).astype(np.uint8), None, fx=s, fy=s)
polys = []
for i, ct in enumerate(cs):
    if cv2.contourArea(ct) < 2000: continue
    p = cv2.approxPolyDP(ct, a.eps, True)
    polys.append({"hole": bool(h[0][i][3] >= 0), "pts": p.reshape(-1, 2).tolist()})
    cv2.polylines(wl, [p * s], True, (255, 255, 255), 3, cv2.LINE_AA)
    cv2.polylines(ov, [p * s], True, (80, 80, 255), 2, cv2.LINE_AA)
json.dump({"size_px": [int(solid.shape[1]), int(solid.shape[0])], "polys": polys}, open(os.path.join(a.out, "walls_px.json"), "w"))
cv2.imwrite(os.path.join(a.out, "walls_trace.png"), wl)
cv2.imwrite(os.path.join(a.out, "walls_overlay.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 88])
print("outline + %d holes, %d points" % (sum(p["hole"] for p in polys), sum(len(p["pts"]) for p in polys)))
