#!/usr/bin/env python3
"""Turn the owner's three animated thirds of a room into a moving 360 room (v5.9).

    python3 tools/rooms/animate_room.py clip_a.mp4 clip_b.mp4 clip_c.mp4 [--room liberator/pilots_lounge]

The clips can come in any order and with any extra ceiling/floor the video generator added: each clip's first frame
is matched to the room loops in art/rooms/<faction>/pano/ (all of them, unless --room is given) to find which room
and which third it is, and where the original strip sits inside it. Then:

  art/rooms/<f>/animated/<room>_loop.mp4      the joined loop (H.264, kept for Echo Vision)
  assets/rooms/<f>/<room>.ogv                 the game copy (Theora, 3072 x 320)
  assets/rooms/<f>/<room>.a1.ogg .a2 .a3      each third's own sound (the game fades them by where you look)
"""
import glob, os, subprocess, sys
import cv2, numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GW, GH = 3072, 320          # game video size (same shape as the 4096 x 427 still)
FADE = 1.0                  # s: the end of each clip fades into its own start (owner: a fade at the loop point)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "format=duration",
                          "-of", "csv=p=0", path], capture_output=True, text=True).stdout.strip()
    return float(out)


def first_frame(path):
    cap = cv2.VideoCapture(path)
    ok, fr = cap.read()
    if not ok: sys.exit("cannot read " + path)
    return fr


def thirds(pano):
    H, W = pano.shape[:2]
    w = W // 3
    return [pano[:, i * w:(i + 1) * w if i < 2 else W] for i in range(3)]


def place(frame, third):
    """Score and vertical offset of this third inside the frame (full width kept, generator added top/bottom)."""
    sx = frame.shape[1] / third.shape[1]
    ts = cv2.resize(third, (frame.shape[1], int(round(third.shape[0] * sx))))
    g = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    tg = cv2.cvtColor(ts, cv2.COLOR_BGR2GRAY)
    m = frame.shape[1] // 8
    if ts.shape[0] >= frame.shape[0]:   # same shape (or a touch flatter): the whole frame is the third
        tg = cv2.resize(tg, (g.shape[1], g.shape[0]))
        r = cv2.matchTemplate(g[:, m:-m], tg[:, m:-m], cv2.TM_CCOEFF_NORMED)
        return float(r.max()), 0, frame.shape[0]
    r = cv2.matchTemplate(g[:, m:-m], tg[:, m:-m], cv2.TM_CCOEFF_NORMED)
    _, mv, _, ml = cv2.minMaxLoc(r)
    return mv, ml[1], ts.shape[0]


def main():
    args = sys.argv[1:]
    room = None
    if "--room" in args:
        i = args.index("--room")
        room = args[i + 1]
        del args[i:i + 2]
    clips = args
    if len(clips) != 3: sys.exit(__doc__)
    panos = sorted(glob.glob(os.path.join(ROOT, "art/rooms/*/pano/*.jpg")))
    if room:
        f, r = room.split("/")
        panos = [p for p in panos if p.endswith("/%s/pano/%s_%s.jpg" % (f, f, r))]
    small = {}
    for p in panos:
        im = cv2.imread(p)
        small[p] = [cv2.resize(t, (400, int(t.shape[0] * 400 / t.shape[1]))) for t in thirds(im)]
    picks = []
    for c in clips:
        fr = first_frame(c)
        fs = cv2.resize(fr, (400, int(fr.shape[0] * 400 / fr.shape[1])))
        best = max(((place(fs, t)[0], p, i) for p in small for i, t in enumerate(small[p])), key=lambda x: x[0])
        picks.append((c, best))
        print("%s -> %s third %d (score %.2f)" % (os.path.basename(c), os.path.basename(best[1]), best[2] + 1, best[0]))
    rooms = {b[1] for _, b in picks}
    idx = sorted(b[2] for _, b in picks)
    if len(rooms) != 1 or idx != [0, 1, 2]: sys.exit("the three clips are not the three thirds of one room")
    pano_path = rooms.pop()
    faction = pano_path.split("/")[-3]
    rname = os.path.basename(pano_path)[len(faction) + 1:-4]
    pano = cv2.imread(pano_path)
    ordered = [None] * 3
    for c, b in picks:
        fr = first_frame(c)
        score, y, h = place(fr, thirds(pano)[b[2]])
        ordered[b[2]] = (c, y, h, fr.shape[1])
        print("  third %d: crop y %d, height %d (score %.2f)" % (b[2] + 1, y, h, score))
    ws = [GW // 3 + (1 if i < GW % 3 else 0) for i in range(3)]
    T = min(duration(c) for c, *_ in ordered) - 0.1   # (all three the same length, so they stay in step)
    F = FADE
    inputs, chains = [], []
    for i, (c, y, h, w) in enumerate(ordered):
        inputs += ["-i", c]
        # seamless loop: start at F, and fade the last F seconds into the clip's own first F seconds
        chains.append("[%d:v]trim=0:%.3f,setpts=PTS-STARTPTS,crop=%d:%d:0:%d,scale=%d:%d,setsar=1,fps=24,split[h%d][b%d];"
                      "[h%d]trim=0:%.3f,setpts=PTS-STARTPTS[hh%d];[b%d]trim=%.3f,setpts=PTS-STARTPTS[bb%d];"
                      "[bb%d][hh%d]xfade=transition=fade:duration=%.3f:offset=%.3f[v%d]"
                      % (i, T, w, h, y, ws[i], GH, i, i, i, F, i, i, F, i, i, i, F, T - 2 * F, i))
    fc = ";".join(chains) + ";[v0][v1][v2]hstack=3,format=yuv420p[v]"
    art = os.path.join(ROOT, "art/rooms", faction, "animated")
    os.makedirs(art, exist_ok=True)
    loop = os.path.join(art, rname + "_loop.mp4")
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", fc, "-map", "[v]", "-an",
                    "-c:v", "libx264", "-crf", "24", "-preset", "veryfast", loop], check=True)
    game = os.path.join(ROOT, "assets/rooms", faction)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", loop, "-c:v", "libtheora", "-q:v", "4", "-an",
                    os.path.join(game, rname + ".ogv")], check=True)
    for i, (c, *_rest) in enumerate(ordered):
        has_audio = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries", "stream=index",
                                    "-of", "csv=p=0", c], capture_output=True, text=True).stdout.strip() != ""
        out = os.path.join(game, "%s.a%d.ogg" % (rname, i + 1))
        if has_audio:
            # (two inputs of the same file, not asplit: asplit + acrossfade stalls in ffmpeg and writes nothing)
            af = ("[0:a]atrim=%.3f:%.3f,asetpts=PTS-STARTPTS[bb];[1:a]atrim=0:%.3f,asetpts=PTS-STARTPTS[hh];"
                  "[bb][hh]acrossfade=d=%.3f[a]" % (F, T, F, F))
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", c, "-i", c, "-filter_complex", af, "-map", "[a]", "-ac", "1",
                            "-ar", "32000", "-c:a", "libvorbis", "-q:a", "3", out], check=True)
        elif os.path.exists(out): os.remove(out)
    print("done:", faction, rname)


if __name__ == "__main__":
    main()
