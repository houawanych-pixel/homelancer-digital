# Cuts each ship out of the owner's fleet roster sheets (HL_<Faction>Fleet_TopDown_*.png, black background) and
# writes crop boxes to fleet_crops.json, plus one transparent PNG token per ship. No new art: these are the sheet's pixels.
# Usage: python3 crop_tokens.py <sheet_dir> <out_dir>
import json, sys, glob, os
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage
def boxes(path):
    im = Image.open(path).convert("RGB"); a = np.asarray(im).astype(int); H, W = a.shape[:2]
    lit = a.max(axis=2) > 40
    lit[: int(H * 0.075)] = False                       # the title banner
    m = ndimage.binary_dilation(lit, iterations=6)
    lab, n = ndimage.label(m)
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        ys, xs = sl; area = (lab[sl] == i + 1).sum()
        h, w = ys.stop - ys.start, xs.stop - xs.start
        if area < 2500 or h < 70: continue               # captions and small bits of text
        out.append({"box": [xs.start, ys.start, xs.stop, ys.stop], "area": int(area), "cx": (xs.start + xs.stop) / 2, "cy": (ys.start + ys.stop) / 2})
    return im, out, W, H
# Which numbered piece of each sheet is which class (read off the sheet's own captions by eye, see README).
# "L" = the left ship of the bomber/fighter pair; "T"/"B" = top/bottom ship when two touch on the sheet.
CLASSES = ["Capital", "Cruiser", "Destroyer", "Resupply", "TroopTransport", "Frigate", "Escort", "Scout", "Bomber"]
MAP = {
    "Covenant": [0, 2, 4, 6, 7, 1, 3, 8, "5L"], "Elyza": [0, 2, 4, 6, 7, 1, 3, 8, "5L"], "Imperium": [0, 2, 4, 5, 7, 1, 3, 8, "6L"],
    "Liberator": ["0T", 2, "0B", 4, 7, 1, 3, 8, 6], "Orion": [0, 2, 4, 5, 8, 1, 3, 9, "6L"], "Savagers": [0, 2, 5, 4, 7, 1, 3, 8, "6L"],
    "Solarion": [0, 2, 4, 5, 7, 1, 3, 8, "6L"], "Unity": [0, 1, 4, 7, 8, 2, 3, 9, 5]}
def ship_only(a, box, part=""):
    """The biggest lit piece inside a box (drops caption text); for a pair, the left or top/bottom piece."""
    x0, y0, x1, y1 = box
    lit = a[y0:y1, x0:x1].max(axis=2) > 40
    lab, n = ndimage.label(ndimage.binary_dilation(lit, iterations=2))
    sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
    order = list(np.argsort(sizes)[::-1] + 1)
    if part in ("L", "T", "B"):
        two = order[:2]; sl = [ndimage.find_objects((lab == k).astype(np.int32))[0] for k in two]
        if part == "L": k = two[0] if sl[0][1].start < sl[1][1].start else two[1]
        elif part == "T": k = two[0] if sl[0][0].start < sl[1][0].start else two[1]
        else: k = two[0] if sl[0][0].start > sl[1][0].start else two[1]
    else: k = order[0]
    ys, xs = ndimage.find_objects((lab == k).astype(np.int32))[0]
    return [x0 + xs.start, y0 + ys.start, x0 + xs.stop, y0 + ys.stop], (lab[ys, xs] == k)
def main(src, dst):
    os.makedirs(dst, exist_ok=True); allc = {}
    for f in sorted(glob.glob(os.path.join(src, "HL_*Fleet_TopDown_*.png"))):
        fac = os.path.basename(f).split("Fleet_")[0][3:]
        im, c, W, H = boxes(f); a3 = np.asarray(im).astype(int); crops = {}
        a = np.asarray(im.convert("RGBA")).copy()
        a[..., 3] = np.clip((a[..., :3].max(axis=2).astype(int) - 18) * 6, 0, 255).astype(np.uint8)
        for cls, pick in zip(CLASSES, MAP[fac]):
            pick = str(pick); idx = int(pick.rstrip("LTB")); part = pick[len(str(idx)):]
            box, keep = ship_only(a3, c[idx]["box"], part)
            x0, y0, x1, y1 = box; t = a[y0:y1, x0:x1].copy(); t[..., 3] = np.where(keep, t[..., 3], 0)
            Image.fromarray(t).save(os.path.join(dst, "%s_%s.png" % (fac.lower(), cls.lower()))); crops[cls] = box
        allc[fac] = {"sheet": os.path.basename(f), "size": [W, H], "crops": crops}
        print(fac, len(crops))
    json.dump(allc, open(os.path.join(dst, "fleet_crops.json"), "w"), indent=1)
if __name__ == "__main__": main(*sys.argv[1:])
