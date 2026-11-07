"""The Homelancer planet fauna, drawn as cel-shaded anime creatures (side / three-quarter view, facing right).

Each draw_* returns (svg_group, width, height, ground_y) in its own local box. Palettes are dicts so the same
drawing makes the biome variants (Mossfleece -> Drift woolly, Strider -> Prismhart, Vexmaw -> Shale stalker...).
"""
import math
from svgkit import (INK, part, smooth, scallop, tufts, line, taper, glow, circle, ellipse, eye, tones, poly, mix)

# ------------------------------------------------------------------ palettes
PAL = {
    "mossfleece": {"wool": "#efe4cf", "wool_sh": "#b9a7c4", "skin": "#4b3a63", "moss": "#79c95f", "horn": "#d9cfe8",
                   "hoof": "#2c2238", "eye": "#5ff2ff", "glow": "#7dffb0", "spore": "#b8ff6a"},
    "drift_woolly": {"wool": "#f4f8ff", "wool_sh": "#8fb0e0", "skin": "#2f4a72", "moss": "#9fe6ff", "horn": "#cfe9ff",
                     "hoof": "#1c2a40", "eye": "#9ff6ff", "glow": "#9ff6ff", "spore": "#e6fbff"},
    "strider": {"hide": "#b07a52", "belly": "#f0dfbf", "stripe": "#2f8e98", "antler": "#e9f4ff", "antler_glow": "#7ff0ff",
                "hoof": "#2a1d24", "eye": "#ffd25e", "crystal": False},
    "prismhart": {"hide": "#6e5aa8", "belly": "#e7e0ff", "stripe": "#ff6fd2", "antler": "#c9a5ff", "antler_glow": "#ff8ef0",
                  "hoof": "#1d1530", "eye": "#8ff6ff", "crystal": True},
    "vexmaw": {"skin": "#c8323a", "belly": "#ead6ae", "spike": "#2a1522", "claw": "#f3ead9", "eye": "#ffe14a",
               "mouth": "#5a0f22", "glow": "#ff8a3a", "stripe": "#7d1630"},
    "shale_stalker": {"skin": "#8a7a6a", "belly": "#d8c9a6", "spike": "#3a2a24", "claw": "#efe6d2", "eye": "#7affd8",
                      "mouth": "#3b1a1a", "glow": "#4effc8", "stripe": "#5a4a40"},
    "grumbark": {"fur": "#6b4a36", "bark": "#3b2b26", "moss": "#7fbf5a", "muzzle": "#c9a27e", "claw": "#efe2c8",
                 "eye": "#ffb347", "mouth": "#4a1020", "glow": "#ffcc66"},
    "rime_grumbark": {"fur": "#dfe8f4", "bark": "#6f86a8", "moss": "#a8f0ff", "muzzle": "#8aa0c0", "claw": "#f5fbff",
                      "eye": "#9ff6ff", "mouth": "#25324a", "glow": "#9ff6ff"},
    "sandmaw": {"hide": "#c98a4a", "plate": "#7a4a2e", "inner": "#3a0f22", "gum": "#d8506a", "tooth": "#fff3dc",
                "glow": "#ffcf5a", "sand": "#e8c07a"},
    "rimeback": {"fur": "#f2f6ff", "fur_sh": "#9fb4dc", "skin": "#5a78a8", "ice": "#a6f0ff", "eye": "#7ff6ff",
                 "mouth": "#24203c", "glow": "#9ff6ff", "claw": "#2a3450"},
}


