"""Stitch a faction's filled joins into 360 loops and put them in the game.
usage: python3 tools/rooms/install_faction.py <faction> <filled.png>=<room> ...
Needs art/rooms/<faction>/<room>.png (the owner's split originals)."""
import sys, os, subprocess
from PIL import Image
ROOMS = ["main_hub","shipyard","mech_dealer","weapons","supplies","mission_center","medical_bay","command","private_quarters","pilots_lounge"]
f = sys.argv[1]
O = "art/rooms/%s" % f
os.makedirs(O + "/pano", exist_ok=True); os.makedirs(O + "/joins_filled", exist_ok=True); os.makedirs("assets/rooms/" + f, exist_ok=True)
for a in sys.argv[2:]:
    src, room = a.split("=")
    Image.open(src).save("%s/joins_filled/%s.png" % (O, room))
    pano = "%s/pano/%s_%s.jpg" % (O, f, room)
    subprocess.run([sys.executable, "tools/rooms/stitch_filled.py", "%s/%s.png" % (O, room), src, pano], check=True)
    im = Image.open(pano); im = im.resize((4096, round(im.height * 4096 / im.width)), Image.LANCZOS)
    im.save("assets/rooms/%s/%s.jpg" % (f, room), quality=86, optimize=True)
p = "scripts/packs.gd"; s = open(p).read()
add = "".join('\t"room_%s_%s": {"folders": ["res://assets/rooms/%s"], "match": "%s.", "probe": "res://assets/rooms/%s/%s.jpg"},   # the owner\'s 360 room\n' % (f, r, f, r, f, r) for r in ROOMS if ('"room_%s_%s"' % (f, r)) not in s)
i = s.index('\t"room_liberator_main_hub"'); s = s[:i] + add + s[i:]; open(p, "w").write(s)
p = "scripts/data.gd"; s = open(p).read()
import re
m = re.search(r'const ROOM_FACTIONS := \[([^\]]*)\]', s)
if '"%s"' % f not in m.group(1): s = s.replace(m.group(0), 'const ROOM_FACTIONS := [%s, "%s"]' % (m.group(1), f))
open(p, "w").write(s)
