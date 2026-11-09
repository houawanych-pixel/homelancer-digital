# Homelancer tabletop: one star system as a 12 x 12 in board cut into six 4 x 6 in cards (300 dpi).
# Everything placed from the game's own layout (Data.SYSTEM_LAYOUT, map squares A-J x 1-10).
import math, random, sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
SKY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../assets/sky/solara.jpg") if os.path.exists(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../assets/sky/solara.jpg")) else "/home/claude/homelancer-digital/assets/sky/solara.jpg"
import os
ARTDIR = os.environ.get("HL_BOARD_ART", "/tmp/claude-0/art")      # HL_BOARDART captures (art.json + art_*.png)
HOLO = os.environ.get("HL_BOARD_HOLO", "/tmp/claude-0/board/wire")  # holo.py renders of the station / gate models
F = "/usr/share/fonts/opentype/inter/"
S = 2                      # draw at 2x, shrink at the end (smooth lines)
B = 3600 * S               # board px
Q = B / 10                 # one map square
def P(x, y): return ((x - 1) * Q, (y - 1) * Q)   # game map coords (1..11) -> px
def fnt(n, sz): return ImageFont.truetype(F + n, int(sz * S))
CY = (95, 215, 255)

SYS = {"name": "SOLARA", "galaxy": "F3", "code": "SOL", "sun": (4.0, 4.0), "sun_col": (255, 219, 153),
  "planets": [("New Terra", (7.6, 3.4), 0.3, (90, 160, 120), "Large world · 3x3 map"), ("Haven", (2.62, 8.96), 0.16, (170, 210, 235), "Small ice world · 1 map")],
  "stations": [("Liberty Hub", (6.0, 6.0), "Unity · Home"), ("Liberator Freeport", (8.6, 7.2), "Liberator · Mech shop"), ("Haven Station", (2.4, 8.2), "Unity · Trade")],
  "gates": [("Jump Gate · Vega", (6.2, 2.25)), ("Jump Gate · Veranthos", (5.6, 9.0))],
  "warp": [("Warp Gate · Void System", (3.21, 3.38))],
  "belt": ("Solara Belt", (4.4, 5.6), 0.5),
  "junctions": [("North Choke Point", (6.9, 4.7)), ("Liberty Crossing", (6.6, 7.7))],
  "clouds": [("Outer Drift", (10.0, 5.0), 26000, "rocks", (158, 148, 140)), ("Ash Wisps", (1.0, 8.4), 24000, "storm", (128, 115, 191)),
    ("Liberty Haze", (7.4, 8.6), 22000, "storm", (89, 153, 242)), ("North Veil", (4.9, 2.4), 30000, "storm", (153, 89, 230)),
    ("Ion Shoals", (9.0, 2.0), 22000, "rocks", (140, 153, 178)), ("Lantern Cloud", (4.6, 6.9), 20000, "storm", (242, 178, 102)),
    ("Crossing Rocks", (4.9, 8.6), 16000, "rocks", (153, 133, 115)), ("Frost Veil", (2.6, 4.5), 70000, "storm", (115, 178, 242)),
    ("Violet Reach", (2.8, 2.6), 79200, "storm", (140, 64, 217))],   # the system's own nebula (480 x NEBULA_SIZE)
  "lanes": [("hub", "North Choke Point"), ("North Choke Point", "New Terra"), ("North Choke Point", "Liberator Freeport"),
    ("New Terra", "Jump Gate · Vega"), ("hub", "Liberty Crossing"), ("Liberty Crossing", "Jump Gate · Veranthos"),
    ("Liberty Crossing", "Liberator Freeport"), ("Liberty Crossing", "Haven Station"), ("Haven Station", "Jump Gate · Veranthos")]}
SQ_M = 100000.0   # metres per map square

pts = {"hub": SYS["stations"][0][1]}
for n, p, *_ in SYS["planets"] + SYS["stations"] + SYS["gates"] + SYS["junctions"]: pts[n] = p

# ---- 1. sky: a square of the system's panorama, darkened, faded to deep space at the board's edge
sky = Image.open(SKY).convert("RGB")
h = sky.height; x0 = (sky.width - h) // 2
sky = sky.crop((x0, 0, x0 + h, h)).resize((B, B), Image.LANCZOS).filter(ImageFilter.GaussianBlur(2 * S))
sky = Image.eval(sky, lambda v: int(v * 0.72))
EDGE = (4, 8, 20)
fade = Image.new("L", (B, B), 0)
fd = ImageDraw.Draw(fade)
fw = int(Q * 0.85)
for i in range(fw):
    a = int(255 * (1 - i / fw) ** 1.6)
    fd.rectangle([i, i, B - 1 - i, B - 1 - i], outline=a)
