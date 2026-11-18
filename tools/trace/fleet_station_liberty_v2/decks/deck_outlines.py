#!/usr/bin/env python3
"""The other four Liberty Hub decks' outlines in the main deck's frame (source.jpg, 3300 px): each deck is the station
model's own slice at its height (station_plans: the side view cut into five decks), moved onto the main deck by the
fit of the model's MAIN HUB slice to the owner's map (best of 8 turns / flips, then scale and shift by area and
centre). Writes decks/outlines.json and decks/outlines.jpg."""
import json, os, sys
import cv2, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); TR = os.path.join(HERE, "..", "..")
sys.path.insert(0, TR)
import station_plans as SP
from shapely.geometry import shape, mapping, Polygon
from shapely import affinity
MAIN = shape(json.load(open(os.path.join(HERE, "..", "hull.json")))["hull"])
O = SP.deck_outlines({"model": "st3d_veranthos_customs"})
names = ["HANGAR", "ENGINEERING", "MAIN HUB", "HABITAT", "COMMAND"]
polys = []
for k, i in enumerate(O["idx"]):
    p = SP.outline(SP.clean(O["masks"][i]))
    polys.append(p)
def fit(g, rot, flip):
    h = affinity.rotate(g, rot, origin="centroid")
    if flip: h = affinity.scale(h, -1, 1, origin="centroid")
    return h
best = None
for rot in (0, 90, 180, 270):
    for flip in (False, True):
        h = fit(polys[2], rot, flip)
        k = (MAIN.area / h.area) ** 0.5
        h = affinity.scale(h, k, k, origin="centroid")
        h = affinity.translate(h, MAIN.centroid.x - h.centroid.x, MAIN.centroid.y - h.centroid.y)
        iou = h.intersection(MAIN).area / h.union(MAIN).area
        if best is None or iou > best[0]: best = (iou, rot, flip, k, h.centroid)
iou, rot, flip, k, _ = best
print("fit: iou %.2f rot %d flip %s scale %.2f" % (iou, rot, flip, k))
c0 = polys[2].centroid
def place(g):
    h = affinity.rotate(g, rot, origin=c0)
    if flip: h = affinity.scale(h, -1, 1, origin=c0)
    h = affinity.scale(h, k, k, origin=c0)
    return affinity.translate(h, MAIN.centroid.x - c0.x, MAIN.centroid.y - c0.y)
out = {}
im = cv2.imread(os.path.join(HERE, "..", "source.jpg")); im = (im * 0.4).astype(np.uint8)
cols = [(0, 200, 255), (0, 120, 255), (255, 255, 255), (255, 150, 30), (200, 80, 255)]
for n, p, c in zip(names, polys, cols):
    g = place(p).buffer(0)
    # mirror-true about the main deck's axis (the bigger half mirrored)
    ax = 1650.0
    L = g.intersection(Polygon([(0, 0), (ax, 0), (ax, 3300), (0, 3300)]))
    Rr = g.intersection(Polygon([(ax, 0), (3300, 0), (3300, 3300), (ax, 3300)]))
    half = L if L.area >= Rr.area else affinity.scale(Rr, -1, 1, origin=(ax, 0))
    g = half.union(affinity.scale(half, -1, 1, origin=(ax, 0))).buffer(1).buffer(-1)
    if g.geom_type != "Polygon": g = max(g.geoms, key=lambda q: q.area)
    out[n] = mapping(g)
    cv2.polylines(im, [np.array(g.exterior.coords, np.int32)], True, c, 6, cv2.LINE_AA)
json.dump(out, open(os.path.join(HERE, "outlines.json"), "w"))
cv2.imwrite(os.path.join(HERE, "outlines.jpg"), cv2.resize(im, (1100, 1100)), [cv2.IMWRITE_JPEG_QUALITY, 85])