# ------------------------------------------------------------------ 1. Mossfleece (passive grazer)
def mossfleece(p):
    W, H, G = 620, 430, 405
    wool = tones(p["wool"], shade_to=p["wool_sh"], st=0.55, dt=0.85)
    skin = tones(p["skin"])
    hoof = tones(p["hoof"])
    moss = tones(p["moss"])
    s = []
    # far legs (behind, darker)
    for x in (200, 365):
        lg = taper([(x + 16, 290), (x + 22, 340), (x + 14, 392)], 30, 16)
        s.append(part(smooth(lg), tones(mix(p["skin"], "#000000", 0.35)), ink=2.6))
        s.append(part(ellipse(x + 16, 396, 17, 9), hoof, ink=2.4))
    # tail tuft
    s.append(part(scallop(92, 196, 34, 30, 7, 0.6), wool, ink=3))
    # body wool
    jit = [0.0, 0.05, -0.03, 0.06, 0.0, 0.04, -0.02, 0.07, 0.01, 0.05, -0.04, 0.03, 0.0, 0.06]
    body = scallop(268, 228, 172, 112, 14, 0.62, jitter=jit)
    s.append(part(body, wool, sh=(14, 18), hl=(7, 8), ink=3.4))
    # inner wool curls
    for (cx, cy, r) in [(190, 215, 26), (250, 250, 30), (320, 215, 24), (210, 280, 22), (300, 285, 26), (370, 260, 20)]:
        s.append(f'<path d="M{cx - r},{cy} a{r},{r * 0.8} 0 0 1 {r * 1.6},{-r * 0.2}" fill="none" stroke="{wool[3]}" stroke-width="2.2" stroke-linecap="round" opacity="0.7"/>')
    # moss saddle on the back with spores
    s.append(part(scallop(262, 140, 96, 34, 9, 0.6, rot=-0.04), moss, sh=(6, 8), hl=(3, 4), ink=2.6))
    for (cx, cy) in [(205, 128), (238, 118), (276, 114), (312, 124), (250, 132), (292, 136)]:
        s.append(glow(circle(cx, cy, 4.2), p["spore"], blur=4, op=1.0, core="#ffffff"))
    # near legs
    for x in (232, 398):
        lg = taper([(x, 300), (x + 8, 345), (x - 2, 394)], 34, 18)
        s.append(part(smooth(lg), skin, ink=2.8))
        s.append(part(ellipse(x - 2, 398, 19, 10), hoof, ink=2.6))
        s.append(line([(x - 10, 396), (x - 2, 402), (x + 8, 396)], 2.0))
    # head: long alien face hanging forward-down
    neck = scallop(410, 175, 52, 48, 7, 0.6)
    s.append(part(neck, wool, ink=3))
    face = smooth([(418, 160), (468, 150), (520, 178), (548, 222), (540, 248), (510, 252), (478, 228), (440, 206), (412, 190)])
    s.append(part(face, skin, sh=(8, 9), hl=(4, 5), ink=3.2))
    s.append(line([(522, 238), (536, 244)], 2.4))          # mouth
    s.append(line([(537, 223), (543, 229)], 2.2))          # nostril
    s.append(line([(544, 246), (566, 262), (560, 276)], 3.0, col="#5fbf4a"))   # a grass blade it's chewing
    s.append(eye(478, 180, 11, p["eye"], p["glow"], look=(0.3, 0.1)))
    # droopy leaf ear
    ear = smooth([(430, 168), (400, 196), (382, 238), (396, 246), (420, 214), (444, 182)])
    s.append(part(ear, moss, sh=(5, 6), ink=2.6))
    s.append(line([(432, 178), (402, 232)], 1.6, op=0.6))
    # wool cap on the head
    s.append(part(scallop(452, 146, 26, 16, 6, 0.6), wool, ink=2.6))
    # curled horn (a thick spiral), lichen-tipped
    spiral = []
    for i in range(36):
        t = i / 35
        a = -1.2 + t * 4.6
        r = 46 * (1 - t * 0.74)
        spiral.append((446 + math.cos(a) * r, 150 + math.sin(a) * r * 0.9))
    hd = smooth(taper(spiral, 30, 7))
    s.append(part(hd, tones(p["horn"]), sh=(4, 5), hl=(2, 3), ink=2.6))
    for i in range(4, 30, 5):
        a, b = spiral[i], spiral[i + 1]
        s.append(line([a, (a[0] + (b[1] - a[1]) * 0.5, a[1] - (b[0] - a[0]) * 0.5)], 1.4, op=0.6))
    return "\n".join(s), W, H, G


