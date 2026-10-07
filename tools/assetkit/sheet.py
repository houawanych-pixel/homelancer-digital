"""sheet.py OUT.png COLS LABEL=prefix ... : contact sheet; each cell = top | side | back three-quarter | front three-quarter."""
import sys
from PIL import Image, ImageDraw
out, cols = sys.argv[1], int(sys.argv[2]); items = [a.split('=', 1) for a in sys.argv[3:]]
S = int(__import__("os").environ.get("CELL","300")); V = ('top', 'side', 'q', 'f'); cw, ch = S * len(V) + 8, S + 22
rows = (len(items) + cols - 1) // cols
im = Image.new('RGB', (cols * cw, rows * ch), (20, 22, 28)); d = ImageDraw.Draw(im)
for k, (lab, pre) in enumerate(items):
    x, y = (k % cols) * cw, (k // cols) * ch
    for j, v in enumerate(V):
        try: im.paste(Image.open(pre + '_' + v + '.png').convert('RGB').resize((S, S)), (x + j * S, y + 20))
        except Exception as e: pass
    d.text((x + 4, y + 4), lab + '   [top: -Z up | side from +X: -Z left | 3/4 from +Z end | 3/4 from -Z end]', fill=(255, 230, 120))
im.save(out)
