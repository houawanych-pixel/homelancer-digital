"""v12.4: put one place's own GPT room pictures in the game as PLACEHOLDER 360 loops (before the joins are painted).
Each picture is the owner's split room (front view on top, back below), named <System>_<Place>_<Room>.png
(Solara_LibertyHub_Hub.png). The loop is front | back with a short soft blend at both joins (no mirroring).
When the owner sends the filled joins, stitch_filled.py makes the real loop and replaces the game copy.
usage: python3 tools/rooms/install_loc.py <folder of pngs>
  - originals  -> art/rooms/loc/<sys>/<Place>_<Room>.png
  - join images-> art/rooms/loc/<sys>/joins/<Place>_<Room>_joins.png (for ChatGPT to fill)
  - game copy  -> assets/rooms/loc/<sys>_<place>_<room>.jpg (4096 wide, q86), one pack each in scripts/packs.gd
  - Data.LOC_ROOMS lists every place's rooms."""
import sys, os, re, glob, subprocess, shutil
import numpy as np
from PIL import Image
SYS = {"solara": "solara", "vega": "vega", "veranthos": "veranthos", "aurelion": "aurelion", "syntharicapital": "synthari_capital", "vantara": "vantara", "dreadholm": "dreadholm", "sepheron": "sepheron"}   # (enemy space is not panoramas: infiltration facilities, owner v12.4; its pictures stay in art/ only)
B = 160   # blend width at each join (px of the original)

def halves(im):
    W, H = im.size; m = H // 2
    top = im.crop((0, 0, W, m - 6)); bot = im.crop((0, m + 6, W, H)); h = min(top.height, bot.height)
    return np.asarray(top.crop((0, 0, W, h)), np.float32), np.asarray(bot.crop((0, 0, W, h)), np.float32)

def loop(im):
    a, b = halves(im)
    t = np.linspace(0, 1, B)[None, :, None]
    ab = a[:, -B:] * (1 - t) + b[:, :B] * t          # FRONT end -> BACK start
    ba = b[:, -B:] * (1 - t) + a[:, :B] * t          # BACK end -> FRONT start (the wrap)
    out = np.concatenate([ba[:, B // 2:], a[:, B:-B], ab, b[:, B:-B], ba[:, :B // 2]], 1)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))

src = sys.argv[1]
rooms = {}
for p in sorted(glob.glob(os.path.join(src, "*.png"))):
    parts = os.path.basename(p)[:-4].split("_")
    if len(parts) != 3: continue
    sy = SYS.get(parts[0].lower());  place = parts[1]; room = parts[2].lower()
    if sy is None: continue
    slug = "%s_%s" % (sy, place.lower())
    art = "art/rooms/loc/%s" % sy; os.makedirs(art + "/joins", exist_ok=True); os.makedirs("assets/rooms/loc", exist_ok=True)
    shutil.copy(p, "%s/%s_%s.png" % (art, place, parts[2]))
    subprocess.run([sys.executable, "tools/rooms/make_joins.py", p, "%s/joins/%s_%s_joins.png" % (art, place, parts[2])], check=True)
    im = loop(Image.open(p).convert("RGB"))
    im = im.resize((4096, round(im.height * 4096 / im.width)), Image.LANCZOS)
    im.save("assets/rooms/loc/%s_%s.jpg" % (slug, room), quality=86, optimize=True)
    rooms.setdefault(slug, []).append(room)

pk = "scripts/packs.gd"; s = open(pk).read()
add = ""
for slug, rs in sorted(rooms.items()):
    for r in rs:
        n = "%s_%s" % (slug, r)
        if '"room_loc_%s"' % n not in s:
            add += '\t"room_loc_%s": {"folders": ["res://assets/rooms/loc"], "match": "%s.", "probe": "res://assets/rooms/loc/%s.jpg"},   # v12.4: GPT room (placeholder loop)\n' % (n, n, n)
i = s.index('\t"room_liberator_main_hub"'); s = s[:i] + add + s[i:]; open(pk, "w").write(s)

dp = "scripts/data.gd"; d = open(dp).read()
m = re.search(r'const LOC_ROOMS := \{[^\n]*\}', d)
old = {}
if m:
    for k, v in re.findall(r'"([a-z_]+)": \[([^\]]*)\]', m.group(0)): old[k] = re.findall(r'"([a-z_]+)"', v)
for k, v in rooms.items(): old[k] = sorted(set(old.get(k, []) + v))
line = "const LOC_ROOMS := {" + ", ".join('"%s": [%s]' % (k, ", ".join('"%s"' % r for r in old[k])) for k in sorted(old)) + "}"
d = d.replace(m.group(0), line) if m else d.replace("const ROOM_FACTIONS :=", line + "   # v12.4: a place's own room set (tools/rooms/install_loc.py)\nconst ROOM_FACTIONS :=", 1)
open(dp, "w").write(d)
print({k: v for k, v in rooms.items()})
