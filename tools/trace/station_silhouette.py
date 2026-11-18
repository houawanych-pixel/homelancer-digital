#!/usr/bin/env python3
"""STEP 1 of the deck formula for a station (owner, Nov 17 2026: "trace the silhouette from the GLB ... separation
lines for the floors from a side view ... more accuracy where the intersections are ... clean lines and mirror it:
it's a Tripo silhouette, not clean"):

  the GLB cut into 96 thin horizontal slices (station_plans.slices); the floor heights are put INSIDE the station's
  solid body (where the side view has hull all the way across: never in the thin spikes under it); each floor's
  outline is its slice, mirrored about the station's middle line (left = right), small bumps closed, then redrawn
  with straight edges snapped to 0 / 45 / 90 degrees.
Writes tools/trace/stations/<model>/silhouettes.json (each floor's height and outline, px; N px across the model)
and silhouettes.jpg (side view with the floor lines + the five top views).   usage: python3 -I station_silhouette.py <model>"""
import json, math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np, cv2
from shapely.geometry import Polygon, MultiPolygon, mapping
import station_plans as SP

SP.NB = 96
N = SP.N
NAMES = ["HANGAR", "ENGINEERING", "MAIN HUB", "HABITAT", "COMMAND"]


def mirror_mask(m, ax):
    f = np.zeros_like(m)
    for x in range(N):
        x2 = int(round(2 * ax - x))
        if 0 <= x2 < N: f[:, x] = m[:, x2]
    return np.maximum(m, f)


def snap45(poly, eps):
    """straight edges at 0 / 45 / 90 degrees: simplify, then rebuild each edge on its nearest 45-degree direction
    (the closing error spread over the edges)"""
    p = poly.simplify(eps, preserve_topology=True)
    pts = list(p.exterior.coords)[:-1]
    if len(pts) < 4: return p
    vec = []
    for i in range(len(pts)):
        (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % len(pts)]
        L = math.hypot(x1 - x0, y1 - y0)
        a = round(math.atan2(y1 - y0, x1 - x0) / (math.pi / 4)) * (math.pi / 4)
        vec.append([math.cos(a) * L, math.sin(a) * L])
    vec = np.array(vec)
    err = vec.sum(0)
    w = np.linalg.norm(vec, axis=1); w = w / w.sum()
    vec -= np.outer(w, err)
    q = [pts[0]]
    for v in vec[:-1]: q.append((q[-1][0] + v[0], q[-1][1] + v[1]))
    out = Polygon(q).buffer(0)
    if isinstance(out, MultiPolygon): out = max(out.geoms, key=lambda g: g.area)
    return out if out.area > 0.6 * poly.area else p


def build(model):
    S = json.load(open(os.path.join(SP.OUT, "stations.json")))
    st = next(s for s in S if s["model"] == model)
    path = os.path.join(SP.REPO, "assets", "stations3d", model + ".glb")
    masks, top, side, (lo, hi, ss, d, upright) = SP.slices(path)
    H = hi[d] - lo[d]
    ax = N / 2.0
    # the side view's width at each slice height: the floors go where the hull runs (nearly) all the way across
    hrow = lambda i: int(N / 2 - ((lo[d] + (i + 0.5) / SP.NB * H) - (lo[d] + hi[d]) / 2) / ss * (N - 40))
    wid = np.array([float((side[min(N - 1, max(0, hrow(i)))] > 0).sum()) for i in range(SP.NB)])
    area = np.array([float((m > 0).sum()) for m in masks])
    body = np.where((wid >= 0.55 * wid.max()) & (area >= 0.35 * area.max()))[0]
    lo_i, hi_i = int(body.min()), int(body.max())
    idx = [int(round(lo_i + (hi_i - lo_i) * k / 4)) for k in range(5)]
    floors = []
    for k, i in enumerate(idx):
        m = mirror_mask(SP.clean(masks[i]), ax)
        m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (21, 21)))
        poly = SP.outline(m)
        clean = snap45(poly, 6.0)
        floors.append({"name": NAMES[k], "slice": i, "row": hrow(i), "outline": mapping(clean), "area_px": round(clean.area)})
    out = os.path.join(SP.OUT, model)
    os.makedirs(out, exist_ok=True)
    json.dump({"model": model, "N": N, "axis_x": ax, "floors": floors, "body_slices": [lo_i, hi_i]}, open(os.path.join(out, "silhouettes.json"), "w"))
    # the sheet
    sv = np.zeros((N, N, 3), np.uint8); sv[:] = (40, 18, 6)
    sv[side > 0] = (150, 110, 60)
    for f in floors:
        cv2.line(sv, (0, f["row"]), (N, f["row"]), (0, 215, 255), 2)
        cv2.putText(sv, f["name"], (8, f["row"] - 5), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 230, 255), 2, cv2.LINE_AA)
    # zoomed on the floors (the body is a thin disc between the towers and the spikes under it)
    r0 = max(0, min(f["row"] for f in floors) - 70); r1 = min(N, max(f["row"] for f in floors) + 70)
    band = side[r0:r1]
    sv = np.zeros((r1 - r0, N, 3), np.uint8); sv[:] = (40, 18, 6); sv[band > 0] = (150, 110, 60)
    zk = N / float(r1 - r0)
    sv = cv2.resize(sv, (N, N), interpolation=cv2.INTER_NEAREST)
    for f in floors:
        y = int((f["row"] - r0) * zk)
        cv2.line(sv, (0, y), (N, y), (0, 215, 255), 2)
        cv2.putText(sv, f["name"], (8, y - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 230, 255), 2, cv2.LINE_AA)
    cv2.putText(sv, "SIDE VIEW (zoomed in up/down %.1fx): floor lines" % zk, (8, 26), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2, cv2.LINE_AA)
    tiles = [sv]
    from shapely.geometry import shape
    for k, f in enumerate(floors):
        t = np.zeros((N, N, 3), np.uint8); t[:] = (40, 18, 6)
        raw = SP.outline(SP.clean(masks[f["slice"]]))
        if raw is not None: cv2.polylines(t, [np.round(np.array(raw.exterior.coords)).astype(np.int32)], True, (90, 70, 60), 1, cv2.LINE_AA)
        g = shape(f["outline"])
        cv2.fillPoly(t, [np.round(np.array(g.exterior.coords)).astype(np.int32)], (110, 70, 30))
        cv2.polylines(t, [np.round(np.array(g.exterior.coords)).astype(np.int32)], True, (255, 245, 225), 2, cv2.LINE_AA)
        cv2.line(t, (int(ax), 40), (int(ax), N - 10), (60, 60, 160), 1)
        cv2.putText(t, "%d  %s  (top view)" % (k + 1, f["name"]), (8, 26), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (255, 255, 255), 2, cv2.LINE_AA)
        tiles.append(t)
    sheet = np.vstack([np.hstack(tiles[:3]), np.hstack(tiles[3:])])
    cv2.imwrite(os.path.join(out, "silhouettes.jpg"), cv2.resize(sheet, None, fx=0.75, fy=0.75), [cv2.IMWRITE_JPEG_QUALITY, 85])
    print(model, "body slices", lo_i, hi_i, "floors at", idx)


if __name__ == "__main__":
    for m in sys.argv[1:]: build(m)
