"""sheet6.py SET OUT.jpg : one row per piece: top | +X side | -X side | +Z | -Z | 3/4, numbered."""
import sys, glob
from PIL import Image, ImageDraw, ImageFont
X, out = sys.argv[1], sys.argv[2]; fs = sorted(glob.glob('%s/v6/c*_top.png' % X)); S = 200
V = ['top', 'side', 'lx', 'fz', 'bz', 'q']
im = Image.new('RGB', (6 * (S + 4), len(fs) * (S + 4)), (20, 22, 28)); d = ImageDraw.Draw(im)
fnt = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 22)
for k, f in enumerate(fs):
    for j, v in enumerate(V):
        im.paste(Image.open(f.replace('_top', '_' + v)).convert('RGB').resize((S, S)), (j * (S + 4), k * (S + 4)))
    d.text((6, k * (S + 4) + 4), f.split('/')[-1][:3], fill=(255, 230, 90), font=fnt)
im.save(out, quality=85)
