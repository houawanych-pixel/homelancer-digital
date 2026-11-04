"""Draw every system's map from an HL_LAYDUMP json (godot ... HL_LAYDUMP=out.json): one PNG per system and contact
sheets, so the lane networks can be checked by eye. Usage: render_maps.py layout.json out_dir"""
import json, sys, os, math
from PIL import Image, ImageDraw, ImageFont

CELLS = 10
S = 640
M = 30
F = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
FB = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'

def px(c):
    k = (S - 2 * M) / CELLS
    return (M + (c[0] - 1) * k, M + (c[1] - 1) * k)

def rad(r):
    return r * (S - 2 * M) / CELLS

def draw(o):
    im = Image.new('RGBA', (S, S), (6, 10, 18, 255))
    ov = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for cc, r, col, w in o['clouds']:
        x, y = px(cc); rr = rad(r)
        rgb = tuple(int(col[i:i + 2], 16) for i in (0, 2, 4))
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=rgb + (60,), outline=rgb + (140,))
        if w == 'rocks': d.text((x - 12, y - 6), 'rocks', fill=(220, 200, 160, 255), font=ImageFont.truetype(F, 11))
    im = Image.alpha_composite(im, ov)
    d = ImageDraw.Draw(im)
    k = (S - 2 * M) / CELLS
    for i in range(CELLS + 1):
        d.line([(M + i * k, M), (M + i * k, S - M)], fill=(30, 50, 70))
        d.line([(M, M + i * k), (S - M, M + i * k)], fill=(30, 50, 70))
    f = ImageFont.truetype(F, 11); fb = ImageFont.truetype(FB, 15)
    if 'belt' in o:
        x, y = px(o['belt'][0]); rr = rad(o['belt'][1])
        d.ellipse([x - rr, y - rr, x + rr, y + rr], outline=(210, 180, 130), width=2)
    sx, sy = px(o['sun'][0]); sr = max(rad(o['sun'][1]), 6)
    d.ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=(255, 200, 80), outline=(255, 240, 160))
    for a, b in o['lanes']:
        d.line([px(a), px(b)], fill=(90, 200, 255), width=3)
    for n, c in o['junctions']:
        x, y = px(c); d.ellipse([x - 6, y - 6, x + 6, y + 6], fill=(255, 170, 40)); d.text((x + 8, y - 6), n, fill=(255, 190, 90), font=f)
    for n, c, kind in o['gates']:
        x, y = px(c); d.regular_polygon((x, y, 9), 6, fill=(240, 200, 60)); d.text((x + 10, y + 2), n, fill=(240, 210, 90), font=f)
    for n, c, r in o['planets']:
        x, y = px(c); rr = max(rad(r), 5); d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(80, 140, 230)); d.text((x + rr + 3, y - 6), n, fill=(150, 190, 255), font=f)
    hn, hc = o['hub']
    x, y = px(hc); d.rectangle([x - 8, y - 8, x + 8, y + 8], fill=(80, 230, 120)); d.text((x + 10, y - 7), hn, fill=(120, 255, 160), font=f)
    for n, c, fac, hid in o['stations']:
        x, y = px(c); col = (230, 90, 90) if hid else (90, 220, 140)
        d.rectangle([x - 6, y - 6, x + 6, y + 6], fill=col); d.text((x + 8, y - 6), n + (' (hidden)' if hid else ''), fill=col, font=f)
    d.text((8, 6), '%s  %s  %s' % (o['name'], o['tile'], o['faction']), fill=(255, 255, 255), font=fb)
    return im.convert('RGB')

def main():
    lay = json.load(open(sys.argv[1])); out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    ims = []
    for sid in sorted(lay, key=lambda k: lay[k]['tile']):
        im = draw(lay[sid]); im.save(os.path.join(out, sid + '.png')); ims.append(im)
    per = 12; cols = 4; t = 480
    for s in range(0, len(ims), per):
        ch = ims[s:s + per]; rows = (len(ch) + cols - 1) // cols
        sheet = Image.new('RGB', (cols * t, rows * t), (0, 0, 0))
        for i, im in enumerate(ch): sheet.paste(im.resize((t, t)), ((i % cols) * t, (i // cols) * t))
        sheet.save(os.path.join(out, 'sheet_%02d.png' % (s // per + 1)))
    print(len(ims), 'maps')

main()
