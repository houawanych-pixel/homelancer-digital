"""Cut the top-down ships out of an owner fleet sheet (HL_<Faction>_Fleet_Sheet.png) as galaxy-map sprites.

    python3 -I tools/fleet/cut_map_sprites.py <Faction> <sheet.png> [<Faction> <sheet.png> ...]

Sheet layout (owner's "SHIP LINEUP (TRIPO READY)" sheets, 1609 x 977): banner on top; row 1 = CAPITAL, CRUISER,
DESTROYER, RESUPPLY, TROOP TRANSPORT; row 2 = FRIGATE, ESCORT, SCOUT, BOMBER. Each ship is drawn twice: top-down
(tall, nose up) and a side view under it, then a name label bar. Only the top-down ships are cut; side views,
banner and label bars are ignored.

The art is never repainted: the green screen (#00FF00) is keyed by distance to the screen colour (so green hull
paint, e.g. Orion's emerald trim, stays opaque), enclosed screen pockets (inside rings) are keyed too, only the
half-transparent edge pixels lose their green spill, and the ship is cropped tight.
Writes assets/fleet_tokens/map/HL_<Faction>_<Role>_top.png and art/fleet/HL_<Faction>_Fleet_Sheet_crops.json.
"""
import json, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage as nd

ROW1 = ["Capital", "Cruiser", "Destroyer", "Resupply", "TroopTransport"]
ROW2 = ["Frigate", "Escort", "Scout", "Bomber"]
KEY = np.array([2, 249, 3])
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def banner_bottom(a, key):
    # last row near the top where the banner (left half) is still mostly not screen
    y = 40
    while y < 110 and (~key[y, :600]).mean() > 0.5:
        y += 1
    return y


def cut(faction, path):
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.int32)
    H, W = a.shape[:2]
    dist = np.sqrt(((a - KEY) ** 2).sum(-1))
    key = dist < 60
    yb = banner_bottom(a, key)
    fg = ~key
    fg[: yb + 2] = False
    fg = nd.binary_opening(fg, iterations=1)
    lab, n = nd.label(fg)
    tops = []
    for i, s in enumerate(nd.find_objects(lab)):
        h, w = s[0].stop - s[0].start, s[1].stop - s[1].start
        if h < 230 or h < w * 0.7 or (lab[s] == i + 1).sum() < 8000:
            continue   # side views are wide and short; label bars are thin
        tops.append((s[0].start, s[1].start, i + 1, s))
    r1 = sorted([t for t in tops if t[0] < H * 0.3], key=lambda t: t[1])
    r2 = sorted([t for t in tops if H * 0.5 < t[0] < H * 0.65], key=lambda t: t[1])
    if len(r1) != 5 or len(r2) != 4:
        raise SystemExit("%s: found %d + %d top-down ships, expected 5 + 4" % (faction, len(r1), len(r2)))
    # screen pockets: every screen-coloured patch of 30+ px is transparent, also inside rings
    kl, kn = nd.label(key)
    big = np.bincount(kl.ravel()) >= 4
    big[0] = False
    clear = big[kl]
    out = os.path.join(REPO, "assets/fleet_tokens/map")
    os.makedirs(out, exist_ok=True)
    crops = {}
    for role, (_, _, li, s) in list(zip(ROW1, r1)) + list(zip(ROW2, r2)):
        ship = nd.binary_fill_holes(nd.binary_dilation(lab == li, iterations=3)) & ~clear
        ys, xs = np.where(ship)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        sub = a[y0:y1, x0:x1].astype(np.float32)
        m = ship[y0:y1, x0:x1]
        dd = dist[y0:y1, x0:x1]
        # the edge ring next to the keyed screen, plus screen-tinted mixed pixels in narrow gaps (green-dominant and
        # within 120 of the screen colour; hull paint such as Orion's emerald is further than that and stays solid)
        gd = sub[..., 1] > np.maximum(sub[..., 0], sub[..., 2]) + 40
        near = (nd.binary_dilation(~m, iterations=2) | (gd & (dd < 120))) & m
        al = np.where(m, 1.0, 0.0)
        al[near] = np.clip((dd[near] - 30.0) / 90.0, 0.0, 1.0)
        rgb = sub.copy()
        sp = near & (al < 1.0)                                   # despill only mixed edge pixels
        g = rgb[..., 1]
        mx = np.maximum(rgb[..., 0], rgb[..., 2])
        g[sp] = np.minimum(g[sp], mx[sp])
        img = np.dstack([rgb, al * 255.0]).round().clip(0, 255).astype(np.uint8)
        name = "HL_%s_%s_top.png" % (faction, role)
        Image.fromarray(img, "RGBA").save(os.path.join(out, name), optimize=True)
        crops[role] = [int(x0), int(y0), int(x1), int(y1)]
        print(faction, role, name, "%dx%d" % (x1 - x0, y1 - y0))
    json.dump(crops, open(os.path.join(REPO, "art/fleet/HL_%s_Fleet_Sheet_crops.json" % faction), "w"))


if __name__ == "__main__":
    args = sys.argv[1:]
    for k in range(0, len(args), 2):
        cut(args[k], args[k + 1])