board = Image.composite(Image.new("RGB", (B, B), EDGE), sky, fade).convert("RGBA")

# ---- 2. clouds: soft noise puffs in the cloud's colour (nebulae block line of sight)
rng = random.Random(7)
def puff_layer(cx, cy, r, col, alpha, rocks):
    lay = Image.new("RGBA", (B, B), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    n = int(18 + r / Q * 30)
    for k in range(n):
        a = rng.random() * math.tau; dd = r * math.sqrt(rng.random()) * 0.85
        pr = r * rng.uniform(0.28, 0.55)
        px, py = cx + math.cos(a) * dd, cy + math.sin(a) * dd
        d.ellipse([px - pr, py - pr, px + pr, py + pr], fill=col + (int(alpha * rng.uniform(0.35, 0.8)),))
    lay = lay.filter(ImageFilter.GaussianBlur(r * 0.22))
    return lay
import numpy as np
def fractal(n, seed):
    g = np.random.default_rng(seed); out = np.zeros((n, n))
    amp = 1.0; tot = 0
    for o in range(6):
        k = 3 * 2 ** o
        z = g.random((k, k))
        out += np.array(Image.fromarray((z * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC), float) / 255 * amp
        tot += amp; amp *= 0.55
    return out / tot
def real_cloud(cx, cy, r, col, strength, seed):
    n = int(r * 3.2); n -= n % 2
    f = fractal(n, seed)
    yy, xx = np.mgrid[0:n, 0:n]; d = np.hypot(xx - n / 2, yy - n / 2) / r
    fall = np.clip(1.0 - (d - 0.6) / 0.95, 0, 1) ** 1.5          # full inside, fading out past the circle
    dens = (0.3 + 0.7 * np.clip((f - 0.25) / 0.45, 0, 1) ** 1.2) * fall
    hi = np.clip((f - 0.55) / 0.25, 0, 1) * fall                  # the bright billows
    c = np.array(col, float)
    rgb = c[None, None, :] * (0.55 + 0.6 * dens[..., None]) + (255 - c)[None, None, :] * 0.22 * hi[..., None]
    a = np.clip(dens * strength + hi * 35, 0, 255)
    lay = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), a]).astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(max(S, r * 0.025)))
    full = Image.new("RGBA", (B, B), (0, 0, 0, 0)); full.paste(lay, (int(cx - n / 2), int(cy - n / 2)), lay)
    return full
import json, os
ART = json.load(open(ARTDIR + "/art.json"))
def game_cloud(key, cx, cy, R, gain=1.7):   # the game's own cloud, seen from above, sized so its body fills the circle
    global board
    a = ART[key]; im = Image.open(ARTDIR + "/art_%s.png" % key).convert("RGB")
    arr = np.asarray(im, float).sum(2); yy, xx = np.mgrid[0:arr.shape[0], 0:arr.shape[1]]
    dd = np.hypot(xx - a["cx"], yy - a["cy"]).ravel(); w = arr.ravel()
    o_ = np.argsort(dd); cum = np.cumsum(w[o_]); r90 = dd[o_][np.searchsorted(cum, cum[-1] * 0.9)]
    k = R * 1.05 / max(r90, 1.0)
    im = im.resize((int(im.width * k), int(im.height * k)), Image.LANCZOS).filter(ImageFilter.GaussianBlur(max(1, R * 0.012)))
    im = Image.eval(im, lambda v: min(255, int(v * gain)))
    full = Image.new("RGB", (B, B), (0, 0, 0)); full.paste(im, (int(cx - a["cx"] * k), int(cy - a["cy"] * k)))
    board = ImageChops.screen(board.convert("RGB"), full).convert("RGBA")
for i, (name, c, rad, kind, col) in enumerate(SYS["clouds"]):
    cx, cy = P(*c); r = max(rad / SQ_M * Q, Q * 0.38)
    key = "cloud_" + name.lower().replace(" ", "_")
    if key in ART: game_cloud(key, cx, cy, r, 1.5 if kind == "rocks" else 1.8)
    else: board = Image.alpha_composite(board, real_cloud(cx, cy, r, col, 200 if kind == "storm" else 140, 11 + i))
d = ImageDraw.Draw(board)