# ------------------------------------------------------------------ 2. Strider / Prismhart (skittish prey)
def strider(p):
    W, H, G = 640, 560, 540
    hide = tones(p["hide"])
    far = tones(mix(p["hide"], "#1a1030", 0.4))
    belly = tones(p["belly"])
    hoof = tones(p["hoof"])
    s = []
    # six legs: three far, three near; front near leg lifted (alert)
    legs_far = [[(176, 330), (160, 400), (186, 468), (178, 532)], [(300, 340), (306, 430), (300, 532)],
                [(420, 330), (430, 430), (424, 532)]]
    for lg in legs_far:
        lg = [(x + 18, y - 4) for x, y in lg]
        s.append(part(smooth(taper(lg, 22, 9), k=0.6), far, ink=2.4))
        s.append(part(ellipse(lg[-1][0] + 2, lg[-1][1] + 3, 10, 6), hoof, ink=2))
    # tail: a flicked-up white flag (the herd alarm)
    tail = smooth([(150, 262), (118, 214), (104, 178), (126, 182), (148, 222), (168, 258)])
    s.append(part(tail, belly, ink=2.6))
    s.append(glow(circle(112, 186, 10), "#ffffff", blur=7, op=0.8))
    # body: lean, deep chest
    body = smooth([(150, 262), (200, 236), (300, 240), (390, 222), (452, 214), (480, 250), (468, 316), (420, 344),
                   (330, 340), (250, 350), (180, 338), (146, 300)])
    s.append(part(body, hide, sh=(10, 13), hl=(5, 6), ink=3.2))
    # belly band + stripes
    bel = smooth([(180, 318), (260, 334), (340, 330), (420, 336), (456, 312), (440, 340), (330, 346), (240, 352), (186, 336)])
    s.append(part(bel, belly, ink=0, deep=False))
    for x0 in (205, 245, 285, 325, 365):
        st = smooth(taper([(x0, 246), (x0 + 6, 270), (x0 - 2, 296)], 14, 3))
        s.append(f'<path d="{st}" fill="{p["stripe"]}" opacity="0.92"/>')
    # neck up to the head
    neck = smooth([(430, 226), (470, 160), (500, 110), (536, 100), (548, 130), (520, 176), (486, 260), (452, 274)])
    s.append(part(neck, hide, sh=(9, 10), ink=3.0))
    s.append(part(smooth([(470, 250), (500, 180), (528, 132), (538, 142), (512, 200), (488, 262)]), belly, ink=0, deep=False))
    # head
    head = smooth([(498, 108), (530, 78), (572, 82), (612, 104), (618, 120), (590, 128), (552, 132), (514, 128)])
    s.append(part(head, hide, sh=(7, 8), hl=(3, 4), ink=3.0))
    s.append(part(smooth([(590, 108), (618, 112), (616, 122), (592, 124)]), belly, ink=1.8, deep=False))
    s.append(f'<path d="{circle(611, 110, 2.6)}" fill="{INK}"/>')
    s.append(eye(556, 100, 9.5, p["eye"], p["eye"], look=(0.35, -0.1)))
    # tall alert ears
    for (bx, tip) in [((520, 88), (494, 30)), ((534, 84), (520, 24))]:
        ear = smooth([(bx[0] - 8, bx[1]), (tip[0] - 4, tip[1] + 18), tip, (tip[0] + 10, tip[1] + 22), (bx[0] + 10, bx[1] + 2)])
        s.append(part(ear, hide, sh=(4, 5), ink=2.4))
        s.append(part(smooth([(bx[0] - 2, bx[1] - 4), (tip[0] + 2, tip[1] + 22), (bx[0] + 6, bx[1] - 2)]), tones(p["stripe"]), ink=0, deep=False))
    # antlers
    if p["crystal"]:
        shards = [((540, 82), (548, 20), 15), ((556, 84), (590, 30), 13), ((548, 80), (570, 4), 11), ((530, 84), (520, 40), 10),
                  ((562, 86), (612, 58), 9)]
        for (b, t, w) in shards:
            mx, my = (b[0] + t[0]) / 2, (b[1] + t[1]) / 2
            dx, dy = t[0] - b[0], t[1] - b[1]
            L = math.hypot(dx, dy)
            nx, ny = -dy / L * w, dx / L * w
            pts = [b, (mx + nx, my + ny), t, (mx - nx * 0.6, my - ny * 0.6)]
            s.append(glow(poly(pts), p["antler_glow"], blur=10, op=0.7))
            s.append(part(poly(pts), tones(p["antler"]), sh=(4, 4), hl=(2, 2), ink=2.2, deep=False))
            s.append(f'<path d="M{b[0]},{b[1]} L{t[0]},{t[1]}" stroke="#ffffff" stroke-width="1.6" opacity="0.7"/>')
    else:
        def branch(pts, w):
            d = smooth(taper(pts, w, 2.5))
            return glow(d, p["antler_glow"], blur=6, op=0.6) + part(d, tones(p["antler"]), sh=(2, 3), hl=(1, 1), ink=2.0, deep=False)
        s.append(branch([(540, 82), (536, 50), (548, 22), (566, 4)], 9))
        s.append(branch([(538, 52), (512, 34), (500, 10)], 6))
        s.append(branch([(546, 30), (580, 26), (598, 8)], 5))
        s.append(branch([(556, 84), (584, 62), (606, 54)], 6))
        s.append(branch([(584, 62), (594, 36)], 4))
    # near legs (front one lifted)
    legs_near = [[(176, 320), (156, 396), (184, 468), (174, 534)], [(300, 334), (296, 432), (292, 534)],
                 [(430, 320), (452, 386), (428, 418), (440, 452)]]
    for i, lg in enumerate(legs_near):
        s.append(part(smooth(taper(lg, 26, 10), k=0.6), hide, sh=(5, 6), ink=2.8))
        e = lg[-1]
        s.append(part(ellipse(e[0] + 2, e[1] + 4, 11, 7, rot=-0.5 if i == 2 else 0), hoof, ink=2.2))
    return "\n".join(s), W, H, G


