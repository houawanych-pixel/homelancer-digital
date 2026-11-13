#!/usr/bin/env python3
"""v13.115 (owner: "Orion and Liberator have no HoloDeck plan: compose the main deck inside the ship's silhouette from
the traced room library, following the class rules"): a ship with no HoloDeck sheet gets the MAIN DECK of the traced
ship of its class (class rules, docs/HANDOFF_SHIP_INTERIORS.md section 7: every ship of a class plays alike, the
faction changes the look), fitted inside ITS OWN silhouette: the fleet token (assets/fleet_tokens/<id>.png) is scaled
up behind the donor's plan until every room and corridor of the donor's main deck sits inside the token's hull, and
drawn as a cyan HoloDeck-style source.jpg so decklib.hull() reads it like the traced ships.

    from fleet_derive import derive
    ax, lifts = derive("orion_capital", "imperium_capital")   # writes tools/trace/fleet_orion_capital/source.jpg,
                                                               # eng/plan.json (+ plan_on_map.jpg)"""
import json, os, sys
import cv2, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapely.geometry import shape
import decklib

TR = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(TR))

def _token_source(tok, W, H, ax, top, height):
    """the token (RGBA) scaled to `height` px, its axis on `ax`, its nose at `top`, on a dark HoloDeck background,
    tinted cyan so the hull reads as glow"""
    im = cv2.imread(tok, cv2.IMREAD_UNCHANGED)
    a = im[:, :, 3]; ys, xs = np.where(a > 40)
    im = im[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    k = height / im.shape[0]
    im = cv2.resize(im, (max(1, int(round(im.shape[1] * k))), int(round(height))), interpolation=cv2.INTER_CUBIC)
    out = np.zeros((H, W, 3), np.uint8); out[:] = (40, 18, 6)
    x0 = int(round(ax - im.shape[1] / 2)); y0 = int(round(top))
    sx0, sy0 = max(0, -x0), max(0, -y0); x0c, y0c = max(0, x0), max(0, y0)
    w = min(im.shape[1] - sx0, W - x0c); h = min(im.shape[0] - sy0, H - y0c)
    if w <= 0 or h <= 0: return out
    piece = im[sy0:sy0 + h, sx0:sx0 + w].astype(np.float32)
    al = (piece[:, :, 3:4] / 255.0)
    rgb = piece[:, :, :3] * 0.55 + np.array([255, 200, 40], np.float32) * 0.45      # BGR: a cyan glow over the art
    hsv = cv2.cvtColor(np.clip(rgb, 0, 255).astype(np.uint8), cv2.COLOR_BGR2HSV); hsv[:, :, 1] = np.maximum(hsv[:, :, 1], 110)
    hsv[:, :, 2] = np.maximum(hsv[:, :, 2], 110); rgb = cv2.cvtColor(hsv, cv2.COLOR_HSV2BGR).astype(np.float32)
    base = out[y0c:y0c + h, x0c:x0c + w].astype(np.float32)
    out[y0c:y0c + h, x0c:x0c + w] = (base * (1 - al) + rgb * al).astype(np.uint8)
    return out

def derive(target, donor):
    dd = os.path.join(TR, "fleet_" + donor); td = os.path.join(TR, "fleet_" + target)
    os.makedirs(os.path.join(td, "eng"), exist_ok=True)
    P = json.load(open(os.path.join(dd, "eng", "plan.json")))
    ax = float(P["mirror_x"]); src_d = os.path.join(dd, "source.jpg")
    H, W = cv2.imread(src_d).shape[:2]
    hd = decklib.hull(src_d, ax)
    body = shape(P["floor"]).buffer(decklib.T * 2)
    x0, y0, x1, y1 = hd.bounds
    tok = os.path.join(ROOT, "assets", "fleet_tokens", target + ".png")
    out = os.path.join(td, "source.jpg")
    for k in [1.0 + 0.04 * i for i in range(40)]:
        height = (y1 - y0) * k; top = (y0 + y1) / 2 - height / 2
        top = min(top, body.bounds[1] - 30); height = max(height, body.bounds[3] + 40 - top)
        img = _token_source(tok, W, H, ax, top, height)
        cv2.imwrite(out, img, [cv2.IMWRITE_JPEG_QUALITY, 92])
        hp = decklib.hull(out, ax)
        if hp.buffer(-decklib.T).contains(body.buffer(-decklib.T * 2)):
            break
    else:
        print("  WARNING: the donor's main deck does not fit inside the token hull even at %.2fx" % k)
    Q = dict(P); Q["ship"] = target; Q["derived_from"] = donor
    Q["note"] = "PROPOSED main deck: the traced %s main deck (same class) inside this ship's own silhouette (fleet token)" % donor
    json.dump(Q, open(os.path.join(td, "eng", "plan.json"), "w"))
    # the main deck on its new hull (white walls, red hull) for the owner
    im = img.copy() // 3
    hp = decklib.hull(out, ax)
    cv2.polylines(im, [np.array(hp.exterior.coords, np.int32)], True, (60, 60, 230), 3)
    fl = shape(P["floor"]); wl = shape(P["walls"])
    for g in getattr(fl, "geoms", [fl]): cv2.fillPoly(im, [np.array(g.exterior.coords, np.int32)], (90, 40, 10))
    for g in getattr(wl, "geoms", [wl]): cv2.fillPoly(im, [np.array(g.exterior.coords, np.int32)], (255, 255, 255))
    for nm, g in P["rooms"].items():
        c = shape(g).centroid; t = nm.upper()[:18]
        (tw, th), _ = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, 0.4, 1)
        cv2.putText(im, t, (int(c.x - tw / 2), int(c.y)), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 220, 120), 1, cv2.LINE_AA)
    cv2.putText(im, "%s MAIN DECK (PROPOSED: the traced %s deck in this ship's silhouette)" % (target.upper(), donor.upper()), (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1, cv2.LINE_AA)
    cv2.imwrite(os.path.join(td, "eng", "plan_on_map.jpg"), im, [cv2.IMWRITE_JPEG_QUALITY, 85])
    lifts = {k: [round(v) for v in shape(g).centroid.coords[0]] for k, g in P["rooms"].items() if "ift" in k}
    print(target, "<-", donor, "token scale %.2f" % k, "lifts", lifts)
    return ax, lifts
