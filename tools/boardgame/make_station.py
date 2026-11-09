# Homelancer tabletop: a station card (4 x 6 in portrait, 300 dpi): its model as a hologram, its rooms from the game.
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
HOLO = os.environ.get("HL_BOARD_HOLO", "/tmp/claude-0/board/wire")
ROOMS = os.environ.get("HL_ROOMS", "/home/claude/homelancer-digital/assets/rooms/loc")
OUT = sys.argv[1] if len(sys.argv) > 1 else "sout"
F = "/usr/share/fonts/opentype/inter/"
def fnt(n, sz): return ImageFont.truetype(F + n, int(sz))
CY = (95, 215, 255)
FAC_COL = {"Unity": (90, 190, 255), "Liberator": (110, 230, 170), "Imperium": (240, 90, 90)}
SYSTEM, GALAXY = "SOLARA", "F3"
# (name, faction, role, where on the board, holo, room prefix, game description, hidden)
STATIONS = [
  ("Liberty Hub", "Unity", "Home station · start here", "F6 · card 5", "hub.png", "solara_libertyhub", "Unity trade and patrol hub. Repairs, outfitting and a ship dealer.", False),
  ("Liberator Freeport", "Liberator", "Ally station · mech shop", "H7 · card 6", "freeport.png", "solara_liberatorfreeport", "Liberator freeport: Unity's allies run a fuel depot, a mech shop and a clinic for pilots passing through.", False),
  ("Haven Station", "Unity", "Trade station", "B8 · card 4", "haven.png", "solara_havenstation", "Unity's west corner station by Haven: ice haulers, a repair dock and a quiet bar for new pilots.", False),
  ("Imperium Watch Post", "Imperium", "Rival station · hidden", "B2 · card 1, inside the Violet Reach", "watchpost.png", "solara_imperiumwatchpost", "An Imperium watch post hidden in the Violet Reach: it sends the raids on Solara's lanes.", True),
]
ROOM_USE = [("hub", "HUB", "Mission board · command · nav map"), ("hangar", "HANGAR", "Shipyard · mechs · weapons · loadout"),
            ("lounge", "LOUNGE", "Pilots' lounge: talk to people"), ("supplies", "SUPPLIES", "Repair & ammo · medical bay")]
def wrap(d, text, f, w):
    out, line = [], ""
    for wd in text.split():
        t = (line + " " + wd).strip()
        if d.textlength(t, font=f) > w: out.append(line); line = wd
        else: line = t
    return out + [line]
os.makedirs(OUT, exist_ok=True)
cards = []
for i, (name, fac, role, where, holo, rp, desc, hidden) in enumerate(STATIONS):
    W, H = 1200, 1800
    c = Image.new("RGBA", (W, H), (6, 12, 26, 255)); d = ImageDraw.Draw(c)
    for y in range(0, H, 40): d.line([(0, y), (W, y)], fill=(11, 30, 55))
    for x in range(0, W, 40): d.line([(x, 0), (x, H)], fill=(11, 30, 55))
    col = FAC_COL.get(fac, CY)
    # header
    d.rectangle([0, 0, W, 150], fill=(8, 20, 40, 255)); d.line([(0, 150), (W, 150)], fill=col, width=4)
    d.text((40, 30), name.upper(), font=fnt("InterDisplay-Bold.otf", 64 if len(name) < 16 else 52), fill=(240, 250, 255))
    d.text((40, 106), f"{fac.upper()} · {role.upper()}", font=fnt("Inter-SemiBold.otf", 26), fill=col)
    # the model
    im = Image.open(f"{HOLO}/{holo}").convert("RGBA"); im.thumbnail((980, 640), Image.LANCZOS)
    glow = Image.new("RGBA", c.size, (0, 0, 0, 0)); gd = ImageDraw.Draw(glow)
    gd.ellipse([W / 2 - 430, 520 - 250, W / 2 + 430, 520 + 250], fill=col + (60,)); glow = glow.filter(ImageFilter.GaussianBlur(90))
    c.alpha_composite(glow)
    c.alpha_composite(im, (int(W / 2 - im.width / 2), int(500 - im.height / 2)))
    d = ImageDraw.Draw(c)
    d.text((W - 40, 790), f"{SYSTEM} · {where.upper()}", font=fnt("Inter-SemiBold.otf", 22), fill=CY, anchor="ra")
    # the game's description
    y = 840
    for ln in wrap(d, desc, fnt("Inter-SemiBold.otf", 30), W - 80): d.text((40, y), ln, font=fnt("Inter-SemiBold.otf", 30), fill=(225, 238, 250)); y += 42
    y += 18
    # its four rooms (the game's own pictures)
    tw, th = 540, 260
    for k, (rk, rt, use) in enumerate(ROOM_USE):
        x0 = 40 + (k % 2) * (tw + 40); y0 = y + (k // 2) * (th + 92)
        p = f"{ROOMS}/{rp}_{rk}.jpg"
        if os.path.exists(p):
            pan = Image.open(p).convert("RGB"); ph = pan.height; pw = int(ph * tw / th)
            x = (pan.width - pw) // 2; thumb = pan.crop((x, 0, x + pw, ph)).resize((tw, th), Image.LANCZOS)
            c.paste(thumb, (x0, y0))
        d.rectangle([x0, y0, x0 + tw, y0 + th], outline=col, width=3)
        d.text((x0 + 14, y0 + 10), rt, font=fnt("InterDisplay-Bold.otf", 30), fill=(240, 250, 255), stroke_width=4, stroke_fill=(0, 0, 0))
        d.text((x0, y0 + th + 10), use, font=fnt("Inter-SemiBold.otf", 22), fill=CY)
    if hidden:   # found only by flying into its nebula
        d.rectangle([40, H - 210, W - 40, H - 120], fill=(60, 10, 14, 255), outline=(240, 90, 90), width=3)
        d.text((W / 2, H - 165), "HIDDEN: keep face down until found in the Violet Reach", font=fnt("InterDisplay-Bold.otf", 27), fill=(255, 210, 210), anchor="mm")
    d.text((40, H - 50), f"HL-{SYSTEM[:3]}-ST{i + 1:02d}", font=fnt("Inter-SemiBold.otf", 20), fill=(130, 210, 255))
    d.text((W - 40, H - 86), "HOMELANCER", font=fnt("InterDisplay-Bold.otf", 34), fill=(240, 250, 255), anchor="ra")
    d.text((W - 40, H - 44), "homelancergame.com", font=fnt("Inter-SemiBold.otf", 19), fill=CY, anchor="ra")
    c = c.convert("RGB"); c.save(f"{OUT}/station_{i + 1}.png", dpi=(300, 300)); cards.append(c)
cards[0].save(f"{OUT}/solara_station_cards.pdf", save_all=True, append_images=cards[1:], resolution=300)
sheet = Image.new("RGB", (2400, 900), (0, 0, 0))
for i, c in enumerate(cards): sheet.paste(c.resize((600, 900)), (i * 600, 0))
sheet.save(f"{OUT}/station_cards_preview.jpg", quality=90)
print("ok")
