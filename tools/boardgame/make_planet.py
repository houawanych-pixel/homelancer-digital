# Homelancer tabletop: a world's surface map on 4 x 6 in cards (300 dpi), drawn from the game's own top-down captures.
# 3 x 3 world: two portrait cards side by side (8 x 6 in): the 6 x 6 in map (2 in a sector) + a 2 in side panel.
# 2 x 2 world: one landscape card (6 x 4): 4 x 4 in map + panel. 1-tile world: one portrait card: 4 x 4 in map + panel.
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
ART = os.environ.get("HL_PLANET_ART", "/tmp/claude-0/pl")
HOLO = os.environ.get("HL_BOARD_HOLO", "/tmp/claude-0/board/wire")
# a dock is drawn with its side's own base model (the game's dock is a plain landing pad)
DOCK_MODEL = {"Unity": "HL_Base_Unity_Hangar", "Elyza": "HL_Base_Elyza_CrystalCourt", "Imperium": "HL_Base_Imperium_Bastion", "Liberator": "HL_Base_Liberator_Outpost"}
OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
SYSTEM, GALAXY = os.environ.get("HL_SYS_NAME", "SOLARA"), os.environ.get("HL_SYS_TILE", "F3")
F = "/usr/share/fonts/opentype/inter/"
def fnt(n, sz): return ImageFont.truetype(F + n, int(sz))
CY = (95, 215, 255)
FAC_COL = {"Unity": (90, 190, 255), "Liberator": (110, 230, 170), "Imperium": (240, 90, 90), "Elyza": (255, 170, 80), "Savagers": (230, 120, 60), "Covenant": (200, 150, 255), "Orion": (255, 220, 110), "Solarion": (255, 200, 90)}
info = json.load(open(ART + "/planets.json"))
def stroke_text(d, xy, t, f, col, anchor="la", sw=3):
    d.text(xy, t, font=f, fill=col, anchor=anchor, stroke_width=sw, stroke_fill=(0, 0, 0))
def hexagon(cx, cy, R, rot=0.0): return [(cx + R * math.cos(rot + i * math.tau / 6), cy + R * math.sin(rot + i * math.tau / 6)) for i in range(6)]

