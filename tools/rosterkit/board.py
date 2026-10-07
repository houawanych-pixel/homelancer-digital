"""board.py rosters.json shipdir portraitdir OUT_PREFIX : overview sheets, one row per faction: who they are, their level, and the ship they fly."""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageEnhance
d = json.load(open(sys.argv[1])); SD, PD, OUT = sys.argv[2], sys.argv[3], sys.argv[4]
B = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'; R = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
fb = lambda s: ImageFont.truetype(B, s); fr = lambda s: ImageFont.truetype(R, s)
CW, CH, HEAD = 250, 330, 54
def sheet(name, title, facs):
    im = Image.new('RGB', (6 * CW + 20, HEAD + len(facs) * (CH + 50) + 10), (14, 16, 22)); dr = ImageDraw.Draw(im)
    dr.text((14, 10), title, font=fb(30), fill=(255, 220, 60))
    for r, f in enumerate(facs):
        v = d[f]; y0 = HEAD + r * (CH + 50); flying = any(p['ship_key'] for p in v['pilots'])
        dr.rectangle((0, y0, im.size[0], y0 + 40), fill=(40, 20, 24) if v['enemy'] else (20, 30, 46))
        dr.text((14, y0 + 6), '%s  —  %s' % (f.upper(), v['title'] or ''), font=fb(24), fill=(255, 255, 255))
        tag = ('ENEMY FACTION' if v['enemy'] else 'MAIN FACTION') + ('   ·   FLYING IN THE GAME' if flying else '   ·   NO SHIPS IN THE GAME YET')
        dr.text((im.size[0] - 14 - dr.textlength(tag, font=fr(18)), y0 + 11), tag, font=fr(18), fill=(120, 255, 150) if flying else (255, 150, 120))
        for k, p in enumerate(v['pilots']):
            x = 10 + k * CW; y = y0 + 48
            try: im.paste(Image.open('%s/%s_clean.jpg' % (PD, p['id'])).convert('RGB').resize((150, 150), Image.LANCZOS), (x, y))
            except Exception: dr.rectangle((x, y, x + 150, y + 150), outline=(90, 90, 90))
            dr.text((x + 158, y + 2), 'LV %d' % p['slot'], font=fb(26), fill=(255, 220, 60))
            if p['ship_key']:
                t = Image.open('%s/ship_%s.png' % (SD, p['ship_key'])).convert('RGB').resize((84, 84), Image.LANCZOS)
                im.paste(ImageEnhance.Brightness(t).enhance(2.2), (x + 158, y + 62))
            nm = p['name']; f1 = fb(19 if len(nm) < 19 else 16)
            dr.text((x, y + 156), nm, font=f1, fill=(255, 255, 255))
            role = p['role']; role = role if len(role) < 29 else role[:27] + '…'
            dr.text((x, y + 182), role, font=fr(15), fill=(180, 190, 205))
            dr.text((x, y + 206), 'Ship: ' + (p['ship'] or 'none yet'), font=fr(15), fill=(120, 255, 150) if p['ship'] else (255, 150, 120))
    im.save('%s_%s.png' % (OUT, name)); print(name, im.size)
main = [f for f in d if not d[f]['enemy']]; enemy = [f for f in d if d[f]['enemy']]
fly = lambda f: any(p['ship_key'] for p in d[f]['pilots'])
sheet('1_flying', 'HOMELANCER v1.4z — pilots flying now, with their ships', [f for f in main + enemy if fly(f)])
sheet('2_main_waiting', 'Main factions waiting for ships', [f for f in main if not fly(f)])
sheet('3_enemy_waiting', 'Enemy factions waiting for ships', [f for f in enemy if not fly(f)])