# ------------------------------------------------------------------ 3a. Vexmaw (territorial ambush hunter, ref 1)
def vexmaw(p):
    W, H, G = 760, 460, 440
    skin = tones(p["skin"])
    far = tones(mix(p["skin"], "#1a0a18", 0.45))
    belly = tones(p["belly"])
    spk = tones(p["spike"])
    claw = tones(p["claw"])
    s = []
    # far leg + far arm
    s.append(part(smooth(taper([(300, 262), (262, 330), (300, 380), (292, 432)], 46, 16), k=0.6), far, ink=2.6))
    s.append(part(smooth(taper([(470, 252), (520, 300), (566, 300)], 22, 12)), far, ink=2.4))
    for k in range(3):
        c = smooth([(562, 292 + k * 6), (600, 296 + k * 12), (624, 320 + k * 14), (596, 304 + k * 10)])
        s.append(part(c, tones(mix(p["claw"], "#2a1a2a", 0.4)), ink=2, deep=False))
    # tail with spike club
    tail = smooth(taper([(250, 236), (190, 228), (120, 238), (60, 262), (22, 300)], 66, 14))
    s.append(part(tail, skin, sh=(8, 10), ink=3.0))
    for (x, y, a) in [(20, 300, 2.6), (34, 284, 2.1), (14, 318, 3.2), (44, 312, 2.8)]:
        tip = (x + math.cos(a) * 34, y + math.sin(a) * 34 - 6)
        s.append(part(poly([(x - 6, y - 4), tip, (x + 8, y + 4)]), spk, ink=2, deep=False))
    # body: lean, low, coiled to lunge
    body = smooth([(240, 214), (320, 186), (420, 182), (480, 196), (520, 222), (500, 262), (430, 286), (340, 290), (260, 276), (230, 248)])
    s.append(part(body, skin, sh=(11, 14), hl=(6, 7), ink=3.4))
    bel = smooth([(270, 270), (350, 284), (430, 278), (494, 252), (470, 280), (400, 294), (320, 296), (268, 284)])
    s.append(part(bel, belly, ink=0, deep=False))
    for x0 in (300, 340, 380, 420):   # dark tiger bands
        s.append(f'<path d="{smooth(taper([(x0, 192), (x0 - 8, 214), (x0 + 2, 238)], 12, 2))}" fill="{p["stripe"]}"/>')
    # dorsal spikes along the spine and tail
    for i, (x, y) in enumerate([(130, 238), (170, 228), (210, 222), (250, 210), (290, 196), (330, 186), (370, 182), (410, 182), (450, 188)]):
        h = 24 + 10 * math.sin(i * 0.6)
        s.append(part(poly([(x - 9, y + 4), (x - 4, y - h), (x + 11, y + 2)]), spk, ink=2.2, deep=False))
    # neck and the big head, jaws wide open
    neck = smooth([(470, 196), (520, 170), (560, 160), (576, 196), (540, 232), (500, 248)])
    s.append(part(neck, skin, ink=3.0))
    upper = smooth([(540, 150), (600, 128), (676, 128), (744, 150), (740, 168), (690, 172), (620, 176), (566, 190)])
    lower = smooth([(560, 196), (612, 206), (680, 236), (726, 260), (716, 274), (650, 262), (590, 240), (552, 222)])
    mouth = smooth([(566, 186), (640, 174), (736, 164), (720, 262), (650, 248), (580, 220)])
    s.append(part(mouth, tones(p["mouth"]), ink=2.4, deep=False))
    s.append(glow(ellipse(620, 206, 30, 16, rot=0.3), p["glow"], blur=14, op=0.55))
    for i in range(9):   # upper teeth
        x = 586 + i * 17
        y = 172 - i * 0.6
        s.append(part(poly([(x, y), (x + 6, y + 22 - i * 0.8), (x + 11, y)]), claw, ink=1.6, deep=False))
    for i in range(7):   # lower teeth
        x = 600 + i * 17
        y = 214 + i * 7
        s.append(part(poly([(x, y), (x + 6, y - 20), (x + 11, y + 3)]), claw, ink=1.6, deep=False))
    s.append(part(upper, skin, sh=(8, 9), hl=(4, 4), ink=3.2))
    s.append(part(lower, skin, sh=(6, 7), ink=3.0))
    for (x, y) in [(600, 136), (630, 130), (662, 130)]:   # brow horns
        s.append(part(poly([(x, y + 4), (x - 16, y - 24), (x + 12, y)]), spk, ink=2, deep=False))
    s.append(eye(598, 152, 10, p["eye"], p["glow"], slit=True, look=(0.3, 0.0)))
    s.append(line([(580, 142), (616, 140)], 3.0))
    # near hind leg: digitigrade, huge thigh
    leg = smooth([(270, 230), (330, 228), (346, 280), (318, 330), (330, 380), (338, 428), (300, 432), (300, 384), (280, 330), (256, 280)])
    s.append(part(leg, skin, sh=(10, 12), hl=(5, 6), ink=3.2))
    for k in range(3):
        c = smooth([(300 + k * 14, 424), (318 + k * 18, 440), (340 + k * 16, 444), (322 + k * 14, 432)])
        s.append(part(c, claw, ink=1.8, deep=False))
    # near arm: reaching forward, long scythe claws
    arm = smooth(taper([(470, 240), (500, 300), (556, 324), (590, 326)], 30, 14))
    s.append(part(arm, skin, ink=3.0))
    for k in range(3):
        c = smooth([(584, 316 + k * 6), (630, 316 + k * 14), (668, 346 + k * 16), (628, 330 + k * 12)])
        s.append(part(c, claw, sh=(3, 4), ink=2.2, deep=False))
    return "\n".join(s), W, H, G


