#!/usr/bin/env python3
"""Rooms V2: join the six animated pieces of a room back into one moving 360 room (v11.5).

    python3 tools/rooms/v2_animate.py <faction> <room> <clip_dir>

<clip_dir> holds v2_<f>_<room>_piece1..6.mp4 (+ .mp3), each one 15 s clip of the 1920x1080 piece that
tools/rooms/v2_room.py cut from art/rooms_v2/<f>/pano/<room>_360.png (piece i starts at strip x = round(i*W/6)).
Each clip is scaled back to its place in the strip and the overlaps are blended (a linear ramp across each overlap);
the last second of the loop fades into its first second, so it loops without a jump. Writes:

  assets/rooms/<f>/<room>.jpg            the still (the V2 360 strip, 4096 wide), shown until the video is in
  assets/rooms/<f>/<room>.ogv            the moving room (Theora, 3072 wide, same shape as the still)
  assets/rooms/<f>/<room>.a1.ogg .a2 .a3 its sound in thirds (pieces 1+2, 3+4, 5+6; the game fades them by where you look)

Prints where the front view's middle sits along the strip (Data.ROOM_FRONT_V2).
"""
import os, subprocess, sys
import cv2, numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GW = 3072        # game video width
SW = 4096        # still width
FADE = 1.0       # s: loop crossfade


def main():
    f, room, cdir = sys.argv[1], sys.argv[2], sys.argv[3]
    pano = cv2.imread(os.path.join(ROOT, "art/rooms_v2", f, "pano", room + "_360.png"))
    H, W = pano.shape[:2]
    pw = round(H * 16 / 9)
    GH = int(round(GW * H / W / 2) * 2)
    s = GW / W
    out_dir = os.path.join(ROOT, "assets/rooms", f)
    os.makedirs(out_dir, exist_ok=True)
    # the still
    cv2.imwrite(os.path.join(out_dir, room + ".jpg"), cv2.resize(pano, (SW, int(round(SW * H / W))), interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 88])
    # where the front view's middle is (the top half of the original picture)
    orig = cv2.imread(os.path.join(ROOT, "art/rooms_v2", f, room + ".png"))
    if orig is not None:
        top = orig[: orig.shape[0] // 2 - 8]
        k = H / top.shape[0]
        ts = cv2.resize(top, (int(top.shape[1] * k), H))
        cw = ts.shape[1] // 4
        mid = ts[:, ts.shape[1] // 2 - cw // 2: ts.shape[1] // 2 + cw // 2]
        wrap = np.concatenate([pano, pano[:, :mid.shape[1]]], axis=1)
        r = cv2.matchTemplate(cv2.cvtColor(wrap, cv2.COLOR_BGR2GRAY), cv2.cvtColor(mid, cv2.COLOR_BGR2GRAY), cv2.TM_CCOEFF_NORMED)
        _, mv, _, ml = cv2.minMaxLoc(r)
        print("front middle at %.4f of the strip (match %.2f)" % (((ml[0] + mid.shape[1] / 2) % W) / W, mv))
    # the pieces, back in place
    caps, xs = [], []
    for i in range(6):
        c = os.path.join(cdir, "v2_%s_%s_piece%d.mp4" % (f, room, i + 1))
        if not os.path.exists(c): sys.exit("missing " + c)
        caps.append(cv2.VideoCapture(c))
        xs.append(round(i * W / 6 * s))
    pg = int(round(pw * s))
    ramp = max(2, pg - GW // 6)   # the overlap with the next piece
    x = np.arange(pg, dtype=np.float32)
    wt = np.clip(np.minimum(x + 0.5, pg - x - 0.5) / ramp, 0.0, 1.0)
    wt = np.repeat(wt[None, :, None], GH, axis=0)
    N = int(min(c.get(cv2.CAP_PROP_FRAME_COUNT) for c in caps))
    fps = caps[0].get(cv2.CAP_PROP_FPS) or 24.0
    nf = int(round(FADE * fps))
    ogv = os.path.join(out_dir, room + ".ogv")
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", "%dx%d" % (GW, GH), "-r", str(fps),
                            "-i", "-", "-c:v", "libtheora", "-q:v", "4", "-pix_fmt", "yuv420p", ogv], stdin=subprocess.PIPE)
    head = []
    for k in range(N):
        acc = np.zeros((GH, GW + pg, 3), np.float32)
        ws = np.zeros((GH, GW + pg, 1), np.float32)
        for i, c in enumerate(caps):
            ok, fr = c.read()
            if not ok: break
            p = cv2.resize(fr, (pg, GH), interpolation=cv2.INTER_AREA).astype(np.float32)
            acc[:, xs[i]:xs[i] + pg] += p * wt
            ws[:, xs[i]:xs[i] + pg] += wt[:, :, :1]
        acc[:, :pg] += acc[:, GW:GW + pg]   # (the last piece wraps round to the start)
        ws[:, :pg] += ws[:, GW:GW + pg]
        comp = acc[:, :GW] / np.maximum(ws[:, :GW], 1e-4)
        if k < nf:
            head.append(comp)
            continue
        if k >= N - nf:
            a = (k - (N - nf) + 1) / (nf + 1)
            comp = comp * (1 - a) + head[k - (N - nf)] * a
        enc.stdin.write(np.clip(comp, 0, 255).astype(np.uint8).tobytes())
    enc.stdin.close()
    enc.wait()
    T = (N - nf) / fps   # the loop's length
    # the sound: pieces 1+2, 3+4, 5+6, each looped with the same fade
    for t in range(3):
        a, b = [os.path.join(cdir, "v2_%s_%s_piece%d.mp3" % (f, room, 2 * t + j + 1)) for j in range(2)]
        out = os.path.join(out_dir, "%s.a%d.ogg" % (room, t + 1))
        if not (os.path.exists(a) and os.path.exists(b)):
            if os.path.exists(out): os.remove(out)
            continue
        af = ("[0:a][1:a]amix=inputs=2:normalize=0,volume=0.75,atrim=%.3f:%.3f,asetpts=PTS-STARTPTS[bb];"
              "[2:a][3:a]amix=inputs=2:normalize=0,volume=0.75,atrim=0:%.3f,asetpts=PTS-STARTPTS[hh];"
              "[bb][hh]acrossfade=d=%.3f[o]" % (FADE, T + FADE, FADE, FADE))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", a, "-i", b, "-i", a, "-i", b, "-filter_complex", af, "-map", "[o]",
                        "-ac", "1", "-ar", "32000", "-c:a", "libvorbis", "-q:a", "3", out], check=True)
    print("done %s %s: %dx%d, %d frames, loop %.2f s, %.1f MB" % (f, room, GW, GH, N - nf, T, os.path.getsize(ogv) / 1e6))


if __name__ == "__main__":
    main()