# ---- 3. grid: map squares with their names (A1 ... J10); the border ring shaded
for i in range(11):
    w = 2 * S if i in (0, 10) else S
    d.line([(i * Q, 0), (i * Q, B)], fill=CY + (70,), width=w)
    d.line([(0, i * Q), (B, i * Q)], fill=CY + (70,), width=w)
bd = Image.new("RGBA", (B, B), (0, 0, 0, 0)); bdd = ImageDraw.Draw(bd)
bdd.rectangle([0, 0, B, Q], fill=(0, 0, 0, 60)); bdd.rectangle([0, B - Q, B, B], fill=(0, 0, 0, 60))
bdd.rectangle([0, Q, Q, B - Q], fill=(0, 0, 0, 60)); bdd.rectangle([B - Q, Q, B, B - Q], fill=(0, 0, 0, 60))
board = Image.alpha_composite(board, bd); d = ImageDraw.Draw(board)
f_sq = fnt("Inter-SemiBold.otf", 17)
for cx in range(10):
    for cy in range(10):
        d.text((cx * Q + 10 * S, cy * Q + 8 * S), "ABCDEFGHIJ"[cx] + str(cy + 1), font=f_sq, fill=CY + (150,))

def label(x, y, title, sub=None, anchor="la", col=(240, 250, 255)):
    ft = fnt("InterDisplay-Bold.otf", 30); fs = fnt("Inter-SemiBold.otf", 19)
    d.text((x, y), title, font=ft, fill=col, anchor=anchor, stroke_width=4 * S, stroke_fill=(0, 0, 0, 230))
    if sub:
        yy = y + 36 * S
        d.text((x, yy), sub, font=fs, fill=CY + (255,), anchor=anchor, stroke_width=4 * S, stroke_fill=(0, 0, 0, 235))

# cloud names + a dashed wireframe edge
def dashed_circle(cx, cy, r, col, w, seg=60, on=0.55):
    for k in range(seg):
        a0 = math.tau * k / seg; a1 = a0 + math.tau / seg * on
        d.arc([cx - r, cy - r, cx + r, cy + r], math.degrees(a0), math.degrees(a1), fill=col, width=w)
for name, c, rad, kind, col in SYS["clouds"]:
    cx, cy = P(*c); r = max(rad / SQ_M * Q, Q * 0.38)
    dashed_circle(cx, cy, r, col + (190,), 2 * S, seg=int(24 + r / Q * 20))
    if kind == "rocks":   # wireframe rocks inside a rock cloud
        for k in range(int(10 + r / Q * 14)):
            a = rng.random() * math.tau; dd = r * math.sqrt(rng.random()) * 0.85
            px, py = cx + math.cos(a) * dd, cy + math.sin(a) * dd; rr = rng.uniform(5, 13) * S
            poly = [(px + math.cos(t) * rr * rng.uniform(0.6, 1.1), py + math.sin(t) * rr * rng.uniform(0.6, 1.1)) for t in [i * math.tau / 6 for i in range(6)]]
            d.polygon(poly, outline=(220, 215, 205, 230), width=S)
    label(cx, cy + r * 0.15, name.upper(), "ROCK FIELD" if kind == "rocks" else "NEBULA · BLOCKS SIGHT", anchor="ma", col=(235, 240, 255))

# ---- 4. orbit rings round the sun (each world's path)
sx, sy = P(*SYS["sun"])
for name, p, rr, col, kind in SYS["planets"]:
    px, py = P(*p); R = math.hypot(px - sx, py - sy)
    dashed_circle(sx, sy, R, CY + (150,), 2 * S, seg=140, on=0.6)

# ---- 5. trade lanes: twin dashed lines
for a, b in SYS["lanes"]:
    (ax, ay), (bx, by) = P(*pts[a]), P(*pts[b])
    L = math.hypot(bx - ax, by - ay); ux, uy = (bx - ax) / L, (by - ay) / L; nx, ny = -uy * 7 * S, ux * 7 * S
    t = 0.0; step = 26 * S
    while t < L:
        t1 = min(t + step * 0.6, L)
        for sgn in (1, -1):
            d.line([(ax + ux * t + nx * sgn, ay + uy * t + ny * sgn), (ax + ux * t1 + nx * sgn, ay + uy * t1 + ny * sgn)], fill=(120, 230, 255, 230), width=2 * S)
        t += step

