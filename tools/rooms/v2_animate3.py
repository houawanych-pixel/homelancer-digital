#!/usr/bin/env python3
"""Rooms V2, three-piece join (owner, v11.8): join a room's 3 animated parts back into one moving 360 room.

    python3 tools/rooms/v2_animate3.py <faction> <room> <clip_dir>

<clip_dir> holds v2_<f>_<room>_part1..3.mp4 (+ .mp3): 15 s clips of the framed parts that tools/rooms/v2_cut3.py made
(art/rooms_v2/<f>/pieces3/, with v2_<f>_<room>_cuts.json saying where each part sits in the strip). The video generator
painted the white bands (ceiling / floor) and may have shifted or zoomed the frame a little, so each clip's first frame is
matched against its strip piece to find it again. The parts are put back at their place in the strip, the small overlaps
at the cuts (where nobody stands) are blended, and the last second fades into the first so the room loops. Writes:

  assets/rooms/<f>/<room>.jpg            the still (the 360 strip, 4096 wide)
  assets/rooms/<f>/<room>.ogv            the moving room (Theora, 3072 wide)
  assets/rooms/<f>/<room>.a1/.a2/.a3.ogg its sound, one per third of the loop (each part's MP3 goes to the third it faces)
  scripts/room_seams.gd                  the cuts and how much the clips disagree there (Evee covers the worst)
"""
import json, os, subprocess, sys
import cv2, numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GW = 3072
SW = 4096
FADE = 1.0


