#!/usr/bin/env python3
"""v13.85 (owner: 3 clips a room; every picture edge is a real seam in a wide clear gap between people, never through a
person or a ship; no padding): cut a location room's 360 strip into 6 pieces, stacked two to a picture (3 pictures =
3 clips, each narrower than 16:9). The two pieces in one picture share a width, so the cuts are chosen in equal pairs:
s1=s2, s3=s4, s5=s6 (within TOL px). Every cut keeps CLEAR px from anyone the detector finds and from --avoid ranges
(people it missed, ships). Picture edges are the cuts themselves (no overlap, no padding).

    /tmp/cv410/bin/python tools/rooms/loc_cut_pairs.py <sys> <Place> <Room> <out_dir> [--clear 40] [--avoid a-b,c-d]
then: python3 tools/rooms/loc_pack_rows.py <sys> <Place> <Room> <out_dir>"""
import json, os, sys
import cv2, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import v2_cut3
ROOT = os.path.dirname(os.path.dirname(HERE))
TOL = 8

def main():
    args = sys.argv[1:]; clear = 40; avoid = []
    if "--clear" in args: i = args.index("--clear"); clear = int(args[i + 1]); del args[i:i + 2]
    if "--avoid" in args:
        i = args.index("--avoid"); avoid = [tuple(int(v) for v in r.split("-")) for r in args[i + 1].split(",")]; del args[i:i + 2]
    sy, place, room, out_dir = args[:4]
    src = os.path.join(ROOT, "assets/rooms/loc", "%s_%s_%s.jpg" % (sy, place.lower(), room.lower()))
    pano = cv2.imread(src); H, W = pano.shape[:2]
    boxes = v2_cut3.people(pano)
    busy = np.zeros(W, bool)
    for x, w, _, _ in boxes:
        for k in range(int(x) - clear, int(x + w) + clear + 1): busy[k % W] = True
    for a, b in avoid:
        for k in range(a - clear, b + clear + 1): busy[k % W] = True
    g = cv2.cvtColor(pano, cv2.COLOR_BGR2GRAY).astype(np.float32)
    gx = np.abs(cv2.Sobel(g, cv2.CV_32F, 1, 0, ksize=3))[int(H * 0.33):int(H * 0.97)].mean(0)
    e = np.convolve(np.concatenate([gx[-60:], gx, gx[:60]]), np.ones(121) / 121.0, mode="same")[60:-60]
    e = e / max(1e-6, float(np.median(e)))
    # distance from every column to the nearest person / avoided thing (circular)
    occ = np.zeros(W, bool)
    for x, w, _, _ in boxes: occ[np.arange(int(x), int(x + w) + 1) % W] = True
    for a0, b0 in avoid: occ[np.arange(a0, b0 + 1) % W] = True
    idx = np.where(occ)[0]
    cols = np.arange(W)
    dd = np.abs(cols[:, None] - idx[None, :]); dist = np.minimum(dd, W - dd).min(1)
    # want the widest gaps: cost falls as the gap grows (to 150 px), a little extra for busy texture
    cost = np.where(dist < clear, 1e6, 150 - np.minimum(dist, 150)) + 5 * e
    MINW, MAXW = int(os.environ.get("HL_MINW", 520)), int(os.environ.get("HL_MAXW", 860))
    best = None
    for c0 in np.argsort(cost)[:200]:
        c0 = int(c0)
        cc = cost[(c0 + np.arange(W + 1)) % W]
        d = np.full(W + 1, np.inf); d[0] = 0.0; back = []
        for k in range(5):
            nd = np.full(W + 1, np.inf); bk = np.zeros(W + 1, int)
            for x in range(MINW, W + 1, 2):
                j0, j1 = max(0, x - MAXW), x - MINW
                seg = d[j0:j1 + 1]; jj = int(np.argmin(seg))
                nd[x] = seg[jj] + cc[x]; bk[x] = j0 + jj
            d = nd; back.append(bk)
        ok = [x for x in range(W - MAXW, W - MINW + 1) if np.isfinite(d[x])]
        if not ok: continue
        x = min(ok, key=lambda v: d[v]); tot = d[x] + cost[c0]
        if best is None or tot < best[0]:
            path = [x]
            for bk in reversed(back[1:]): path.append(int(bk[path[-1]]))
            best = (float(tot), [c0] + [c0 + q for q in sorted(path)])
    cu = best[1]
    gaps = [int(dist[c % W]) for c in cu]
    if min(gaps) < clear: print("WARNING: a cut is within %d px of someone" % min(gaps))
    cuts = [c % W for c in cu]
    os.makedirs(out_dir, exist_ok=True)
    meta = {"src": src.replace(ROOT + "/", ""), "strip": [W, H], "cuts": cuts, "overlap": 0, "clear": clear, "avoid": avoid,
            "people": len(boxes), "method": "loc_cut_pairs (6 pieces, equal pairs, stacked 3 pictures)"}
    os.makedirs(os.path.join(HERE, "loc_cuts"), exist_ok=True)
    meta["gaps"] = gaps
    json.dump(meta, open(os.path.join(HERE, "loc_cuts", "%s_%s_%s.json" % (sy, place.lower(), room.lower())), "w"), indent=1)
    pv = pano.copy()
    for x, w, y, h in boxes: cv2.rectangle(pv, (int(x), int(y)), (int(x + w), int(y + h)), (0, 200, 255), 2)
    for a, b in avoid: cv2.rectangle(pv, (a, 2), (b, H - 2), (255, 0, 255), 2)
    for i, c in enumerate(cuts):
        cv2.line(pv, (c, 0), (c, H), (0, 0, 255), 5); cv2.putText(pv, str(i + 1), (c + 8, 40), 0, 1.2, (255, 255, 255), 3)
    cv2.imwrite(os.path.join(out_dir, "%s_%s_cuts_preview.jpg" % (place, room)), pv, [cv2.IMWRITE_JPEG_QUALITY, 85])
    sp = [(cu[(i + 1) % 6] if i < 5 else cu[0] + W) - cu[i] for i in range(6)]
    print("%s %s: cuts %s spans %s gap to nearest person %s" % (place, room, cuts, sp, gaps)); meta["gaps"] = gaps

main()