# ---- 6. the asteroid belt (wireframe rocks), mineable
bn, bc, br = SYS["belt"]; bx, by = P(*bc); BR = br * Q
for k in range(70):
    a = rng.random() * math.tau; dd = BR * math.sqrt(rng.random())
    px, py = bx + math.cos(a) * dd, by + math.sin(a) * dd * 0.7; rr = rng.uniform(4, 14) * S
    poly = [(px + math.cos(t) * rr * rng.uniform(0.6, 1.1), py + math.sin(t) * rr * rng.uniform(0.6, 1.1)) for t in [i * math.tau / 7 for i in range(7)]]
    d.polygon(poly, fill=(60, 55, 52, 200), outline=(225, 215, 200, 255), width=S)
label(bx, by + BR * 0.72, bn.upper(), "ASTEROIDS · MINEABLE", anchor="ma")

# ---- 7. the sun
def screen_paste(img, cx, cy):   # light on black: added like light (the glow), nothing dark covers the board
    global board
    full = Image.new("RGB", (B, B), (0, 0, 0)); full.paste(img.convert("RGB"), (int(cx - img.width / 2), int(cy - img.height / 2)))
    board = ImageChops.screen(board.convert("RGB"), full).convert("RGBA")
def game_body(key, cx, cy, R, solid):
    global board
    a = ART[key]; im = Image.open(ARTDIR + "/art_%s.png" % key).convert("RGB")
    k = R / a["r"]; im = im.resize((int(im.width * k), int(im.height * k)), Image.LANCZOS)
    ox, oy = cx - a["cx"] * k, cy - a["cy"] * k
    full = Image.new("RGB", (B, B), (0, 0, 0)); full.paste(im, (int(ox), int(oy)))
    scr = ImageChops.screen(board.convert("RGB"), full)
    if solid:   # the world itself covers what is behind it; its glow is light added round it
        m = Image.new("L", (B, B), 0); ImageDraw.Draw(m).ellipse([cx - R * 0.985, cy - R * 0.985, cx + R * 0.985, cy + R * 0.985], fill=255)
        m = m.filter(ImageFilter.GaussianBlur(S))
        scr = Image.composite(full, scr, m)
    board = scr.convert("RGBA")
def halo(cx, cy, R, col, strength=1.0):   # an atmosphere's glow round a world
    g = Image.new("RGB", (B, B), (0, 0, 0)); gd = ImageDraw.Draw(g)
    for k in range(24, 0, -1):
        rr = R * (1.0 + k * 0.022); v = (1 - k / 24) ** 2 * 0.55 * strength
        gd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=tuple(int(c * v) for c in col))
    g = g.filter(ImageFilter.GaussianBlur(R * 0.06))
    global board
    board = ImageChops.screen(board.convert("RGB"), g).convert("RGBA")
r = Q * 0.3
game_body("sun", sx, sy, r, False)
d = ImageDraw.Draw(board)
label(sx, sy + r + 12 * S, SYS["name"] + " STAR", "DO NOT FLY INTO", anchor="ma", col=(255, 230, 180))

# ---- 8. planets as the game draws them, with their atmosphere's glow
for name, p, rr, col, kind in SYS["planets"]:
    px, py = P(*p); R = rr * Q
    halo(px, py, R, (120, 190, 255) if "ice" not in kind.lower() else (170, 215, 255))
    game_body(name.lower().replace(" ", "_"), px, py, R, True)
    d = ImageDraw.Draw(board)
    label(px, py + R * 1.12 + 6 * S, name.upper(), kind.upper(), anchor="ma")

# ---- 9. stations, gates, junctions (wireframe symbols)
def hexagon(cx, cy, R, rot=0.0): return [(cx + R * math.cos(rot + i * math.tau / 6), cy + R * math.sin(rot + i * math.tau / 6)) for i in range(6)]
def holo_paste(file, cx, cy, wpx, tint=None):
    global board, d
    im = Image.open(HOLO + "/" + file).convert("RGBA")
    k = wpx / max(im.width, im.height); im = im.resize((int(im.width * k), int(im.height * k)), Image.LANCZOS)
    if tint:
        r_, g_, b_, a_ = im.split()
        lum = Image.merge("RGB", (r_, g_, b_)).convert("L")
        im = Image.merge("RGBA", [lum.point(lambda v, c=c: int(v * c / 255)) for c in tint] + [a_])
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0)); sh.paste((0, 0, 0, 150), (0, 0), im.split()[3])
    sh = sh.filter(ImageFilter.GaussianBlur(6 * S))
    board.alpha_composite(sh, (int(cx - im.width / 2 + 6 * S), int(cy - im.height / 2 + 8 * S)))
    board.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))
    d = ImageDraw.Draw(board)
    return im.width, im.height
