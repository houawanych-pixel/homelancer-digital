"""v12.21: put GPT's filled join images in the game. Each filled file is matched to its room by its kept pixels (the
filled image keeps every pixel outside the two white gaps, so the file name doesn't matter: Drive downloads arrive as
.tmp). For each match:
  - the filled image  -> art/rooms/loc/<sys>/joins/<Place>_<Room>_joins_filled.png
  - the stitched loop -> assets/rooms/loc/<sys>_<place>_<room>.jpg (4096 wide, q86), replacing the placeholder blend
Rooms with an animated loop (.ogv) keep their still (it is the video's first frame), only the filled join is saved.
usage: python3 tools/rooms/install_filled.py <folder of filled files (.png or .tmp)>"""
import sys, os, glob, json, subprocess, tempfile
import numpy as np
from PIL import Image
E = 560

def key(im):
    """the kept left block of the top row, small and grey"""
    W, H = im.size
    return np.asarray(im.convert("L").crop((0, 0, E, H // 2 - 6)).resize((70, 50), Image.BILINEAR), np.float32)

tmpl = {}
for p in glob.glob("art/rooms/loc/*/joins/*_joins.png"):
    sy = p.split("/")[3]
    place, room = os.path.basename(p)[:-len("_joins.png")].split("_")
    tmpl[p] = (sy, place, room, key(Image.open(p)), Image.open(p).size)
def level(im):
    """GPT's painted gap meets the kept pixels with a step in brightness and a thin line: per row, the colour step at each
    edge of the gap is measured (smoothed down the picture) and faded out into the painting over LV px, then a narrow
    band across each edge is softened."""
    from PIL import ImageFilter
    a = np.asarray(im, np.float32).copy()
    W, H = im.size; m = H // 2
    for y0, y1 in [(0, m - 6), (m + 6, H)]:
        rows = a[y0:y1]
        for g, d in [(E, 1), (W - E - 1, -1)]:
            kept = rows[:, g - d * 3: g - d * 1: d].mean(1) if d > 0 else rows[:, g + 2: g + 4].mean(1)
            paint = rows[:, g + d * 2: g + d * 4: d].mean(1) if d > 0 else rows[:, g - 3: g - 1].mean(1)
            step = kept - paint
            k = np.ones(31) / 31.0
            step = np.stack([np.convolve(np.pad(step[:, c], 15, mode="edge"), k, "valid") for c in range(3)], 1)
            LV = 140
            for t in range(LV):
                x = g + d * t
                rows[:, x] += step * (1.0 - t / LV) ** 1.5
        a[y0:y1] = rows
    out = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    soft = out.filter(ImageFilter.GaussianBlur(2.2))
    mask = Image.new("L", out.size, 0)
    from PIL import ImageDraw
    dr = ImageDraw.Draw(mask)
    for g in (E, W - E):
        dr.rectangle([g - 6, 0, g + 6, H], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(4))
    return Image.composite(soft, out, mask)

done, skipped, unmatched = [], [], []
env = dict(os.environ, STITCH_SEAM="1", STITCH_MATCH="1")
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*"))):
    try:
        im = Image.open(f).convert("RGB")
    except Exception:
        continue
    k = key(im)
    best = min(tmpl.items(), key=lambda kv: float(np.abs(kv[1][3] - k).mean()) + (0 if kv[1][4] == im.size else 1e6))
    err = float(np.abs(best[1][3] - k).mean())
    if err > 6.0:
        unmatched.append([os.path.basename(f), round(err, 1)])
        continue
    sy, place, room, _, _ = best[1]
    slug = "%s_%s_%s" % (sy, place.lower(), room.lower())
    filled = "art/rooms/loc/%s/joins/%s_%s_joins_filled.png" % (sy, place, room)
    im.save(filled)   # (GPT's file as it came)
    if os.path.exists("assets/rooms/loc/%s.ogv" % slug):
        skipped.append(slug)
        continue
    orig = "art/rooms/loc/%s/%s_%s.png" % (sy, place, room)
    out = tempfile.mktemp(suffix=".png")
    lev = tempfile.mktemp(suffix=".png")
    level(im).save(lev)
    r = subprocess.run([sys.executable, "tools/rooms/stitch_filled.py", orig, lev, out], env=env, capture_output=True, text=True)
    os.remove(lev)
    if r.returncode != 0:
        unmatched.append([slug, "stitch failed"])
        continue
    lp = Image.open(out)
    lp.resize((4096, round(lp.height * 4096 / lp.width)), Image.LANCZOS).save("assets/rooms/loc/%s.jpg" % slug, quality=86, optimize=True)
    os.remove(out)
    done.append(slug)
    print("stitched", slug, r.stdout.strip().split("shifts")[-1], flush=True)
print(json.dumps({"stitched": len(done), "animated_kept": skipped, "unmatched": unmatched}))
