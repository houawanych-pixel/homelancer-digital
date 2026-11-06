"""v12.14: put the owner's animated GPT room clips in the game (<System>_<Place>_<Room>_loop4s.mp4: 1920x1080, the
FRONT view on the top half and the BACK view on the bottom half, first frame = the still).
Each frame becomes the same 360 loop as the placeholder still (tools/rooms/install_loc.py: front | back, a soft blend at
both joins, no mirroring), 3072 wide, Theora, no sound: assets/rooms/loc/<sys>_<place>_<room>.ogv, next to the still,
in the same pack (the room plays it by itself when it's there). A place or room with no still in the game yet gets one
from the clip's first frame.
usage: python3 tools/rooms/install_loc_clip.py <folder of _loop4s.mp4>"""
import sys, os, glob, json, subprocess, shutil, tempfile
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
SYS = {"solara": "solara", "vega": "vega", "veranthos": "veranthos", "aurelion": "aurelion", "syntharicapital": "synthari_capital", "vantara": "vantara", "dreadholm": "dreadholm"}
GW = 3072        # game video width (as the other moving rooms)
B0 = 160         # the still's blend width at 1672 px (install_loc.py)

def halves(a):
    H = a.shape[0]; m = H // 2; k = max(1, round(6 * H / 941))
    top = a[:m - k]; bot = a[m + k:]; h = min(top.shape[0], bot.shape[0])
    return top[:h].astype(np.float32), bot[:h].astype(np.float32)

def loop(a, B):
    f, b = halves(a)
    t = np.linspace(0, 1, B)[None, :, None]
    ab = f[:, -B:] * (1 - t) + b[:, :B] * t
    ba = b[:, -B:] * (1 - t) + f[:, :B] * t
    return np.concatenate([ba[:, B // 2:], f[:, B:-B], ab, b[:, B:-B], ba[:, :B // 2]], 1)

def probe(p):
    o = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height,r_frame_rate,nb_frames",
                                            "-of", "json", p]))["streams"][0]
    n, d = o["r_frame_rate"].split("/")
    return int(o["width"]), int(o["height"]), float(n) / float(d)

done, stills = [], []
src = sys.argv[1]
for p in sorted(glob.glob(os.path.join(src, "*_loop4s.mp4"))):
    parts = os.path.basename(p)[:-len("_loop4s.mp4")].split("_")
    if len(parts) != 3 or parts[0].lower() not in SYS: print("skip", p); continue
    sy = SYS[parts[0].lower()]; place = parts[1]; room = parts[2].lower()
    slug = "%s_%s_%s" % (sy, place.lower(), room)
    W, H, fps = probe(p)
    B = round(B0 * W / 1672)
    # the still, if the game has none yet: the clip's first frame (the owner's still, at the clip's size)
    new_still = not os.path.exists("assets/rooms/loc/%s.jpg" % slug)
    if new_still:
        tmp = tempfile.mkdtemp()
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", p, "-frames:v", "1", os.path.join(tmp, "%s_%s_%s.png" % (parts[0], place, parts[2]))], check=True)
        subprocess.run([sys.executable, "tools/rooms/install_loc.py", tmp], check=True, stdout=subprocess.DEVNULL)
        shutil.rmtree(tmp); stills.append(slug)
    dec = subprocess.Popen(["ffmpeg", "-v", "error", "-i", p, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    enc = None
    n = 0
    while True:
        raw = dec.stdout.read(W * H * 3)
        if len(raw) < W * H * 3: break
        fr = np.frombuffer(raw, np.uint8).reshape(H, W, 3)
        lp = np.clip(loop(fr, B), 0, 255).astype(np.uint8)
        gh = round(lp.shape[0] * GW / lp.shape[1]) // 2 * 2
        im = Image.fromarray(lp).resize((GW, gh), Image.LANCZOS)
        if enc is None:
            out = "assets/rooms/loc/%s.ogv" % slug
            if new_still:   # the still = this clip's first frame, made the same way (so the switch from still to video doesn't jump)
                Image.fromarray(lp).resize((4096, round(lp.shape[0] * 4096 / lp.shape[1])), Image.LANCZOS).save("assets/rooms/loc/%s.jpg" % slug, quality=86, optimize=True)
            enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (GW, gh), "-r", "%g" % fps, "-i", "-",
                                    "-an", "-c:v", "libtheora", "-q:v", "5", "-pix_fmt", "yuv420p", out], stdin=subprocess.PIPE)
        enc.stdin.write(im.tobytes()); n += 1
    dec.wait()
    if enc is not None:
        enc.stdin.close(); enc.wait()
        done.append([slug, n, round(os.path.getsize("assets/rooms/loc/%s.ogv" % slug) / 1e6, 2)])
        print("clip", slug, n, "frames", done[-1][2], "MB", flush=True)
print(json.dumps({"clips": done, "new_stills": stills}))