# ------------------------------------------------------------------ 3b. Grumbark (bear-like omnivore)
def grumbark(p):
    W, H, G = 620, 470, 450
    fur = tones(p["fur"])
    far = tones(mix(p["fur"], "#120a10", 0.45))
    bark = tones(p["bark"])
    moss = tones(p["moss"])
    claw = tones(p["claw"])
    s = []
    for (x, y) in [(170, 300), (420, 300)]:   # far legs
        s.append(part(smooth(taper([(x + 22, y), (x + 30, 380), (x + 22, 444)], 66, 50)), far, ink=2.6))
    # body with the big hump
    body = tufts(290, 250, 205, 150, 22, out=0.1, seed=4, rot=0.0)
    s.append(part(body, fur, sh=(14, 16), hl=(7, 8), ink=3.4))
    # bark plates down the hump (natural growth, layered like shingles)
    for i, (x, y, r) in enumerate([(170, 150, 0.4), (220, 118, 0.2), (275, 104, 0.0), (330, 110, -0.2), (380, 132, -0.4)]):
        pl = smooth([(x - 34, y + 22), (x - 26, y - 16), (x + 6, y - 30), (x + 34, y - 6), (x + 30, y + 26), (x, y + 36)])
        s.append(f'<g transform="rotate({math.degrees(r)},{x},{y})">' + part(pl, bark, sh=(5, 6), ink=2.6) +
                 line([(x - 18, y - 4), (x + 4, y + 18)], 1.6, col=bark[0], op=0.8) + "</g>")
        s.append(part(scallop(x - 4, y - 24, 16, 7, 4, 0.6), moss, ink=1.8, deep=False))
    # head, low and roaring
    head = smooth([(420, 210), (480, 190), (548, 214), (590, 250), (586, 300), (540, 330), (476, 324), (428, 290)])
    s.append(part(head, fur, sh=(9, 10), ink=3.2))
    mouth = smooth([(520, 280), (586, 276), (594, 314), (548, 340), (512, 316)])
    s.append(part(mouth, tones(p["mouth"]), ink=2.6, deep=False))
    for i in range(4):
        x = 528 + i * 15
        s.append(part(poly([(x, 280), (x + 6, 298), (x + 12, 280)]), claw, ink=1.4, deep=False))
        s.append(part(poly([(x, 334 - i * 3), (x + 6, 316 - i * 3), (x + 12, 332 - i * 3)]), claw, ink=1.4, deep=False))
    s.append(part(smooth([(540, 236), (596, 244), (600, 272), (548, 276)]), tones(p["muzzle"]), ink=2.4, deep=False))
    s.append(f'<path d="{ellipse(592, 252, 6, 4)}" fill="{INK}"/>')
    s.append(eye(510, 232, 9, p["eye"], p["glow"], look=(0.3, 0.1)))
    s.append(line([(490, 218), (528, 222)], 3.2))
    for (x, y) in [(448, 196), (476, 184)]:
        s.append(part(ellipse(x, y, 16, 13), fur, ink=2.4))
    # near legs, thick, with claws
    for (x, y) in [(150, 300), (400, 300)]:
        s.append(part(smooth(taper([(x + 10, y), (x + 4, 380), (x + 14, 446)], 78, 58)), fur, sh=(8, 8), ink=3.0))
        for k in range(4):
            c = smooth([(x - 8 + k * 14, 442), (x - 2 + k * 15, 458), (x + 8 + k * 15, 456)])
            s.append(part(c, claw, ink=1.6, deep=False))
    return "\n".join(s), W, H, G


