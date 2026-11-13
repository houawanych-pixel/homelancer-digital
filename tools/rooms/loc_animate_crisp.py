#!/usr/bin/env python3
"""v13.88 (owner: "put all three together and plug it back in"): join a location room's 3 animated clips (made from
loc_cut_crisp.py pieces) back into the moving 360 room, edge to edge with HARD, crisp seams (no blend, no blur).

    python3 tools/rooms/loc_animate_crisp.py <sys> <Place> <Room> <clip_dir>

<clip_dir> holds <Place>_<Room>_clip1..3.mp4 (sound inside the mp4). The generator may squeeze a clip to another shape
(Liberty Hub: 3.16:1 came back 2288x912) and shift it a little, so each clip's first frame is matched to its still piece
(SIFT, full affine: separate x and y scale) and every frame is warped back onto the piece. The pieces go back seam to
seam, the last second fades (in time) into the first so the motion loops. Writes, next to the still:
  assets/rooms/loc/<sys>_<place>_<room>.ogv        3072 wide, Theora
  assets/rooms/loc/<sys>_<place>_<room>.a1..a3.ogg each clip's sound in the third of the loop it faces
  <clip_dir>/<Place>_<Room>_seams_check.jpg        frame 0 / middle / last with the seams marked (look at it)"""
import json, os, subprocess, sys
import cv2, numpy as np
sy, place, room, cdir = sys.argv[1:5]
take = sys.argv[5] if len(sys.argv) > 5 else ""   # v13.91 (owner: "a second clip back to back"): b -> <key>.b.ogv, played after the first; keeps the first take's sound
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
key = "%s_%s_%s" % (sy, place.lower(), room.lower())
meta = json.load(open(os.path.join(HERE, "loc_cuts", key + ".json")))
still = cv2.imread(os.path.join(ROOT, meta["src"])); H, W = still.shape[:2]
GW = 3072; GH = int(round(GW * H / W / 2) * 2); s = GW / W; FADE = 1.0
wrap = np.concatenate([still, still], 1)
caps, warps, bounds = [], [], []
cuts = meta["cuts"]
for i, pt in enumerate(meta["parts"]):
    c = os.path.join(cdir, "%s_%s_clip%d.mp4" % (place, room, i + 1))
    cap = cv2.VideoCapture(c); ok, fr = cap.read(); cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
    if not ok: sys.exit("cannot read " + c)
    x0, w = pt["strip_x0"], pt["strip_w"]
    gx0 = int(round(x0 * s)); gx1 = int(round((x0 + w) * s)); gw = gx1 - gx0
    piece = cv2.resize(wrap[:, x0:x0 + w], (gw, GH), interpolation=cv2.INTER_AREA)
    sift = cv2.SIFT_create(6000)
    k1, d1 = sift.detectAndCompute(cv2.cvtColor(fr, cv2.COLOR_BGR2GRAY), None)
    k2, d2 = sift.detectAndCompute(cv2.cvtColor(piece, cv2.COLOR_BGR2GRAY), None)
    ms = [a for a, b in cv2.BFMatcher().knnMatch(d1, d2, k=2) if a.distance < 0.75 * b.distance]
    p1 = np.float32([k1[m.queryIdx].pt for m in ms]); p2 = np.float32([k2[m.trainIdx].pt for m in ms])
    M, inl = cv2.estimateAffine2D(p1, p2, ransacReprojThreshold=3)
    plain = np.float32([[gw / fr.shape[1], 0, 0], [0, GH / fr.shape[0], 0]])
    if M is None or inl.sum() < 40:
        print("clip %d: few features, plain squeeze" % (i + 1)); M = plain
    test = cv2.warpAffine(fr, M, (gw, GH), flags=cv2.INTER_AREA, borderMode=cv2.BORDER_REPLICATE)
    err = float(np.abs(test.astype(int) - piece.astype(int)).mean())
    errp = float(np.abs(cv2.warpAffine(fr, plain, (gw, GH), flags=cv2.INTER_AREA).astype(int) - piece.astype(int)).mean())
    if errp <= err: M, err = plain, errp
    print("clip %d: %dx%d -> %dx%d, fit error %.1f (%d features)" % (i + 1, fr.shape[1], fr.shape[0], gw, GH, err, int(inl.sum()) if inl is not None else 0))
    caps.append(cap); warps.append((M, gw)); bounds.append(gx0)
