#!/usr/bin/env python3
"""v13.78 (owner: "give me those panorama pictures cut in good places, where people won't cross the seams ... cut where
the pillars are, or where there's a big empty space"): the three-piece cut (v2_cut3.py's method) for a LOCATION room
(the game's own 360 still, assets/rooms/loc/<sys>_<place>_<room>.jpg). People are found (YOLOv4-tiny) and the 3 cuts go in the calmest columns clear of everyone
(pillars, walls, empty floor). Each piece (+40 px overlap each side) sits in a 1920x1080 frame, white bands above and
below for the video generator to extend before it animates.

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
    cuts = manual if manual else best[1]
    hit = [c for c in cuts if busy[c % W]]
    os.makedirs(out_dir, exist_ok=True)
    FW, FH, OV = v2_cut3.FW, v2_cut3.FH, v2_cut3.OV
    wrap = np.concatenate([pano, pano, pano], axis=1)
    meta = {"src": src.replace(ROOT + "/", ""), "strip": [W, H], "cuts": cuts, "overlap": OV, "frame": [FW, FH], "parts": [], "people": len(boxes), "cuts_touching_people": hit}
    for i in range(3):
        a = cuts[i] - OV
        b = (cuts[(i + 1) % 3] if i < 2 else cuts[0] + W) + OV
        piece = wrap[:, W + a:W + b]
        pw = b - a
        k = FW / pw
        ph = int(round(H * k))
        if ph > FH: k = FH / H; ph = FH
        pw2 = int(round(pw * k))
        frame = np.full((FH, FW, 3), 255, np.uint8)
        y0 = (FH - ph) // 2; x0 = (FW - pw2) // 2
        frame[y0:y0 + ph, x0:x0 + pw2] = cv2.resize(piece, (pw2, ph), interpolation=cv2.INTER_LANCZOS4 if k > 1 else cv2.INTER_AREA)
        name = "%s_%s_part%d.png" % (place, room, i + 1)
        cv2.imwrite(os.path.join(out_dir, name), frame)
        meta["parts"].append({"file": name, "strip_x0": a % W, "strip_w": pw, "frame_rect": [x0, y0, pw2, ph]})
    os.makedirs(os.path.join(HERE, "loc_cuts"), exist_ok=True)
    with open(os.path.join(HERE, "loc_cuts", "%s_%s_%s.json" % (sy, place.lower(), room.lower())), "w") as o: json.dump(meta, o, indent=1)
    pv = pano.copy()
    for x, w, y, h in boxes: cv2.rectangle(pv, (int(x), int(y)), (int(x + w), int(y + h)), (0, 200, 255), 2)
    for c in cuts: cv2.line(pv, (c, 0), (c, H), (0, 0, 255), 5)
    cv2.imwrite(os.path.join(out_dir, "%s_%s_cuts_preview.jpg" % (place, room)), pv, [cv2.IMWRITE_JPEG_QUALITY, 85])
    print("%s %s: %d people, cuts %s, widths %s, touching people: %s" % (place, room, len(boxes), cuts, [p["strip_w"] for p in meta["parts"]], hit))

if __name__ == "__main__":
    main()
