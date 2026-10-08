"""overview.py SET OUT.jpg : one cell per split piece (top view | three-quarter view), numbered, biggest first."""
import sys, glob, os
from PIL import Image, ImageDraw, ImageFont
X, out = sys.argv[1], sys.argv[2]; fs = sorted(glob.glob('%s/view/c*_top.png' % X)); S = 220; cols = 4 if len(fs) > 9 else 3
rows = (len(fs) + cols - 1) // cols; im = Image.new('RGB', (cols * (2 * S + 6), rows * (S + 6)), (20, 22, 28)); d = ImageDraw.Draw(im)
try: fnt = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 26)
except Exception: fnt = None
for k, f in enumerate(fs):
    x, y = (k % cols) * (2 * S + 6), (k // cols) * (S + 6)
    im.paste(Image.open(f).convert('RGB').resize((S, S)), (x, y)); im.paste(Image.open(f.replace('_top', '_q')).convert('RGB').resize((S, S)), (x + S, y))
    d.text((x + 6, y + 4), str(k), fill=(255, 230, 90), font=fnt)
im.save(out, quality=85)
