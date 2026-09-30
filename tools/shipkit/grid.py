# grid.py sheet.png out.png W views... : overlay model-coordinate grid on orthographic studio shots
import sys
from PIL import Image, ImageDraw
src, out, W = sys.argv[1], sys.argv[2], int(sys.argv[3])
cx, cy, cz, size = [float(v) for v in sys.argv[4].split(",")]
views = sys.argv[5].split(";")   # per shot: "h,v" axes as e.g. "z,y" or "-z,y" or "x,-z"
im = Image.open(src).convert("RGB"); d = ImageDraw.Draw(im)
C = {"x": cx, "y": cy, "z": cz}
for k, vw in enumerate(views):
    ha, va = vw.split(",")
    for axis, horiz in ((ha, True), (va, False)):
        sgn = -1 if axis.startswith("-") else 1; a = axis[-1]
        STEP = float(__import__('os').environ.get('GSTEP', '0.025'))
        for i in range(-60, 61):
            val = round(C[a] + i * STEP, 3)
            off = (val - C[a]) / size * W * sgn
            pix = W / 2 + off if horiz else W / 2 - off
            if not (0 <= pix < W): continue
            col = (255, 200, 80) if i % 2 == 0 else (90, 90, 120)
            if horiz:
                d.line([(k * W + pix, 0), (k * W + pix, W)], fill=col, width=1)
                if i % 2 == 0: d.text((k * W + pix + 2, 2), "%s%.2f" % (a, val), fill=(255, 220, 120))
            else:
                d.line([(k * W, pix), (k * W + W, pix)], fill=col, width=1)
                if i % 2 == 0: d.text((k * W + 2, pix + 2), "%s%.2f" % (a, val), fill=(120, 220, 255))
im.save(out)