# ------------------------------------------------------------------ 4. Sandmaw (giant burrower)
def sandmaw(p):
    W, H, G = 640, 720, 690
    hide = tones(p["hide"])
    plate = tones(p["plate"])
    sand = tones(p["sand"])
    s = []
    # dune it bursts out of (behind)
    s.append(part(smooth([(0, 690), (60, 640), (180, 600), (330, 610), (470, 640), (640, 690)], k=0.6) + "", sand, ink=0))
    # segments along a curve from the ground up and over to the right
    path = []
    for i in range(12):
        t = i / 11
        x = 170 + 220 * t + 60 * math.sin(t * 2.4)
        y = 670 - 520 * math.sin(t * 1.35) + 40 * t * t
        r = 92 - 34 * t
        path.append((x, y, r))
    for i, (x, y, r) in enumerate(path):
        rot = 0.25 + i * 0.05
        seg = ellipse(x, y, r * 1.02, r * 0.66, rot=rot)
        s.append(part(seg, hide, sh=(8, 10), hl=(4, 5), ink=3.0))
        pl = smooth([(x - r * 0.9, y - r * 0.15), (x - r * 0.5, y - r * 0.62), (x + r * 0.2, y - r * 0.72), (x + r * 0.8, y - r * 0.3),
                     (x + r * 0.6, y - r * 0.05), (x - r * 0.2, y - r * 0.25)])
        s.append(part(pl, plate, sh=(4, 5), ink=2.4, deep=False))
        s.append(glow(circle(x + r * 0.05, y + r * 0.35, r * 0.08), p["glow"], blur=5, op=0.9, core="#fff6d0"))
    # the head: three petal jaws round a toothed maw, facing us/right
    hx, hy = 470, 150
    for k, a in enumerate([-1.9, 0.15, 2.2]):
        tip = (hx + math.cos(a) * 200, hy + math.sin(a) * 170)
        l = (hx + math.cos(a - 0.55) * 70, hy + math.sin(a - 0.55) * 60)
        r_ = (hx + math.cos(a + 0.55) * 70, hy + math.sin(a + 0.55) * 60)
        pet = smooth([l, (hx + math.cos(a - 0.32) * 150, hy + math.sin(a - 0.32) * 128), tip, (hx + math.cos(a + 0.22) * 160, hy + math.sin(a + 0.22) * 134), r_], k=0.35)
        s.append(part(pet, plate, sh=(7, 8), ink=3.0))
        for j in range(4):   # hooked teeth along each petal
            tt = 0.35 + j * 0.15
            bx, by = hx + math.cos(a) * 200 * tt, hy + math.sin(a) * 170 * tt
            s.append(part(poly([(bx - 6, by), (bx + math.cos(a + 2.4) * 30, by + math.sin(a + 2.4) * 30), (bx + 6, by + 4)]), tones(p["tooth"]), ink=1.4, deep=False))
    maw = ellipse(hx, hy, 70, 62)
    s.append(part(maw, tones(p["gum"]), ink=3.0))
    s.append(f'<path d="{ellipse(hx + 6, hy + 4, 46, 40)}" fill="{p["inner"]}"/>')
    s.append(glow(ellipse(hx + 8, hy + 6, 24, 20), p["glow"], blur=16, op=0.8))
    for i in range(16):   # ring of teeth pointing in
        a = math.tau * i / 16
        b0 = (hx + math.cos(a - 0.12) * 58, hy + math.sin(a - 0.12) * 52)
        b1 = (hx + math.cos(a + 0.12) * 58, hy + math.sin(a + 0.12) * 52)
        t = (hx + math.cos(a) * 36, hy + math.sin(a) * 31)
        s.append(f'<path d="{poly([b0, t, b1])}" fill="{p["tooth"]}" stroke="{INK}" stroke-width="1.3"/>')
    # sand spray and the dune in front
    import random
    r = random.Random(7)
    for i in range(70):
        x = r.uniform(40, 600)
        y = r.uniform(560, 700) - abs(x - 260) * r.uniform(0.0, 0.5)
        s.append(f'<path d="{circle(x, y, r.uniform(2, 7))}" fill="{p["sand"]}" stroke="{INK}" stroke-width="1" opacity="0.9"/>')
    s.append(part(smooth([(0, 720), (0, 676), (120, 650), (230, 664), (300, 640), (380, 668), (520, 672), (640, 690), (640, 720)], k=0.6), sand, ink=3.0))
    return "\n".join(s), W, H, G


