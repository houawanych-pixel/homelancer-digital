#!/usr/bin/env python3
"""v13.78 (owner: "give me those panorama pictures cut in good places, where people won't cross the seams ... cut where
the pillars are, or where there's a big empty space"): the three-piece cut (v2_cut3.py's method) for a LOCATION room
(the game's own 360 still, assets/rooms/loc/<sys>_<place>_<room>.jpg). People are found (YOLOv4-tiny) and the 3 cuts go in the calmest columns clear of everyone
(pillars, walls, empty floor). v13.79: each third is split again so every piece is a full 16:9 window (no white bands);
run loc_upscale.py on out_dir afterwards for 1920x1080 frames. --cuts may list extra seams; --avoid x0-x1 marks
people the detector missed.

    python3 tools/rooms/loc_cut3.py <sys> <Place> <Room> <out_dir> [--span 0.15] [--cuts x1,x2,x3]

Writes <out_dir>/<Place>_<Room>_part1..3.png and _cuts_preview.jpg, and tools/rooms/loc_cuts/<sys>_<place>_<room>.json
(the cuts, to join the animated parts back later)."""
import json, os, sys
import cv2, numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import v2_cut3
ROOT = os.path.dirname(os.path.dirname(HERE))

def main():
    args = sys.argv[1:]
    manual = None
    if "--span" in args:
        i = args.index("--span"); v2_cut3.Data_SPAN = float(args[i + 1]); del args[i:i + 2]
    avoid = []
    if "--avoid" in args:   # x0-x1,x0-x1: people the detector missed (e.g. the seated wolf man)
        i = args.index("--avoid"); avoid = [tuple(int(v) for v in r.split("-")) for r in args[i + 1].split(",")]; del args[i:i + 2]
    if "--clear" in args:   # px a cut keeps from anyone's box (crowded rooms need less)
        i = args.index("--clear"); v2_cut3.CLEAR = int(args[i + 1]); del args[i:i + 2]
    if "--ov" in args:   # overlap px each side (smaller = fewer pieces at 16:9)
        i = args.index("--ov"); v2_cut3.OV = int(args[i + 1]); del args[i:i + 2]
    if "--cuts" in args:
        i = args.index("--cuts"); manual = sorted(int(v) for v in args[i + 1].split(",")); del args[i:i + 2]
    sy, place, room, out_dir = args[:4]
    src = os.path.join(ROOT, "assets/rooms/loc", "%s_%s_%s.jpg" % (sy, place.lower(), room.lower()))   # the game's own 360 still (what you see)
    pano = cv2.imread(src)
    H, W = pano.shape[:2]
    boxes = v2_cut3.people(pano)
    busy = np.zeros(W, bool)
    for x, w, _, _ in boxes:
        for k in range(int(x) - v2_cut3.CLEAR, int(x + w) + v2_cut3.CLEAR + 1): busy[k % W] = True
    for x0, x1 in avoid:
        for k in range(x0 - v2_cut3.CLEAR, x1 + v2_cut3.CLEAR + 1): busy[k % W] = True
    g = cv2.cvtColor(pano, cv2.COLOR_BGR2GRAY).astype(np.float32)
    gx = np.abs(cv2.Sobel(g, cv2.CV_32F, 1, 0, ksize=3))[int(H * 0.33):int(H * 0.97)].mean(0)
    wrapped = np.concatenate([gx[-60:], gx, gx[:60]])
    energy = np.convolve(wrapped, np.ones(121) / 121.0, mode="same")[60:-60]
    energy = energy / max(1e-6, float(np.median(energy)))
    cost = np.where(busy, 1e9, energy)
    free = np.where(~busy)[0]
    best = None
    span = int(W * v2_cut3.Data_SPAN)
    for c0 in free[::3]:
        cs = [int(c0)]; total = float(cost[c0])
        for k in (1, 2):
            idx = np.arange(int(c0 + k * W / 3.0 - span), int(c0 + k * W / 3.0 + span)) % W
            j = idx[int(np.argmin(cost[idx]))]
            cs.append(int(j)); total += float(cost[j])
        cs = sorted(cs)
        widths = [cs[1] - cs[0], cs[2] - cs[1], W - cs[2] + cs[0]]
        score = total + 2.0 * (max(widths) - min(widths)) / W
        if best is None or score < best[0]: best = (score, cs, widths)
    seams = manual if manual else best[1]          # the main seams (owner-checked)
    if "--fewest" in sys.argv:
        # v13.82 (owner: the generator takes 16:9 or narrower, never wider; keep the cuts few): the fewest pieces that each
        # fit one 16:9 window, the cuts placed anywhere round the circle at the calmest people-free columns.
        WIN0 = int(round(H * 16 / 9.0)); KEEP0 = WIN0 - 2 * v2_cut3.OV
        n0 = -(-W // KEEP0); lo = KEEP0 // 2
        c = np.minimum(cost, 1e6)
        for n in (n0, n0 + 1, n0 + 2):     # one more piece only if the fewest would cut through someone
          lo = min(KEEP0 // 2, W // n - 40)
          bestf = None
          for a in np.argsort(c)[:300]:
              a = int(a); L = W
              d = np.full(L + 1, np.inf); d[0] = 0.0; back = []
              cc = np.array([c[(a + x) % W] for x in range(L + 1)])
              for k in range(n - 1):
                  nd = np.full(L + 1, np.inf); bk = np.zeros(L + 1, int)
                  for x in range(lo, L + 1):
                      j0, j1 = max(0, x - KEEP0), x - lo
                      seg = d[j0:j1 + 1]; jj = int(np.argmin(seg))
                      nd[x] = seg[jj] + cc[x]; bk[x] = j0 + jj
                  d = nd; back.append(bk)
              ok = [x for x in range(L - KEEP0, L - lo + 1) if np.isfinite(d[x])]
              if not ok: continue
              x = min(ok, key=lambda v: d[v]); tot = d[x] + c[a]
              if bestf is None or tot < bestf[0]:
                  path = [x]
                  for bk in reversed(back[1:]): path.append(int(bk[path[-1]]))
                  bestf = (tot, sorted(a + q for q in path) + [a])
          if bestf and bestf[0] < 1e6: break
        seams = sorted(v % W for v in bestf[1])
        print("fewest:", n, "pieces, cost", round(float(bestf[0]), 1))
    # v13.79 (owner: "make sure I don't have any white space ... it may alter the render"): no white bands. Every piece is
    # a full 16:9 window of the strip (WIN px wide at the strip's full height), so each main third is split again at the
    # calmest people-free columns until every kept span fits inside one window; the window's extra width either side is
    # context that the join throws away.
    WIN = int(round(H * 16 / 9.0)); OV = v2_cut3.OV; KEEP = WIN - 2 * OV
    cuts = []
    FILL = "--fill" in args or "--fill" in sys.argv
    for i in range(len(seams)):
        if FILL: cuts.append(seams[i]); continue
        a = seams[i]; b = seams[i + 1] if i < len(seams) - 1 else seams[0] + W
        n = -(-(b - a) // KEEP)
        cuts.append(a)
        if n > 1:   # DP: n-1 inner cuts, every span in [KEEP*0.45, KEEP], least summed cost
            lo = int(KEEP * 0.5)
            pos = list(range(a + lo, b - lo + 1))
            prev = {a: (0.0, [])}
            for k in range(n - 1):
                cur = {}
                for x in pos:
                    best_v = None
                    for px, (v, path) in prev.items():
                        if lo <= x - px <= KEEP and (k < n - 2 or lo <= b - x <= KEEP):
                            if best_v is None or v < best_v[0]: best_v = (v, path)
                    if best_v: cur[x] = (best_v[0] + float(cost[x % W]), best_v[1] + [x])
                prev = cur
            cuts += min(prev.values())[1]
    cuts_u = cuts                          # unwrapped, increasing from seams[0]
    cuts = [c % W for c in cuts_u]
    hit = [c for c in cuts if busy[c % W]]
    os.makedirs(out_dir, exist_ok=True)
    FW, FH = v2_cut3.FW, v2_cut3.FH
    wrap = np.concatenate([pano, pano, pano], axis=1)
    meta = {"src": src.replace(ROOT + "/", ""), "strip": [W, H], "seams": seams, "cuts": cuts, "overlap": OV, "frame": [FW, FH], "window": WIN, "parts": [], "people": len(boxes), "cuts_touching_people": hit}
    N = len(cuts)
    for i in range(N if FILL else 0):
        # v13.80 (owner: "we can't have too many cuts ... they gotta be 16:9 landscape"): keep the 3 seams; each piece
        # (+OV each side) fills the frame's width and the bands above and below are the picture itself mirrored and
        # blurred out (ceiling up, floor down), so there is no white and the frame is 16:9. The join keeps only frame_rect.
        a = cuts_u[i] - OV; b = (cuts_u[i + 1] if i < N - 1 else cuts_u[0] + W) + OV
        piece = wrap[:, W + a:W + b]; pw = b - a
        fh = int(round(pw * 9 / 16.0)); t = (fh - H) // 2; bt = fh - H - t
        frame = np.zeros((fh, pw, 3), np.uint8); frame[t:t + H] = piece
        def band(src, n):            # src rows nearest the edge first
            rows = np.concatenate([src] * (n // len(src) + 1))[:n].astype(np.float32)
            out = rows.copy()
            for k, sig in enumerate((6, 18, 40)):
                bl = cv2.GaussianBlur(rows, (0, 0), sig)
                w = np.clip((np.arange(n) / max(1, n - 1)) * 3 - k, 0, 1)[:, None, None]
                out = out * (1 - w) + bl * w
            fade = (1 - 0.25 * np.arange(n) / max(1, n - 1))[:, None, None]
            return np.clip(out * fade, 0, 255).astype(np.uint8)
        frame[:t] = band(piece, t)[::-1]              # mirror of the ceiling, upwards
        frame[t + H:] = band(piece[::-1], bt)         # mirror of the floor, downwards
        name = "%s_%s_part%d.png" % (place, room, i + 1)
        cv2.imwrite(os.path.join(out_dir, name), frame)   # native; loc_upscale.py brings it to 1920x1080
        k = FW / float(pw)
        meta["parts"].append({"file": name, "strip_x0": a % W, "strip_w": pw, "keep": [cuts_u[i] % W, pw - 2 * OV], "frame_rect": [0, int(round(t * k)), FW, int(round(H * k))]})
    for i in range(0 if FILL else N):
        a = cuts_u[i]; b = cuts_u[i + 1] if i < N - 1 else cuts_u[0] + W
        w0 = (a + b) // 2 - WIN // 2          # window centred on the kept span
        piece = wrap[:, W + w0:W + w0 + WIN]
        name = "%s_%s_part%d.png" % (place, room, i + 1)
        cv2.imwrite(os.path.join(out_dir, name), piece)   # native; upscale_parts() brings it to 1920x1080
        meta["parts"].append({"file": name, "strip_x0": w0 % W, "strip_w": WIN, "keep": [a % W, b - a], "frame_rect": [0, 0, FW, FH]})
    os.makedirs(os.path.join(HERE, "loc_cuts"), exist_ok=True)
    with open(os.path.join(HERE, "loc_cuts", "%s_%s_%s.json" % (sy, place.lower(), room.lower())), "w") as o: json.dump(meta, o, indent=1)
    pv = pano.copy()
    for x, w, y, h in boxes: cv2.rectangle(pv, (int(x), int(y)), (int(x + w), int(y + h)), (0, 200, 255), 2)
    for c in cuts: cv2.line(pv, (c, 0), (c, H), (0, 0, 255) if c in seams[:3] else (255, 120, 0), 5)
    for i, c in enumerate(cuts): cv2.putText(pv, str(i + 1), (c + 8, 40), 0, 1.2, (255, 255, 255), 3)
    cv2.imwrite(os.path.join(out_dir, "%s_%s_cuts_preview.jpg" % (place, room)), pv, [cv2.IMWRITE_JPEG_QUALITY, 85])
    print("%s %s: %d people, cuts %s, spans %s, touching people: %s" % (place, room, len(boxes), cuts, [p["keep"][1] for p in meta["parts"]], hit))

if __name__ == "__main__":
    main()
