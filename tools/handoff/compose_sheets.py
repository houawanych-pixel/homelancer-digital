"""Compose front/side/back (top row) + top view under side into one reference sheet with alignment guides.
usage: python3 compose_sheets.py <views_dir> <out_dir>"""
import sys, os, json
from PIL import Image, ImageDraw, ImageFont
src, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
V = json.load(open(os.path.join(src, 'views.json')))
try: F = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 18); FS = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 14)
except Exception: F = FS = ImageFont.load_default()
for key, m in V.items():
    P = m['px']; s = P / m['ortho_size']; cx, cy, cz = m['center']; sx, sy, sz = m['size']
    pad = 40; head = 50
    W, H = pad + 3 * (P + pad), head + 2 * (P + pad) + 30
    sheet = Image.new('RGB', (W, H), (24, 25, 28)); d = ImageDraw.Draw(sheet)
    pos = {'front': (pad, head), 'side': (pad * 2 + P, head), 'back': (pad * 3 + 2 * P, head), 'top': (pad * 2 + P, head + P + pad)}
    for v, (x, y) in pos.items():
        p = os.path.join(src, '%s_%s.png' % (key, v))
        if os.path.exists(p): sheet.paste(Image.open(p).convert('RGB'), (x, y))
        d.rectangle([x, y, x + P, y + P], outline=(90, 95, 105))
        d.text((x + 6, y + 4), v.upper(), fill=(230, 230, 230), font=F)
    # same scale everywhere: half-extents in pixels
    hy, hx, hz = sy / 2 * s, sx / 2 * s, sz / 2 * s
    mid = P / 2
    G1, G2 = (255, 210, 60), (70, 200, 255)
    top_y = head + mid - hy; bot_y = head + mid + hy; cen_y = head + mid
    for yy, col in ((top_y, G1), (bot_y, G1), (cen_y, G2)):          # height guides across front / side / back
        for xx in range(pad, W - pad, 12): d.line([xx, yy, xx + 6, yy], fill=col, width=1)
    sx0 = pos['side'][0]
    for xx, col in ((sx0 + mid - hz, G1), (sx0 + mid + hz, G1), (sx0 + mid, G2)):   # length guides: side down to top
        for yy in range(head, H - 40, 12): d.line([xx, yy, xx, yy + 6], fill=col, width=1)
    fx0 = pos['front'][0]; bx0 = pos['back'][0]
    for x0 in (fx0, bx0):                                              # width guides on front/back
        for xx in (x0 + mid - hx, x0 + mid + hx):
            for yy in range(head, head + P, 12): d.line([xx, yy, xx, yy + 6], fill=G1, width=1)
    tx0, ty0 = pos['top']                                              # width guides on top view
    for yy in (ty0 + mid - hx, ty0 + mid + hx):
        for xx in range(tx0, tx0 + P, 12): d.line([xx, yy, xx + 6, yy], fill=G1, width=1)
    d.text((pad, 12), '%s   bounds (file units, after game yaw %s deg): width X %.3f  height Y %.3f  length Z %.3f   |   same orthographic scale in all views: %.1f px per unit   |   nose = -Z (points right in SIDE and TOP)' % (key, m['yaw'], sx, sy, sz, s), fill=(240, 240, 240), font=FS)
    d.text((pad, H - 28), 'yellow dashes = bounding box edges, blue dashes = bounding box centre. Views are rendered from the same game file, not redrawn.', fill=(180, 180, 180), font=FS)
    lx, ly = pos['front'][0], head + P + pad                           # legend box under FRONT
    sheet.save(os.path.join(out, key + '_reference_sheet.png'))
print(len(V), 'sheets')