STATION_ART = {"Liberty Hub": "hub.png", "Liberator Freeport": "freeport.png", "Haven Station": "haven.png"}
for name, p, sub in SYS["stations"]:
    cx, cy = P(*p)
    w_, h_ = holo_paste(STATION_ART[name], cx, cy, Q * 0.62)
    label(cx + w_ * 0.5 + 8 * S, cy - 24 * S, name.upper(), "STATION · " + sub.upper())
for name, p in SYS["gates"]:
    cx, cy = P(*p)
    w_, h_ = holo_paste("gate.png", cx, cy, Q * 0.5, tint=(150, 255, 175))
    nm, to = name.split(" · ")
    label(cx + w_ * 0.5 + 8 * S, cy - 24 * S, "JUMP GATE", "TO " + to.upper(), col=(170, 255, 190))
for name, p in SYS.get("warp", []):
    cx, cy = P(*p); R = 30 * S
    for rr, w in ((R, 3), (R * 0.62, 2)): d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=(120, 170, 255, 255), width=w * S)
    for k in range(6):
        a = k * math.pi / 3
        d.line([(cx + math.cos(a) * R * 0.62, cy + math.sin(a) * R * 0.62), (cx + math.cos(a + 0.5) * R, cy + math.sin(a + 0.5) * R)], fill=(120, 170, 255, 255), width=2 * S)
    nm, to = name.split(" · ")
    label(cx + R * 1.7, cy - 24 * S, "WARP GATE", "TO " + to.upper(), col=(160, 195, 255))
for name, p in SYS["junctions"]:
    cx, cy = P(*p); R = 14 * S
    d.polygon([(cx, cy - R), (cx + R, cy), (cx, cy + R), (cx - R, cy)], fill=(8, 25, 45, 255), outline=(120, 230, 255, 255), width=2 * S)
    label(cx + R + 10 * S, cy - 14 * S, name.upper(), "LANE JUNCTION")

# ---- 10. the border marks: the system's name top centre, the game bottom right
ft = fnt("InterDisplay-Bold.otf", 88); fs = fnt("Inter-SemiBold.otf", 26)
for dx, dy in ((3, 3), (-3, 3), (0, 4)): d.text((B / 2 + dx * S, Q * 0.18 + dy * S), SYS["name"], font=ft, fill=(0, 0, 0, 200), anchor="ma")
d.text((B / 2, Q * 0.18), SYS["name"], font=ft, fill=(240, 250, 255, 255), anchor="ma")
d.text((B / 2, Q * 0.18 + 100 * S), "GALAXY " + SYS["galaxy"] + "  ·  UNITY SPACE", font=fs, fill=CY + (255,), anchor="ma")
d.text((B - 40 * S, B - 92 * S), "HOMELANCER", font=fnt("InterDisplay-Bold.otf", 40), fill=(240, 250, 255, 255), anchor="ra")
d.text((B - 40 * S, B - 46 * S), "homelancergame.com", font=fnt("Inter-SemiBold.otf", 22), fill=CY + (255,), anchor="ra")

# ---- 11. cut into six cards (3 across, 2 down), each labelled on its outer edge
board = board.convert("RGB").resize((3600, 3600), Image.LANCZOS)
board.save(f"{OUT}/{SYS['code'].lower()}_board_full.png", dpi=(300, 300))
cards = []
fl = ImageFont.truetype(F + "Inter-SemiBold.otf", 22)
for row in range(2):
    for col in range(3):
        k = row * 3 + col + 1
        c = board.crop((col * 1200, row * 1800, col * 1200 + 1200, row * 1800 + 1800)).copy()
        cd = ImageDraw.Draw(c)
        txt = f"{SYS['name']} {k} OF 6  ·  HL-{SYS['code']}-{k:02d}"
        y = 1800 - 14 if row == 1 else 44
        x = 40 if col != 2 or row == 0 else 40
        cd.text((x + 1, y + 1), txt, font=fl, fill=(0, 0, 0), anchor="la" if row == 0 else "ld")
        cd.text((x, y), txt, font=fl, fill=(130, 210, 255), anchor="la" if row == 0 else "ld")
        c.save(f"{OUT}/{SYS['code'].lower()}_card_{k}_of_6.png", dpi=(300, 300))
        cards.append(c)
cards[0].save(f"{OUT}/{SYS['code'].lower()}_board_6_cards.pdf", save_all=True, append_images=cards[1:], resolution=300)
print("ok")