# ------------------------------------------------------------------ 5. Rimeback (snow beast, ref 2)
def rimeback(p):
    W, H, G = 640, 700, 680
    fur = tones(p["fur"], shade_to=p["fur_sh"], st=0.6, dt=0.95)
    skin = tones(p["skin"])
    ice = tones(p["ice"])
    claw = tones(p["claw"])
    s = []
    # legs (short, thick)
    for x in (230, 380):
        s.append(part(tufts(x, 596, 64, 84, 12, out=0.12, seed=x), fur, sh=(8, 9), ink=3.0))
        s.append(part(ellipse(x + 8, 672, 58, 14), skin, ink=2.6))
    # torso: huge, furry
    torso = tufts(310, 400, 190, 210, 26, out=0.1, seed=3)
    s.append(part(torso, fur, sh=(16, 18), hl=(8, 9), ink=3.4))
    for sd in (-1, 1):   # chest muscles under the fur: shading only, no bare plate
        s.append(line([(310 + sd * 8, 372), (310 + sd * 56, 380), (310 + sd * 70, 420)], 2.4, col=fur[3], op=0.8))
        s.append(line([(310 + sd * 10, 430), (310 + sd * 48, 440)], 2.0, col=fur[3], op=0.6))
    for (x, y) in [(200, 470), (230, 520), (390, 480), (420, 520), (310, 540), (260, 560), (360, 566)]:
        s.append(line([(x, y), (x + 6, y + 22), (x + 2, y + 34)], 1.8, col=fur[3], op=0.7))
    # arms raised in the threat display
    for sd in (-1, 1):
        sx = 310 + sd * 150
        arm = [(sx, 300), (sx + sd * 90, 230), (sx + sd * 130, 120), (sx + sd * 120, 50)]
        s.append(part(smooth(taper(arm, 110, 70)), fur, sh=(10, 12), ink=3.2))
        hx, hy = arm[-1]
        s.append(part(ellipse(hx, hy - 6, 44, 34, rot=0.2 * sd), skin, ink=2.8))
        for k in range(4):
            fx = hx - 30 + k * 20
            s.append(part(smooth([(fx - 8, hy - 30), (fx - 4, hy - 64), (fx + 8, hy - 62), (fx + 8, hy - 30)]), skin, ink=2.2, deep=False))
            s.append(part(poly([(fx - 5, hy - 60), (fx + 1, hy - 80), (fx + 7, hy - 60)]), claw, ink=1.4, deep=False))
    # ice crystals growing out of the shoulders and back
    for (x, y, h, a) in [(170, 268, 90, -0.6), (200, 236, 120, -0.3), (236, 214, 80, -0.15), (450, 268, 90, 0.6), (420, 236, 120, 0.3), (384, 214, 80, 0.15)]:
        tip = (x + math.sin(a) * h, y - math.cos(a) * h)
        pts = [(x - 16, y + 8), (x - 8 + math.sin(a) * h * 0.6, y - math.cos(a) * h * 0.6), tip, (x + 14 + math.sin(a) * h * 0.4, y - math.cos(a) * h * 0.4), (x + 16, y + 10)]
        s.append(glow(poly(pts), p["glow"], blur=12, op=0.55))
        s.append(part(poly(pts), ice, sh=(4, 5), hl=(2, 2), ink=2.4, deep=False))
        s.append(f'<path d="M{x},{y} L{tip[0]},{tip[1]}" stroke="#ffffff" stroke-width="1.8" opacity="0.7"/>')
    # head: shaggy brow, roaring
    s.append(part(tufts(310, 236, 80, 66, 16, out=0.16, seed=9), fur, sh=(8, 9), ink=3.2))
    face = smooth([(262, 230), (358, 230), (372, 280), (340, 318), (280, 318), (248, 280)])
    s.append(part(face, skin, sh=(6, 7), ink=3.0))
    mouth = smooth([(278, 272), (342, 272), (336, 310), (284, 310)])
    s.append(part(mouth, tones(p["mouth"]), ink=2.6, deep=False))
    for i in range(4):
        x = 284 + i * 14
        s.append(f'<path d="{poly([(x, 272), (x + 6, 288), (x + 12, 272)])}" fill="#ffffff" stroke="{INK}" stroke-width="1.2"/>')
    s.append(f'<path d="{poly([(282, 310), (288, 290), (294, 310)])}" fill="#ffffff" stroke="{INK}" stroke-width="1.2"/>')
    s.append(f'<path d="{poly([(326, 310), (332, 290), (338, 310)])}" fill="#ffffff" stroke="{INK}" stroke-width="1.2"/>')
    s.append(eye(286, 250, 8.5, p["eye"], p["glow"], look=(0.0, 0.1)))
    s.append(eye(334, 250, 8.5, p["eye"], p["glow"], look=(0.0, 0.1)))
    s.append(line([(268, 236), (300, 244)], 3.6))
    s.append(line([(352, 236), (320, 244)], 3.6))
    s.append(part(tufts(310, 212, 70, 22, 12, out=0.3, seed=12, a0=math.pi, a1=math.tau), fur, ink=2.8))   # the brow fringe
    return "\n".join(s), W, H, G