def map_image(pid, P, sector_px):
    g = P["grid"]; M = g * sector_px
    im = Image.new("RGB", (M, M), (0, 0, 0))
    for t in range(g * g):
        s = Image.open(f"{ART}/surf_{pid}_{t}.png").convert("RGB").resize((sector_px, sector_px), Image.LANCZOS)
        im.paste(s, ((t % g) * sector_px, (t // g) * sector_px))
    im = im.convert("RGBA"); d = ImageDraw.Draw(im)
    k = sector_px / P["tile_m"]
    def at(tile, x, y): return ((tile % g) * sector_px + sector_px / 2 + x * k, (tile // g) * sector_px + sector_px / 2 + y * k)
    # sector grid + names (row letter, column number: the game's own sector names)
    for i in range(g + 1):
        d.line([(i * sector_px, 0), (i * sector_px, M)], fill=(225, 245, 255, 220), width=3)
        d.line([(0, i * sector_px), (M, i * sector_px)], fill=(225, 245, 255, 220), width=3)
    fs = fnt("InterDisplay-Bold.otf", 34); fb = fnt("Inter-SemiBold.otf", 22)
    for t in range(g * g):
        x0, y0 = (t % g) * sector_px, (t // g) * sector_px
        stroke_text(d, (x0 + 16, y0 + 12), "ABCDEFG"[t // g] + str(t % g + 1), fs, (240, 250, 255))
        stroke_text(d, (x0 + 16, y0 + 54), P["tiles"][t]["name"].upper(), fb, CY)
    def holo(file, x, y, wpx, col):   # the model as a hologram in its side's colour, with a soft shadow
        p = f"{HOLO}/{file}.png"
        if not os.path.exists(p): return 0, 0
        im = Image.open(p).convert("RGBA"); k = wpx / max(im.width, im.height)
        im = im.resize((int(im.width * k), int(im.height * k)), Image.LANCZOS)
        r_, g_, b_, a_ = im.split(); lum = Image.merge("RGB", (r_, g_, b_)).convert("L").point(lambda v: min(255, int(v * 1.5)))
        im = Image.merge("RGBA", [lum.point(lambda v, c=c: int(v * (0.35 + 0.65 * c / 255))) for c in col] + [a_])
        sh = Image.new("RGBA", im.size, (0, 0, 0, 0)); sh.paste((0, 0, 0, 170), (0, 0), a_); sh = sh.filter(ImageFilter.GaussianBlur(8))
        im_x, im_y = int(x - im.width / 2), int(y - im.height * 0.62)
        base.alpha_composite(sh, (im_x + 8, im_y + 12)); base.alpha_composite(im, (im_x, im_y))
        return im.width, im.height
    base = im
    # facilities: the building as a hologram, a square with its level (the dungeon), coloured by its side
    ff = fnt("InterDisplay-Bold.otf", 30); fl = fnt("Inter-SemiBold.otf", 19)
    for f in P["facilities"]:
        x, y = at(f["tile"], f["x"], f["y"]); col = FAC_COL.get(f["faction"], (230, 230, 230)); R = 24
        hw, hh = holo(f.get("model", ""), x, y, sector_px * 0.3, col)
        d = ImageDraw.Draw(im)
        bx, by = x - hw * 0.5, y - hh * 0.62
        d.rectangle([bx - R, by - R, bx + R, by + R], fill=(10, 14, 22, 235), outline=col + (255,), width=5)
        d.text((bx, by + 1), str(f["level"]), font=ff, fill=col, anchor="mm")
        y = y + hh * 0.38 - R
        near = any(l["tile"] == f["tile"] and math.hypot(l["x"] - f["x"], l["y"] - f["y"]) * k < 140 for l in P["locations"])
        nm = f["name"].replace(P["name"] + " ", "").replace("Solara Haven ", "").upper()
        if near:   # (a dock right by it: the name goes to the side)
            stroke_text(d, (x + R + 10, y - 14), nm, fl, (240, 248, 255), "lm")
            stroke_text(d, (x + R + 10, y + 10), "%s FACILITY · LV %d" % (f["faction"].upper(), f["level"]), fnt("Inter-SemiBold.otf", 15), col, "lm")
        else:
            stroke_text(d, (x, y + R + 8), nm, fl, (240, 248, 255), "ma")
            stroke_text(d, (x, y + R + 32), "%s FACILITY · LV %d" % (f["faction"].upper(), f["level"]), fnt("Inter-SemiBold.otf", 15), col, "ma")
    # docks: hexagon, coloured by side
    for l in P["locations"]:
        x, y = at(l["tile"], l["x"], l["y"]); col = FAC_COL.get(l["faction"], (230, 230, 230)); R = 26
        crowded = any(f["tile"] == l["tile"] and math.hypot(l["x"] - f["x"], l["y"] - f["y"]) * k < 160 for f in P["facilities"])
        hw, hh = (sector_px * 0.3, sector_px * 0.2) if crowded else holo(DOCK_MODEL.get(l["faction"], "HL_Base_Unity_Hangar"), x, y, sector_px * 0.32, col)
        if crowded: x, y = x - sector_px * 0.3, y - sector_px * 0.02   # (a facility stands right there: the dock's mark sits beside it)
        d = ImageDraw.Draw(im)
        hx, hy = x + hw * 0.5, y - hh * 0.62
        d.polygon(hexagon(hx, hy, R), fill=(10, 14, 22, 235), outline=col + (255,), width=5)
        d.polygon(hexagon(hx, hy, R * 0.45, math.pi / 6), fill=col + (255,))
        y = y - hh * 0.62 + R
        stroke_text(d, (x, y - R - 34), l["name"].upper(), fnt("InterDisplay-Bold.otf", 21), (240, 248, 255), "ma")
        stroke_text(d, (x, y - R - 12), "%s DOCK" % l["faction"].upper(), fnt("Inter-SemiBold.otf", 15), col, "ma")
    d.rectangle([0, 0, M - 1, M - 1], outline=(225, 245, 255, 255), width=5)
    return im

def panel(P, W, H, size_word):
    p = Image.new("RGBA", (W, H), (6, 12, 26, 255)); d = ImageDraw.Draw(p)
    for y in range(0, H, 40): d.line([(0, y), (W, y)], fill=(12, 34, 60))
    for x in range(0, W, 40): d.line([(x, 0), (x, H)], fill=(12, 34, 60))
    y = 40
    d.text((30, y), P["name"].upper(), font=fnt("InterDisplay-Bold.otf", 52 if len(P["name"]) < 12 else 40), fill=(240, 250, 255)); y += 70
    d.text((30, y), f"{SYSTEM} · GALAXY {GALAXY}", font=fnt("Inter-SemiBold.otf", 22), fill=CY); y += 36
    d.text((30, y), f"{size_word} WORLD · {P['grid']}x{P['grid']} MAP" if P["grid"] > 1 else f"{size_word} WORLD · 1-SECTOR MAP", font=fnt("Inter-SemiBold.otf", 22), fill=CY); y += 60
    fh = fnt("InterDisplay-Bold.otf", 26); fr = fnt("Inter-SemiBold.otf", 20)
    d.text((30, y), "KEY", font=fh, fill=(240, 250, 255)); y += 44
    d.polygon(hexagon(52, y + 14, 18), outline=CY, width=4); d.text((86, y), "Dock: land, repair, missions", font=fr, fill=(220, 235, 250)); y += 46
    d.rectangle([36, y, 68, y + 30], outline=(240, 90, 90), width=4); d.text((52, y + 15), "2", font=fnt("InterDisplay-Bold.otf", 20), fill=(240, 90, 90), anchor="mm")
    d.text((86, y), "Facility (dungeon), level 1-4", font=fr, fill=(220, 235, 250)); y += 54
    d.text((30, y), "SIDES", font=fh, fill=(240, 250, 255)); y += 44
    for fct in sorted(set([l["faction"] for l in P["locations"]] + [f["faction"] for f in P["facilities"]])):
        col = FAC_COL.get(fct, (230, 230, 230)); d.rectangle([36, y + 4, 60, y + 28], fill=col); d.text((76, y + 2), fct.upper(), font=fr, fill=(220, 235, 250)); y += 38
    y += 20
    d.text((30, y), "SECTORS", font=fh, fill=(240, 250, 255)); y += 44
    for t, tl in enumerate(P["tiles"]):
        d.text((30, y), "ABCDEFG"[t // P["grid"]] + str(t % P["grid"] + 1), font=fnt("InterDisplay-Bold.otf", 20), fill=CY)
        d.text((86, y), tl["name"], font=fr, fill=(220, 235, 250)); y += 32
    d.text((W - 30, H - 86), "HOMELANCER", font=fnt("InterDisplay-Bold.otf", 34), fill=(240, 250, 255), anchor="ra")
    d.text((W - 30, H - 44), "homelancergame.com", font=fnt("Inter-SemiBold.otf", 19), fill=CY, anchor="ra")
    return p

SIZE = {1: "SMALL", 2: "MEDIUM", 3: "LARGE"}
os.makedirs(OUT, exist_ok=True)
for pid, P in info.items():
    g = P["grid"]; code = pid.upper().replace("SOLARA_", "")[:6]
    cards = []
    if g == 3:   # 8 x 6 in, two portrait cards side by side
        W, H = 2400, 1800
        sheet = Image.new("RGBA", (W, H), (6, 12, 26, 255))
        sheet.paste(map_image(pid, P, 600), (0, 0))
        sheet.paste(panel(P, 600, H, SIZE[g]), (1800, 0))
        parts = [(0, 0, 1200, 1800), (1200, 0, 2400, 1800)]
    elif g == 2:   # one landscape card, 6 x 4: 4 x 4 map + panel
        W, H = 1800, 1200
        sheet = Image.new("RGBA", (W, H), (6, 12, 26, 255))
        sheet.paste(map_image(pid, P, 600), (0, 0)); sheet.paste(panel(P, 600, H, SIZE[g]), (1200, 0))
        parts = [(0, 0, 1800, 1200)]
    else:          # one portrait card, 4 x 6: map on top, panel under it
        W, H = 1200, 1800
        sheet = Image.new("RGBA", (W, H), (6, 12, 26, 255))
        sheet.paste(map_image(pid, P, 1200), (0, 0))
        pn = panel(P, 1200, 600, SIZE[g])
        sheet.paste(pn, (0, 1200))
        parts = [(0, 0, 1200, 1800)]
    sheet = sheet.convert("RGB")
    sheet.save(f"{OUT}/{pid}_map_full.png", dpi=(300, 300))
    for i, b in enumerate(parts):
        c = sheet.crop(b); cd = ImageDraw.Draw(c)
        lab = f"{P['name'].upper()} {i + 1} OF {len(parts)} · HL-{code}-{i + 1:02d}"
        cd.text((c.width - 24 if i == len(parts) - 1 and g == 3 else 24, c.height - 16), lab, font=fnt("Inter-SemiBold.otf", 18), fill=(130, 210, 255), anchor="rd" if (i == len(parts) - 1 and g == 3) else "ld", stroke_width=2, stroke_fill=(0, 0, 0))
        c.save(f"{OUT}/{pid}_card_{i + 1}_of_{len(parts)}.png", dpi=(300, 300)); cards.append(c)
    cards[0].save(f"{OUT}/{pid}_cards.pdf", save_all=True, append_images=cards[1:], resolution=300)
print("ok")
