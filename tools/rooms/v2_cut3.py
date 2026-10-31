#!/usr/bin/env python3
"""Rooms V2, three-piece cut (owner, v11.8): cut a room's 360 strip into 3 pieces for the video generator, with the
cuts only where NOBODY stands (a person cut in two animates as two halves that don't match).

    <venv with opencv 4.10>/bin/python tools/rooms/v2_cut3.py <faction> <room>

Finds the people in art/rooms_v2/<f>/pano/<room>_360.png (YOLOv4-tiny, as evee_people.py), picks 3 cut columns clear
of everyone and as close to equal thirds as it can, and writes each piece (+ OV px overlap each side) into a 1920x1080
frame: the strip piece scaled to the full width, in the middle, with WHITE bands above and below for the generator to
extend (ceiling / floor) before it animates. Writes:

  art/rooms_v2/<f>/pieces3/v2_<f>_<room>_part1..3.png
  art/rooms_v2/<f>/pieces3/v2_<f>_<room>_cuts.json   (strip size, cuts, each piece's span and where it sits in the frame)
  art/rooms_v2/<f>/pieces3/v2_<f>_<room>_cuts_preview.jpg  (the strip with the people boxes and the cut lines)
"""
import json, os, sys
import cv2, numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FW, FH = 1920, 1080
OV = 40            # px of strip overlap each side of a cut (blended when the clips are joined)
CLEAR = 24         # px a cut keeps away from anyone's box
Data_SPAN = 0.07   # each cut may move this share of the strip from its equal third, to find a calm column
D = os.path.join(ROOT, "tools/rooms/.yolo")


def people(im):
    net = cv2.dnn.readNetFromDarknet(os.path.join(D, "yolov4-tiny.cfg"), os.path.join(D, "yolov4-tiny.weights"))
    ln = [net.getLayerNames()[i - 1] for i in net.getUnconnectedOutLayers().flatten()]
    H, W = im.shape[:2]
    out = []
    for x0 in range(0, W, H // 2):
        tile = im[:, x0:x0 + H] if x0 + H <= W else np.concatenate([im[:, x0:], im[:, :x0 + H - W]], axis=1)
        net.setInput(cv2.dnn.blobFromImage(tile, 1 / 255.0, (608, 608), swapRB=True, crop=False))
        for o in net.forward(ln):
            for d in o:
                sc = d[5:]; c = int(np.argmax(sc)); conf = float(sc[c]) * float(d[4])
                if c == 0 and conf > 0.2:
                    cx, w = d[0] * H, d[2] * H
                    out.append([(x0 + cx - w / 2) % W, w, d[1] * H - d[3] * H / 2, d[3] * H])
    return out


def main():
    f, room = sys.argv[1], sys.argv[2]
    pano = cv2.imread(os.path.join(ROOT, "art/rooms_v2", f, "pano", room + "_360.png"))
    H, W = pano.shape[:2]
    boxes = people(pano)
    busy = np.zeros(W, bool)
    for x, w, _, _ in boxes:
        for k in range(int(x) - CLEAR, int(x + w) + CLEAR + 1): busy[k % W] = True
    free = np.where(~busy)[0]
    if len(free) == 0: sys.exit("no clear column at all")
    # how busy each column is where people and creatures stand (the lower 2/3): edges there = someone or something
    g = cv2.cvtColor(pano, cv2.COLOR_BGR2GRAY).astype(np.float32)
    gx = np.abs(cv2.Sobel(g, cv2.CV_32F, 1, 0, ksize=3))[int(H * 0.33):int(H * 0.97)].mean(0)
    wrapped = np.concatenate([gx[-60:], gx, gx[:60]])
    energy = np.convolve(wrapped, np.ones(121) / 121.0, mode="same")[60:-60]
    energy = energy / max(1e-6, float(np.median(energy)))
    cost = np.where(busy, 1e9, energy)
    best = None
    span = int(W * Data_SPAN)
    for c0 in free[::3]:
        cs = [int(c0)]
        total = float(cost[c0])
        for k in (1, 2):
            lo = int(c0 + k * W / 3.0 - span); hi = int(c0 + k * W / 3.0 + span)
            idx = np.arange(lo, hi) % W
            j = idx[int(np.argmin(cost[idx]))]
            cs.append(int(j)); total += float(cost[j])
        cs = sorted(cs)
        widths = [cs[1] - cs[0], cs[2] - cs[1], W - cs[2] + cs[0]]
        score = total + 2.0 * (max(widths) - min(widths)) / W
        if best is None or score < best[0]: best = (score, cs, widths)
    _, cuts, widths = best
    out_dir = os.path.join(ROOT, "art/rooms_v2", f, "pieces3")
    os.makedirs(out_dir, exist_ok=True)
    wrap = np.concatenate([pano, pano, pano], axis=1)
    meta = {"strip": [W, H], "cuts": cuts, "overlap": OV, "frame": [FW, FH], "parts": []}
    for i in range(3):
        a = cuts[i] - OV
        b = (cuts[(i + 1) % 3] if i < 2 else cuts[0] + W) + OV
        piece = wrap[:, W + a:W + b]
        pw = b - a
        k = FW / pw
        ph = int(round(H * k))
        if ph > FH:   # (a narrow piece: fit the height instead, white at the sides)
            k = FH / H
            ph = FH
        pw2 = int(round(pw * k))
        frame = np.full((FH, FW, 3), 255, np.uint8)
        y0 = (FH - ph) // 2
        x0 = (FW - pw2) // 2
        frame[y0:y0 + ph, x0:x0 + pw2] = cv2.resize(piece, (pw2, ph), interpolation=cv2.INTER_LANCZOS4 if k > 1 else cv2.INTER_AREA)
        name = "v2_%s_%s_part%d.png" % (f, room, i + 1)
        cv2.imwrite(os.path.join(out_dir, name), frame)
        meta["parts"].append({"file": name, "strip_x0": a % W, "strip_w": pw, "frame_rect": [x0, y0, pw2, ph]})
    with open(os.path.join(out_dir, "v2_%s_%s_cuts.json" % (f, room)), "w") as o: json.dump(meta, o, indent=1)
    pv = pano.copy()
    for x, w, y, h in boxes:
        cv2.rectangle(pv, (int(x), int(y)), (int(x + w), int(y + h)), (0, 200, 255), 2)
    for c in cuts: cv2.line(pv, (c, 0), (c, H), (0, 0, 255), 4)
    cv2.imwrite(os.path.join(out_dir, "v2_%s_%s_cuts_preview.jpg" % (f, room)), cv2.resize(pv, (W // 2, H // 2)), [cv2.IMWRITE_JPEG_QUALITY, 85])
    print("%s %s: %d people, cuts %s, piece widths %s (frame fill %s)" % (f, room, len(boxes), cuts, widths, [p["frame_rect"][3] for p in meta["parts"]]))


if __name__ == "__main__":
    main()
