#!/usr/bin/env python3
"""Rooms V2: join the six animated pieces of a room back into one moving 360 room (v11.5).

    python3 tools/rooms/v2_animate.py <faction> <room> <clip_dir>

<clip_dir> holds v2_<f>_<room>_piece1..6.mp4 (+ .mp3), each one 15 s clip of the 1920x1080 piece that
tools/rooms/v2_room.py cut from art/rooms_v2/<f>/pano/<room>_360.png (piece i starts at strip x = round(i*W/6)).
Each clip is scaled back to its place in the strip and each seam is a clean cut round the moving people;
the last second of the loop fades into its first second, so it loops without a jump. Writes:

  assets/rooms/<f>/<room>.jpg            the still (the V2 360 strip, 4096 wide), shown until the video is in
  assets/rooms/<f>/<room>.ogv            the moving room (Theora, 3072 wide, same shape as the still)
  assets/rooms/<f>/<room>.a1.ogg .a2 .a3 its sound in thirds (pieces 1+2, 3+4, 5+6; the game fades them by where you look)

Prints where the front view's middle sits along the strip (Data.ROOM_FRONT_V2).
"""
import json, os, subprocess, sys
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
    N = int(min(c.get(cv2.CAP_PROP_FRAME_COUNT) for c in caps))
    fps = caps[0].get(cv2.CAP_PROP_FPS) or 24.0
    nf = int(round(FADE * fps))
    # v11.6 (owner: "the seams are just put together"): each seam is a clean CUT, not a see-through fade. The cut runs
    # where the two clips agree best over the whole clip (round the moving people), so nobody shows twice.
    # Seam j joins piece j (left) and piece j+1 (right; piece 6 joins piece 1 round the back).
    starts = [xs[(j + 1) % 6] + (GW if j == 5 else 0) for j in range(6)]
    ovs = [xs[j] + pg - starts[j] for j in range(6)]
    diff = [np.zeros((GH, ovs[j]), np.float64) for j in range(6)]
    for k in range(N):
        fr = []
        for c in caps:
            ok, f_ = c.read()
            if not ok: break
            fr.append(cv2.resize(f_, (pg, GH), interpolation=cv2.INTER_AREA).astype(np.float32))
        if len(fr) < 6: break
        for j in range(6):
            a_ = fr[j][:, pg - ovs[j]:]
            b_ = fr[(j + 1) % 6][:, :ovs[j]]
            diff[j] += np.abs(a_ - b_).mean(2)
    for c in caps: c.set(cv2.CAP_PROP_POS_FRAMES, 0)
    F = 3   # px of feather either side of the cut
    cuts, bad = [], []
    for j in range(6):
        d = diff[j] / max(1, N)
        h, w = d.shape
        cost = d.copy(); back = np.zeros((h, w), int)
        for y in range(1, h):
            l = np.r_[np.inf, cost[y - 1, :-1]]; r = np.r_[cost[y - 1, 1:], np.inf]
            st = np.vstack([l, cost[y - 1], r]); kk = st.argmin(0); back[y] = kk - 1
            cost[y] += st[kk, np.arange(w)]
        cut = np.zeros(h, int); cut[-1] = int(cost[-1, F:w - F].argmin()) + F
        for y in range(h - 1, 0, -1): cut[y - 1] = np.clip(cut[y] + back[y, cut[y]], F, w - F - 1)
        cuts.append(cut)
        along = d[np.arange(h), cut]
        bad.append(round(float(np.percentile(along, 90)), 2))   # (the worst stretch of the cut: a person cut in two shows here)
    wts = []
    xx = np.arange(pg)[None, :]
    for i in range(6):
        wt = np.ones((GH, pg), np.float32)
        jr, jl = i, (i - 1) % 6   # the seam on this piece's right, and on its left
        o = ovs[jr]; x0 = pg - o   # right overlap: this piece is the left one, 1 before the cut
        r = np.clip((xx - x0 - (cuts[jr][:, None] - F)) / (2.0 * F), 0, 1)
        wt = np.where(xx >= x0, wt * (1 - r), wt)
        o = ovs[jl]   # left overlap: this piece is the right one, 1 after the cut
        r = np.clip((xx - (cuts[jl][:, None] - F)) / (2.0 * F), 0, 1)
        wt = np.where(xx < o, wt * r, wt)
        wts.append(wt[:, :, None])
    seams = [round(((starts[j] + int(np.median(cuts[j]))) % GW) / GW, 4) for j in range(6)]
    print("seams at", seams, "badness", bad)
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
            acc[:, xs[i]:xs[i] + pg] += p * wts[i]
            ws[:, xs[i]:xs[i] + pg] += wts[i]
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
    sp = os.path.join(ROOT, "scripts/room_seams.gd")
    data = {}
    if os.path.exists(sp):
        t = open(sp).read()
        data = json.loads(t[t.index("const ROOMS := ") + 15:].strip())
    data["%s_%s" % (f, room)] = {"seams": seams, "bad": bad}
    with open(sp, "w") as o:
        o.write("## v11.6 (generated by tools/rooms/v2_animate.py): where each moving room's six seams are (share of the loop) and\n")
        o.write("## how much the two clips disagree there (bigger = worse): Evee stands on the worst one to hide it.\n")
        o.write("extends RefCounted\n\nconst ROOMS := " + json.dumps(data, separators=(",", ":"), sort_keys=True) + "\n")
    print("done %s %s: %dx%d, %d frames, loop %.2f s, %.1f MB" % (f, room, GW, GH, N - nf, T, os.path.getsize(ogv) / 1e6))


if __name__ == "__main__":
    main()
