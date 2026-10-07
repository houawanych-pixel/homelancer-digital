"""crop.py : cut the 12 portraits (6 clean, 6 damaged) out of each enemy roster picture -> out/<faction>_0N_clean.jpg / _damaged.jpg (256 px)
and a check sheet per faction. Boxes are in half-size picture pixels: column centres (clean 3, damaged 3), face-centre y per row, square side."""
import os, sys
from PIL import Image, ImageDraw
SPEC = {   # file: (id prefix, [clean col centres], [damaged col centres], [row centres], side)
    'phenom':      ('phenom',     [58, 163, 271], [384, 490, 597], [258, 415], 100),
    'cybermorphs': ('cybermorph', [58, 163, 271], [384, 490, 597], [258, 415], 100),
    'arctides':    ('arctides',   [58, 163, 271], [384, 490, 597], [258, 415], 100),
    'kaijurai':    ('kaijurai',   [69, 197, 325], [509, 637, 765], [140, 325], 118),
    'solrath':     ('solrath',    [72, 206, 341], [494, 628, 763], [150, 335], 118),
    'gadversee':   ('gadversee',  [74, 208, 342], [494, 626, 760], [152, 312], 118),
}
SPEC.update(eval(open('tune.py').read()) if os.path.exists('tune.py') else {})
os.makedirs('out', exist_ok=True)
for f, (pre, cc, dc, rows, side) in SPEC.items():
    im = Image.open(f + '.png').convert('RGB'); sheet = Image.new('RGB', (6 * 200, 2 * 200))
    for state, cols, sx in (('clean', cc, 0), ('damaged', dc, 0)):
        for slot in range(6):
            cx, cy = cols[slot % 3] * 2, rows[slot // 3] * 2; h = side
            t = im.crop((cx - h, cy - h, cx + h, cy + h)).resize((256, 256), Image.LANCZOS)
            t.save('out/%s_%02d_%s.jpg' % (pre, slot + 1, state), quality=88)
            sheet.paste(t.resize((200, 200)), (slot * 200, 0 if state == 'clean' else 200))
    d = ImageDraw.Draw(sheet); [d.text((k * 200 + 4, 4), '%02d' % (k + 1), fill=(255, 255, 0)) for k in range(6)]
    sheet.save('check_%s.jpg' % f, quality=85)