# ------------------------------------------------------------------ the human pilot and the mech for scale (silhouette only)
def human_sil(h):
    """A 1.8 m pilot silhouette, h px tall, standing on y=0, x centred."""
    u = h / 18.0
    pts = [(-1.2, -16.2), (1.2, -16.2), (1.4, -14.2), (3.3, -13.4), (3.6, -7.6), (2.5, -7.5), (2.2, -11.5), (2.0, -7.0), (2.4, 0), (0.6, 0),
           (0.2, -6.6), (-0.2, -6.6), (-0.6, 0), (-2.4, 0), (-2.0, -7.0), (-2.2, -11.5), (-2.5, -7.5), (-3.6, -7.6), (-3.3, -13.4), (-1.4, -14.2)]
    body = poly([(x * u, y * u) for x, y in pts])
    return body + " " + circle(0, -16.4 * u, 1.6 * u)


def mech_sil(h):
    """A 10 m mech silhouette (blocky legs, broad core, rifle arm)."""
    u = h / 100.0
    pts = [(-14, -100), (14, -100), (18, -88), (34, -84), (38, -56), (30, -54), (28, -70), (22, -56), (24, -40), (30, 0), (12, 0), (8, -36),
           (-8, -36), (-12, 0), (-30, 0), (-24, -40), (-22, -56), (-28, -70), (-30, -54), (-52, -60), (-54, -66), (-36, -66), (-34, -84), (-18, -88)]
    return poly([(x * u, y * u) for x, y in pts])