def locate(frame, piece):
    """Where the strip piece sits in the frame: (x, y, w, h), searching a range of scales (the generator may zoom)."""
    g = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    pg = cv2.cvtColor(piece, cv2.COLOR_BGR2GRAY)
    best = (-1, None)
    small = 0.25
    gs = cv2.resize(g, None, fx=small, fy=small, interpolation=cv2.INTER_AREA)
    for k in np.linspace(0.88, 1.12, 25):
        w = int(round(frame.shape[1] * k)); h = int(round(piece.shape[0] * w / piece.shape[1]))
        if h > frame.shape[0] * 1.05 or w < 16: continue
        t = cv2.resize(pg, (max(4, int(w * small)), max(4, int(h * small))), interpolation=cv2.INTER_AREA)
        if t.shape[0] > gs.shape[0] or t.shape[1] > gs.shape[1]:   # (zoomed past the frame: compare the middle)
            cx = (t.shape[1] - gs.shape[1]) // 2 + 1
            cy = max(0, (t.shape[0] - gs.shape[0]) // 2 + 1)
            t2 = t[cy:cy + min(t.shape[0], gs.shape[0]) - 2, cx:cx + gs.shape[1] - 2]
            r = cv2.matchTemplate(gs, t2, cv2.TM_CCOEFF_NORMED)
            _, mv, _, ml = cv2.minMaxLoc(r)
            cand = (mv, (int((ml[0] - cx) / small), int((ml[1] - cy) / small), w, h))
        else:
            r = cv2.matchTemplate(gs, t, cv2.TM_CCOEFF_NORMED)
            _, mv, _, ml = cv2.minMaxLoc(r)
            cand = (mv, (int(ml[0] / small), int(ml[1] / small), w, h))
        if cand[0] > best[0]: best = cand
    return best


def main():
    f, room, cdir = sys.argv[1], sys.argv[2], sys.argv[3]
    pano = cv2.imread(os.path.join(ROOT, "art/rooms_v2", f, "pano", room + "_360.png"))
    meta = json.load(open(os.path.join(ROOT, "art/rooms_v2", f, "pieces3", "v2_%s_%s_cuts.json" % (f, room))))
    H, W = pano.shape[:2]
    if [W, H] != meta["strip"]: sys.exit("the strip changed since it was cut: cut it again")
    GH = int(round(GW * H / W / 2) * 2)
    s = GW / W
    out_dir = os.path.join(ROOT, "assets/rooms", f)
    os.makedirs(out_dir, exist_ok=True)
    cv2.imwrite(os.path.join(out_dir, room + ".jpg"), cv2.resize(pano, (SW, int(round(SW * H / W))), interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 88])
    wrap = np.concatenate([pano, pano], axis=1)
    caps, places, spans = [], [], []
    for i, pt in enumerate(meta["parts"]):
        c = os.path.join(cdir, "v2_%s_%s_part%d.mp4" % (f, room, i + 1))
        if not os.path.exists(c): sys.exit("missing " + c)
        cap = cv2.VideoCapture(c)
        ok, fr = cap.read()
        if not ok: sys.exit("cannot read " + c)
        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
        x0, w = int(pt["strip_x0"]), int(pt["strip_w"])
        piece = wrap[:, x0:x0 + w]
        score, rect = locate(fr, piece)
        print("part %d: found at %s in %dx%d (match %.2f)" % (i + 1, rect, fr.shape[1], fr.shape[0], score))
        if score < 0.45: print("  WARNING: weak match: check this clip by eye")
        caps.append(cap); places.append(rect); spans.append((x0, w))
    N = int(min(c.get(cv2.CAP_PROP_FRAME_COUNT) for c in caps))
    fps = caps[0].get(cv2.CAP_PROP_FPS) or 24.0
    nf = int(round(FADE * fps))
    OV = int(meta["overlap"])
    # each part's weight across its own width: 1 inside, ramping down over the overlap at each end
    wts, gx = [], []
    for x0, w in spans:
        gw = int(round(w * s)); go = max(2, int(round(2 * OV * s)))
        xx = np.arange(gw, dtype=np.float32)
        wt = np.clip(np.minimum(xx + 0.5, gw - xx - 0.5) / go, 0.0, 1.0)
        wts.append(np.repeat(wt[None, :, None], GH, axis=0)); gx.append((int(round(x0 * s)), gw))
    ogv = os.path.join(out_dir, room + ".ogv")
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", "%dx%d" % (GW, GH), "-r", str(fps),
                            "-i", "-", "-c:v", "libtheora", "-q:v", "4", "-pix_fmt", "yuv420p", ogv], stdin=subprocess.PIPE)
    head = []
    diffs = [0.0, 0.0, 0.0]
    for k in range(N):
        acc = np.zeros((GH, GW * 2, 3), np.float32)
        ws = np.zeros((GH, GW * 2, 1), np.float32)
        parts = []
        for i, c in enumerate(caps):
            ok, fr = c.read()
            if not ok: break
            x, y, w, h = places[i]
            pad = cv2.copyMakeBorder(fr, max(0, -y), max(0, y + h - fr.shape[0]), max(0, -x), max(0, x + w - fr.shape[1]), cv2.BORDER_REPLICATE)
            crop = pad[max(0, y):max(0, y) + h, max(0, x):max(0, x) + w]
            p = cv2.resize(crop, (gx[i][1], GH), interpolation=cv2.INTER_AREA).astype(np.float32)
            parts.append(p)
            a = gx[i][0]
            acc[:, a:a + gx[i][1]] += p * wts[i]
            ws[:, a:a + gx[i][1]] += wts[i]
        if len(parts) < 3: break
        for i in range(3):   # how much neighbours disagree in their overlap (for Evee)
            j = (i + 1) % 3
            o = int(round(2 * OV * s))
            diffs[i] += float(np.abs(parts[i][:, -o:] - parts[j][:, :o]).mean())
        acc[:, :GW] += acc[:, GW:]
        ws[:, :GW] += ws[:, GW:]
        comp = acc[:, :GW] / np.maximum(ws[:, :GW], 1e-4)
        if k < nf:
            head.append(comp)
            continue
        if k >= N - nf:
            al = (k - (N - nf) + 1) / (nf + 1)
            comp = comp * (1 - al) + head[k - (N - nf)] * al
        enc.stdin.write(np.clip(comp, 0, 255).astype(np.uint8).tobytes())
    enc.stdin.close()
    enc.wait()
    T = (N - nf) / fps
    # sound: each part's MP3 goes to the third of the loop its middle faces
    thirds = {}
    for i, (x0, w) in enumerate(spans):
        mid = ((x0 + w / 2.0) % W) / W
        t = int(mid * 3) % 3
        while t in thirds: t = (t + 1) % 3
        thirds[t] = i
    for t in range(3):
        a = os.path.join(cdir, "v2_%s_%s_part%d.mp3" % (f, room, thirds[t] + 1))
        out = os.path.join(out_dir, "%s.a%d.ogg" % (room, t + 1))
        if not os.path.exists(a):
            if os.path.exists(out): os.remove(out)
            continue
        af = "[0:a]atrim=%.3f:%.3f,asetpts=PTS-STARTPTS[bb];[1:a]atrim=0:%.3f,asetpts=PTS-STARTPTS[hh];[bb][hh]acrossfade=d=%.3f[o]" % (FADE, T + FADE, FADE, FADE)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", a, "-i", a, "-filter_complex", af, "-map", "[o]", "-ac", "1", "-ar", "32000",
                        "-c:a", "libvorbis", "-q:a", "3", out], check=True)
    seams = [round(meta["cuts"][(i + 1) % 3] / W, 4) for i in range(3)]
    bad = [round(d / max(1, N), 2) for d in diffs]
    sp = os.path.join(ROOT, "scripts/room_seams.gd")
    data = {}
    if os.path.exists(sp):
        t = open(sp).read()
        data = json.loads(t[t.index("const ROOMS := ") + 15:].strip())
    data["%s_%s" % (f, room)] = {"seams": seams, "bad": bad}
    with open(sp, "w") as o:
        o.write("## v11.6 (generated by tools/rooms/v2_animate.py / v2_animate3.py): where each moving room's seams are (share of the loop)\n")
        o.write("## and how much the clips disagree there (bigger = worse): Evee stands on the worst one to hide it.\n")
        o.write("extends RefCounted\n\nconst ROOMS := " + json.dumps(data, separators=(",", ":"), sort_keys=True) + "\n")
    print("done %s %s: %dx%d, %d frames, loop %.2f s, %.1f MB, seams %s bad %s" % (f, room, GW, GH, N - nf, T, os.path.getsize(ogv) / 1e6, seams, bad))


if __name__ == "__main__":
    main()