N = int(min(c.get(cv2.CAP_PROP_FRAME_COUNT) for c in caps)); fps = caps[0].get(cv2.CAP_PROP_FPS) or 24.0
nf = int(round(FADE * fps))
out = os.path.join(ROOT, "assets/rooms/loc", key + ("." + take if take else "") + ".ogv")
enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", "%dx%d" % (GW, GH), "-r", str(fps), "-i", "-",
                        "-c:v", "libtheora", "-q:v", "4", "-pix_fmt", "yuv420p", out], stdin=subprocess.PIPE)
head = []; snaps = {}
for k in range(N):
    full = np.zeros((GH, GW, 3), np.uint8)
    for i, cap in enumerate(caps):   # hard seams: each clip owns exactly its own columns
        ok, fr = cap.read()
        if not ok: break
        M, gw = warps[i]
        full[:, (np.arange(gw) + bounds[i]) % GW] = cv2.warpAffine(fr, M, (gw, GH), flags=cv2.INTER_AREA, borderMode=cv2.BORDER_REPLICATE)
    if k in (0, N // 2, N - 1): snaps[k] = full.copy()
    if k < nf: head.append(full); continue
    if k >= N - nf:   # loop: fade IN TIME into the first second (not across the picture)
        al = (k - (N - nf) + 1) / (nf + 1)
        full = (full.astype(np.float32) * (1 - al) + head[k - (N - nf)].astype(np.float32) * al).astype(np.uint8)
    enc.stdin.write(full.tobytes())
enc.stdin.close(); enc.wait()
T = (N - nf) / fps
# sound: each clip's own audio goes to the third of the loop its middle faces
thirds = {}
for i, pt in enumerate(meta["parts"]):
    t = int(((pt["strip_x0"] + pt["strip_w"] / 2.0) % W) / W * 3) % 3
    while t in thirds: t = (t + 1) % 3
    thirds[t] = i
for t in (range(3) if not take else []):
    a = os.path.join(cdir, "%s_%s_clip%d.mp4" % (place, room, thirds[t] + 1))
    o = os.path.join(ROOT, "assets/rooms/loc", "%s.a%d.ogg" % (key, t + 1))
    af = "[0:a]atrim=%.3f:%.3f,asetpts=PTS-STARTPTS[bb];[1:a]atrim=0:%.3f,asetpts=PTS-STARTPTS[hh];[bb][hh]acrossfade=d=%.3f[o]" % (FADE, T + FADE, FADE, FADE)
    r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", a, "-i", a, "-filter_complex", af, "-map", "[o]", "-ac", "1", "-ar", "32000", "-c:a", "libvorbis", "-q:a", "3", o])
    if r.returncode: print("no sound for third", t + 1)
# check sheet: frames 0 / middle / last, seams marked in red
rows = []
for k in sorted(snaps):
    im = snaps[k].copy()
    for b in bounds: cv2.line(im, (b, 0), (b, 8), (0, 0, 255), 3); cv2.line(im, (b, GH - 9), (b, GH - 1), (0, 0, 255), 3)
    rows.append(im)
cv2.imwrite(os.path.join(cdir, "%s_%s_seams_check.jpg" % (place, room)), np.concatenate(rows, 0), [cv2.IMWRITE_JPEG_QUALITY, 88])
print("done %s: %dx%d, %d frames, loop %.2f s, %.1f MB" % (key, GW, GH, N - nf, T, os.path.getsize(out) / 1e6))
