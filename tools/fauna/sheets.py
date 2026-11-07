"""Build the 5 archetype concept sheets and the scale chart (SVG -> PNG with the pre-installed Chromium).

    python3 tools/fauna/sheets.py OUT_DIR
"""
import math
import random
import sys
from svgkit import INK, smooth, poly, circle, ellipse, glow, uid, mix
import creatures as C

W, H = 1800, 1100
HERO = (40, 150, 1130, 760)    # x, y, w, h of the splash panel
FONT = "Inter Display, Inter, DejaVu Sans, sans-serif"

# ------------------------------------------------------------------ the sheets' content
SHEETS = [
    {"no": 1, "arch": "PASSIVE GRAZER", "name": "MOSSFLEECE", "fn": C.mossfleece, "pal": "mossfleece",
     "tag": "Woolly herd grazer. Moss grows on its back; spores glow at dusk.",
     "bg": ("#ffcf8a", "#f59a6a", "#7a5aa0"), "land": ("#6fa85a", "#3f7a4a", "#2a4a3a"), "fx": "meadow", "accent": "#7dffb0",
     "profile": [("Role", "PREY (placeholder animal)"), ("Biome", "Farmland + forest (Meridian, Fields, Verdance)"), ("Size", "3.5 m long, 2.4 m tall"), ("Diet", "Grass, moss"),
                 ("Group", "Herds of 4-8"), ("Active", "Day"), ("Notices you", "40 m"), ("Territory", "none (roams)")],
     "states": ["GRAZE", "ROAM", "ALERT", "FLEE"],
     "notes": ["Head down grazing; one keeps watch, head up.", "Alerted: bleats, the herd bunches up, then runs.",
               "Never attacks. Shots make the whole herd scatter.", "Moss saddle + spores = the alien read at a distance."],
     "anims": ["idle (chew, ear flick)", "graze (head down loop)", "walk", "run", "alert (head up, bleat)", "startle hop", "lie down / sleep"], "variants": [("drift_woolly", "DRIFT WOOLLY", "Snow worlds (Prism, Frost)")]},
    {"no": 2, "arch": "SKITTISH PREY", "name": "STRIDER", "fn": C.strider, "pal": "strider",
     "tag": "Six-legged runner. Flicks up a white tail-flag to warn the herd, then bolts.",
     "bg": ("#3a6a8a", "#1d3a5a", "#120f2a"), "land": ("#2f5a4a", "#1f4038", "#122a26"), "fx": "forest", "accent": "#7ff0ff",
     "profile": [("Role", "PREY (placeholder animal)"), ("Biome", "Forest + jungle (Verdance, Thornwild, Eden Prime)"), ("Size", "6 m tall at the antlers"), ("Diet", "Leaves, flowers"),
                 ("Group", "Herds of 2-4"), ("Active", "Dawn + dusk"), ("Notices you", "90 m"), ("Territory", "none (roams)")],
     "states": ["GRAZE", "ALERT", "FLAG", "FLEE TO COVER"],
     "notes": ["First to spot you: freezes, ears up, tail flag flashes.", "The flag alerts every animal in 60 m.",
               "Bolts at 26 m/s towards trees / rocks, zig-zags.", "Already in the game (v12.28); Prismhart is new."],
     "anims": ["idle", "graze", "walk", "gallop (6-leg tripod)", "alert freeze (ears up)", "tail-flag flash", "zig-zag bolt", "drink"], "variants": [("prismhart", "PRISMHART", "Crystal worlds (Crystara, Geode, Lumen)")]},
    {"no": 3, "arch": "TERRITORIAL PREDATOR", "name": "VEXMAW", "fn": C.vexmaw, "pal": "vexmaw",
     "tag": "Lean ambush hunter. Lies low in the jungle, warns once, then lunges.",
     "bg": ("#ff6a4a", "#8a1a3a", "#1a0a1e"), "land": ("#3a5a2a", "#22381e", "#121c12"), "fx": "jungle", "accent": "#ff8a3a",
     "profile": [("Role", "PREDATOR (placeholder animal)"), ("Biome", "Jungle (Thornwild, Brood, Eden Prime)"), ("Size", "12 m long, 4.5 m tall"), ("Diet", "Meat (hunts striders)"),
                 ("Group", "Alone or a pair"), ("Active", "Dusk + night"), ("Notices you", "70 m"), ("Territory", "150 m")],
     "states": ["PATROL", "WARN", "ATTACK", "GIVE UP + RETURN"],
     "notes": ["Warn: hiss, jaws open, spines up (2 s) - back off and it stops.", "Attack: lunge + bite, then circles and lunges again.",
               "Leaves you once you're past its territory (150 m).", "Hunts striders on its own: you can watch a chase."],
     "anims": ["idle crouch", "stalk (low walk)", "run", "warn: hiss + spines up", "lunge bite", "claw swipe", "circle / strafe", "hit react", "give up: turn away"], "variants": [("grumbark", "GRUMBARK", "Bear-like. DEFENSE role. Forest (Verdance)"), ("shale_stalker", "SHALE STALKER", "Rock-skinned. Desert + canyon")]},
    {"no": 4, "arch": "GIANT BURROWER", "name": "SANDMAW", "fn": C.sandmaw, "pal": "sandmaw",
     "tag": "Lives under the dunes. The ground ripples first; then it bursts out.",
     "bg": ("#ffd88a", "#f08a4a", "#7a2a3a"), "land": ("#d89a5a", "#a0623a", "#5a3226"), "fx": "desert", "accent": "#ffcf5a",
     "profile": [("Role", "DEFENSE (placeholder animal)"), ("Biome", "Desert + canyon (planet TBD: Keld Minor?)"), ("Size", "45 m long, 18 m out of the ground"), ("Diet", "Anything that walks"),
                 ("Group", "One per area"), ("Active", "Any time"), ("Notices you", "Footsteps, 120 m"), ("Territory", "300 m")],
     "states": ["BURROW", "RIPPLE", "TELEGRAPH", "EMERGE", "EXPOSED", "RE-BURROW"],
     "notes": ["Ripple: a sand wake moves towards you (you see it coming).", "Telegraph: a ring of shaking sand for 1.5 s - move out.",
               "Emerge: bite in the ring only. Big hit, never an instant kill.", "Exposed 4 s: weak spot open, then it digs back in."],
     "anims": ["burrow travel (sand wake)", "ripple", "telegraph shake (1.5 s)", "emerge + bite", "exposed roar (weak spot open)", "hit react", "re-burrow"], "variants": []},
    {"no": 5, "arch": "SNOW BEAST", "name": "RIMEBACK", "fn": C.rimeback, "pal": "rimeback",
     "tag": "Giant snow ape. Ice crystals grow from its shoulders. Beats the snow, roars, defends its peak.",
     "bg": ("#bfe4ff", "#6a8ad0", "#2a2a6a"), "land": ("#eaf4ff", "#a8c0e8", "#6a7ab0"), "fx": "snow", "accent": "#9ff6ff",
     "profile": [("Role", "DEFENSE (placeholder animal)"), ("Biome", "Snow + ice mountains (Prism, Frost, Glacier)"), ("Size", "14 m tall standing"), ("Diet", "Fur grazers, ice moss"),
                 ("Group", "Alone"), ("Active", "Any time (blizzards)"), ("Notices you", "100 m"), ("Territory", "250 m")],
     "states": ["ROAM", "THREAT DISPLAY", "CHARGE", "SLAM", "RETURN"],
     "notes": ["Threat display: rears up, arms high, roars (2.5 s).", "Charge + ground slam: a shock ring you can jump or dash.",
               "Throws ice chunks if you keep away at range.", "Gives up at the edge of its peak and walks home."],
     "anims": ["idle (breath steam)", "knuckle walk", "run", "threat display: rear + chest beat", "charge", "ground slam (shock ring)", "ice throw", "give up: walk home"], "variants": []},
]


# ------------------------------------------------------------------ background art per biome
def backdrop(sh):
    x, y, w, h = HERO
    top, mid, low = sh["bg"]
    l1, l2, l3 = sh["land"]
    g = uid("bg")
    rnd = random.Random(sh["no"])
    s = [f'<linearGradient id="{g}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{low}"/>'
         f'<stop offset="0.55" stop-color="{mid}"/><stop offset="1" stop-color="{top}"/></linearGradient>',
         f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="url(#{g})"/>']
    cx, cy = x + w * 0.55, y + h * 0.45
    # splash-art burst: rays from behind the creature
    for i in range(28):
        a = math.tau * i / 28 + rnd.uniform(-0.05, 0.05)
        wa = rnd.uniform(0.03, 0.08)
        L = 1500
        s.append(f'<path d="{poly([(cx, cy), (cx + math.cos(a - wa) * L, cy + math.sin(a - wa) * L), (cx + math.cos(a + wa) * L, cy + math.sin(a + wa) * L)])}" '
                 f'fill="#ffffff" opacity="{rnd.uniform(0.03, 0.09):.3f}"/>')
    s.append(glow(circle(cx, cy, 260), top, blur=90, op=0.65))
    fx = sh["fx"]
    if fx == "snow":   # aurora + jagged peaks
        for k in range(3):
            pts = [(x + i * w / 10, y + 90 + k * 40 + 30 * math.sin(i * 0.9 + k)) for i in range(11)]
            s.append(f'<path d="{smooth(pts, False)}" stroke="{["#7affd8", "#9ff6ff", "#c48aff"][k]}" stroke-width="{38 - k * 8}" fill="none" opacity="0.28" stroke-linecap="round"/>')
    for k, (col, base, amp, n) in enumerate([(l3, 0.52, 0.20, 7), (l2, 0.68, 0.14, 9), (l1, 0.82, 0.09, 11)]):
        pts = [(x - 20, y + h + 20)]
        for i in range(n + 1):
            px = x + w * i / n
            if fx in ("snow",):
                py = y + h * (base - amp * (0.5 + 0.5 * math.sin(i * 1.7 + k))) - (rnd.uniform(20, 70) if i % 2 else 0)
            elif fx == "desert":
                py = y + h * (base - amp * (0.3 + 0.7 * abs(math.sin(i * 0.7 + k * 2))))
                if k == 0 and i % 3 == 1:
                    py -= 120   # mesas
            else:
                py = y + h * (base - amp * (0.5 + 0.5 * math.sin(i * 1.3 + k * 1.7)))
            pts.append((px, py))
        pts.append((x + w + 20, y + h + 20))
        d = smooth(pts, True, k=0.3 if fx in ("snow", "desert") else 0.5)
        s.append(f'<path d="{d}" fill="{col}" opacity="{0.75 + k * 0.12:.2f}"/>')
        if fx == "snow" and k < 2:
            s.append(f'<path d="{d}" fill="none" stroke="#ffffff" stroke-width="3" opacity="0.5"/>')
    if fx in ("forest", "jungle"):   # tall alien trees / huge leaves framing the sides
        for i in range(7):
            tx = x + (rnd.uniform(0, 160) if i % 2 else w - rnd.uniform(0, 200))
            th = rnd.uniform(0.6, 1.0) * h
            col = mix(l3, "#000000", 0.35)
            s.append(f'<path d="{smooth([(tx - 14, y + h), (tx - 6, y + h - th * 0.6), (tx + 4, y + h - th), (tx + 16, y + h - th * 0.6), (tx + 18, y + h)], True)}" fill="{col}" opacity="0.9"/>')
            for j in range(4):
                a = rnd.uniform(-2.8, -0.3)
                lx, ly = tx, y + h - th * rnd.uniform(0.6, 1.0)
                L = rnd.uniform(90, 200)
                tip = (lx + math.cos(a) * L, ly + math.sin(a) * L * 0.6)
                s.append(f'<path d="{smooth([(lx, ly), ((lx + tip[0]) / 2 - 30, (ly + tip[1]) / 2 - 40), tip, ((lx + tip[0]) / 2 + 30, (ly + tip[1]) / 2 + 20)])}" fill="{col}" opacity="0.92"/>')
    if fx == "meadow":   # far colony towers (Meridian), soft
        for i in range(5):
            tx = x + w * 0.62 + i * 46
            th = rnd.uniform(90, 200)
            s.append(f'<path d="{poly([(tx, y + h * 0.5), (tx + 6, y + h * 0.5 - th), (tx + 14, y + h * 0.5 - th - 18), (tx + 22, y + h * 0.5 - th), (tx + 28, y + h * 0.5)])}" fill="{l3}" opacity="0.55"/>')
            s.append(glow(circle(tx + 14, y + h * 0.5 - th - 10, 4), "#fff0b0", blur=4, op=0.9, core="#ffffff"))
    # floating particles (spores / embers / snow / sand)
    pc = {"meadow": "#eaffb0", "forest": "#9ff6ff", "jungle": "#ffb070", "desert": "#fff0c0", "snow": "#ffffff"}[fx]
    for i in range(90 if fx == "snow" else 50):
        px, py = x + rnd.uniform(0, w), y + rnd.uniform(0, h)
        r = rnd.uniform(1.5, 5.5 if fx == "snow" else 3.5)
        s.append(f'<path d="{circle(px, py, r)}" fill="{pc}" opacity="{rnd.uniform(0.35, 0.95):.2f}"/>')
    if fx == "desert":   # ripple rings: the telegraph read
        for k in range(4):
            s.append(f'<path d="{ellipse(x + w * 0.2, y + h * 0.9, 60 + k * 34, 14 + k * 8)}" fill="none" stroke="#fff3d0" stroke-width="3" opacity="{0.7 - k * 0.15:.2f}"/>')
    return "\n".join(s)


def frame(x, y, w, h, col, cut=26, sw=3):
    pts = [(x + cut, y), (x + w, y), (x + w, y + h - cut), (x + w - cut, y + h), (x, y + h), (x, y + cut)]
    return f'<path d="{poly(pts)}" fill="none" stroke="{col}" stroke-width="{sw}"/>'


def frame_clip(x, y, w, h, cut=26):
    return poly([(x + cut, y), (x + w, y), (x + w, y + h - cut), (x + w - cut, y + h), (x, y + h), (x, y + cut)])


def text(x, y, t, size, col="#ffffff", weight=800, anchor="start", ls=0, op=1.0):
    t = t.replace("&", "&amp;")
    return (f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" font-weight="{weight}" fill="{col}" '
            f'text-anchor="{anchor}" letter-spacing="{ls}" opacity="{op}">{t}</text>')


def place(fn, pal, box, flip=False, sil=None):
    """Fit a creature into box (x, y, w, h), standing on the box's bottom."""
    g, cw, ch, gy = fn(C.PAL[pal])
    bx, by, bw, bh = box
    sc = min(bw / cw, bh / ch)
    ox = bx + (bw - cw * sc) / 2
    oy = by + bh - ch * sc
    tr = f"translate({ox + (cw * sc if flip else 0):.1f},{oy:.1f}) scale({-sc if flip else sc:.4f},{sc:.4f})"
    if sil:
        return f'<g transform="{tr}" filter="url(#sil_{sil})">{g}</g>'
    return f'<g transform="{tr}">{g}</g>'


def sheet(sh):
    x, y, w, h = HERO
    acc = sh["accent"]
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
         '<defs><filter id="sil_k"><feColorMatrix type="matrix" values="0 0 0 0 0.08 0 0 0 0 0.06 0 0 0 0 0.12 0 0 0 1 0"/></filter>',
         '<filter id="sil_w"><feColorMatrix type="matrix" values="0 0 0 0 0.85 0 0 0 0 0.9 0 0 0 0 1 0 0 0 1 0"/></filter></defs>',
         f'<rect width="{W}" height="{H}" fill="#0e1222"/>',
         f'<path d="{poly([(0, 0), (W, 0), (W, 120), (0, 120)])}" fill="#151a30"/>',
         f'<path d="M0,118 L{W},118" stroke="{acc}" stroke-width="2" opacity="0.8"/>']
    # header
    s.append(text(48, 52, "HOMELANCER  ·  PLANET FAUNA  ·  CONCEPT SHEET %d / 5" % sh["no"], 20, "#8fa0c8", 700, ls=3))
    s.append(text(48, 100, sh["name"], 50, "#ffffff", 900, ls=2))
    s.append(text(48 + len(sh["name"]) * 39 + 44, 100, sh["arch"], 26, acc, 800, ls=4))
    s.append(text(W - 48, 52, "PLACEHOLDER - NOT FINAL", 18, "#ffcf5a", 800, "end", ls=3))
    s.append(text(W - 48, 92, "original design · Epic Seven anime + Homelancer sci-fi", 18, "#8fa0c8", 600, "end"))
    # the splash panel
    cp = uid("hc")
    s.append(f'<clipPath id="{cp}"><path d="{frame_clip(x, y, w, h)}"/></clipPath><g clip-path="url(#{cp})">')
    s.append(backdrop(sh))
    pad = {1: (150, 150, 820, 560), 2: (240, 30, 700, 700), 3: (60, 160, 1010, 560), 4: (260, 10, 640, 740), 5: (260, 20, 620, 720)}[sh["no"]]
    # a cast shadow on the ground
    s.append(f'<path d="{ellipse(x + pad[0] + pad[2] / 2, y + pad[1] + pad[3] - 8, pad[2] * 0.42, 22)}" fill="#000000" opacity="0.28"/>')
    s.append(place(sh["fn"], sh["pal"], (x + pad[0], y + pad[1], pad[2], pad[3])))
    s.append('</g>')
    s.append(frame(x, y, w, h, acc))
    s.append(f'<path d="{poly([(x, y + h - 58), (x + w, y + h - 58), (x + w, y + h - 26), (x + w - 26, y + h), (x, y + h)])}" fill="#0e1222" opacity="0.72"/>')
    s.append(text(x + 24, y + h - 20, sh["tag"], 22, "#ffffff", 700))
    # right column: profile
    rx = 1210
    s.append(text(rx, 182, "PROFILE", 22, acc, 900, ls=4))
    yy = 220
    for k, v in sh["profile"]:
        s.append(text(rx, yy, k.upper(), 15, "#8fa0c8", 800, ls=2))
        s.append(text(rx + 150, yy, v, 19, "#ffffff", 600))
        yy += 34
    # behaviour chain
    yy += 18
    s.append(text(rx, yy, "BEHAVIOUR", 22, acc, 900, ls=4))
    yy += 22
    bx = rx
    row_y = yy
    for i, st in enumerate(sh["states"]):
        tw = 15 + len(st) * 10.5
        if bx + tw > W - 40:
            bx = rx
            row_y += 46
        s.append(f'<path d="{poly([(bx, row_y), (bx + tw, row_y), (bx + tw + 10, row_y + 17), (bx + tw, row_y + 34), (bx, row_y + 34), (bx + 10, row_y + 17)])}" '
                 f'fill="{mix(acc, "#0e1222", 0.72)}" stroke="{acc}" stroke-width="1.6"/>')
        s.append(text(bx + 14, row_y + 23, st, 15, "#ffffff", 800, ls=1))
        bx += tw + 14
    yy = row_y + 70
    for n in sh["notes"]:
        s.append(f'<path d="{circle(rx + 6, yy - 6, 4)}" fill="{acc}"/>')
        s.append(text(rx + 20, yy, n, 17, "#d8e0f4", 500))
        yy += 30
    # palette swatches
    yy += 16
    s.append(text(rx, yy, "PALETTE", 22, acc, 900, ls=4))
    pal = C.PAL[sh["pal"]]
    cols = [v for v in pal.values() if isinstance(v, str) and v.startswith("#")][:8]
    for i, c in enumerate(cols):
        s.append(f'<path d="{poly([(rx + i * 66, yy + 16), (rx + i * 66 + 56, yy + 16), (rx + i * 66 + 56, yy + 62), (rx + i * 66, yy + 62)])}" fill="{c}" stroke="#ffffff" stroke-width="1.5"/>')
    # animation list
    yy += 112
    s.append(text(rx, yy, "ANIMATIONS", 22, acc, 900, ls=4))
    yy += 34
    for i, a in enumerate(sh["anims"]):
        cx = rx + (i % 2) * 280
        cy = yy + (i // 2) * 30
        s.append(text(cx, cy, "%02d  %s" % (i + 1, a), 16, "#d8e0f4", 500))
    # bottom strip: scale + variants
    by = 935
    s.append(f'<path d="{poly([(40, by), (1170, by), (1170, 1070), (40, 1070)])}" fill="#151a30" stroke="#2a3456" stroke-width="2"/>')
    s.append(text(60, by + 30, "SCALE", 18, acc, 900, ls=3))
    # human 1.8 m, mech 10 m, creature at its height
    hpx = 110 / 14.0   # px per metre (14 m fits 110 px)
    gy = by + 122
    s.append(f'<path d="M60,{gy} L560,{gy}" stroke="#4a5a86" stroke-width="2"/>')
    s.append(f'<path transform="translate(90,{gy})" d="{C.human_sil(1.8 * hpx)}" fill="#d8e0f4"/>')
    s.append(text(90, gy + 18, "1.8 m", 12, "#8fa0c8", 700, "middle"))
    s.append(f'<path transform="translate(150,{gy})" d="{C.mech_sil(10 * hpx)}" fill="#6a7ab0"/>')
    s.append(text(150, gy + 18, "mech 10 m", 12, "#8fa0c8", 700, "middle"))
    hm = {1: 2.4, 2: 6.0, 3: 4.5, 4: 18.0, 5: 14.0}[sh["no"]]
    _, cw, ch, _ = sh["fn"](C.PAL[sh["pal"]])
    hpx_c = min(hm * hpx, 110)
    sc = hpx_c / ch
    s.append(place(sh["fn"], sh["pal"], (260, gy - hpx_c, cw * sc, hpx_c), sil="w"))
    s.append(text(260 + cw * sc / 2, gy + 18, "%s %g m tall" % (sh["name"].title(), hm), 12, acc, 800, "middle"))
    if sh["no"] == 4:
        s.append(text(560, gy + 18, "(only the front 18 m comes out)", 12, "#8fa0c8", 600, "end"))
    # variants
    vx = 600
    if sh["variants"]:
        s.append(text(vx, by + 30, "BIOME VARIANTS (same body, new colours / parts)", 16, acc, 900, ls=2))
        for i, (vp, vn, vd) in enumerate(sh["variants"]):
            cx = vx + i * 290
            fn = C.grumbark if vp in ("grumbark", "rime_grumbark") else sh["fn"]
            s.append(place(fn, vp, (cx, by + 42, 120, 84)))
            s.append(text(cx + 128, by + 72, vn, 17, "#ffffff", 900, ls=1))
            words = vd.split(" ")
            l1, l2 = " ".join(words[:3]), " ".join(words[3:])
            s.append(text(cx + 128, by + 96, l1, 14, "#b8c4e4", 500))
            s.append(text(cx + 128, by + 116, l2, 14, "#b8c4e4", 500))
    else:
        s.append(text(vx, by + 30, "READ AT A DISTANCE", 16, acc, 900, ls=2))
        s.append(place(sh["fn"], sh["pal"], (vx, by + 40, 150, 90), sil="k"))
        s.append(text(vx + 170, by + 76, "Silhouette must read on a phone at 200 m:", 15, "#d8e0f4", 600))
        s.append(text(vx + 170, by + 100, "big shapes, glowing bits, no armour.", 15, "#d8e0f4", 600))
    s.append('</svg>')
    return "\n".join(s)


# ------------------------------------------------------------------ the scale chart
SCALE = [("Pilot", None, None, 1.8, "#d8e0f4"), ("Hopper*", None, None, 1.8, None), ("Mossfleece", C.mossfleece, "mossfleece", 2.4, None),
         ("Vexmaw", C.vexmaw, "vexmaw", 4.5, None), ("Glow grazer*", None, None, 5.0, None), ("Strider", C.strider, "strider", 6.0, None),
         ("Grumbark", C.grumbark, "grumbark", 6.5, None), ("Mech", None, None, 10.0, "#6a7ab0"), ("Rimeback", C.rimeback, "rimeback", 14.0, None),
         ("Sandmaw (out)", C.sandmaw, "sandmaw", 18.0, None)]


def scale_chart():
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
         f'<rect width="{W}" height="{H}" fill="#0e1222"/>',
         text(48, 60, "HOMELANCER  ·  PLANET FAUNA  ·  SCALE CHART", 20, "#8fa0c8", 700, ls=3),
         text(48, 110, "HOW BIG THEY ARE NEXT TO YOU", 44, "#ffffff", 900, ls=2),
         text(W - 48, 60, "PLACEHOLDER - NOT FINAL", 18, "#ffcf5a", 800, "end", ls=3)]
    # width of each figure per metre of height, so the whole line-up fits the page at one scale
    def wpm(fn, pal, name):
        if fn:
            _, cw, ch, _ = fn(C.PAL[pal])
            return cw / ch
        return {"Pilot": 0.5, "Mech": 0.95, "Hopper*": 0.9, "Glow grazer*": 1.2}[name]
    gap = 34
    total_w = sum(wpm(fn, pal, n) * hm for n, fn, pal, hm, _ in SCALE)
    ppm = min(42.0, (W - 160 - gap * len(SCALE)) / total_w)
    gy = 960
    for m in range(0, 19, 2):
        yy = gy - m * ppm
        s.append(f'<path d="M90,{yy:.1f} L{W - 40},{yy:.1f}" stroke="#25304e" stroke-width="{2 if m % 10 == 0 else 1}"/>')
        s.append(text(80, yy + 5, f"{m} m", 14, "#6a7aa8", 700, "end"))
    s.append(f'<path d="M90,{gy} L{W - 40},{gy}" stroke="#8fa0c8" stroke-width="3"/>')
    x = 110
    for name, fn, pal, hm, col in SCALE:
        hpx = hm * ppm
        wbox = wpm(fn, pal, name) * hpx
        if fn:
            s.append(place(fn, pal, (x, gy - hpx, wbox, hpx)))
        elif name == "Pilot":
            s.append(f'<path transform="translate({x + wbox / 2},{gy})" d="{C.human_sil(hpx)}" fill="{col}"/>')
        elif name == "Mech":
            s.append(f'<path transform="translate({x + wbox * 0.57},{gy})" d="{C.mech_sil(hpx)}" fill="{col}"/>')
        else:   # in-game models already exist (v12.28): an outline blob
            s.append(f'<path d="{ellipse(x + wbox / 2, gy - hpx / 2, wbox / 2, hpx / 2)}" fill="none" stroke="#7ff0ff" stroke-width="2" stroke-dasharray="6 5"/>')
        ty = gy + 34
        if name != "Hopper*":   # (too narrow here; it's labelled in the zoom row)
            s.append(text(x + wbox / 2, ty, name, 17, "#ffffff", 800, "middle"))
            s.append(text(x + wbox / 2, ty + 22, f"{hm:g} m", 15, "#8fa0c8", 700, "middle"))
        x += wbox + gap
    # zoom x3 on the small and middle ones (same order, same scale as each other)
    z = ppm * 3.0
    zg = 560
    s.append(text(48, 170, "ZOOM x3 - THE SMALLER ONES", 18, "#7ff0ff", 900, ls=3))
    s.append(f'<path d="M90,{zg} L{W - 40},{zg}" stroke="#8fa0c8" stroke-width="2"/>')
    for m in (2, 4, 6):
        s.append(f'<path d="M90,{zg - m * z:.1f} L{W - 40},{zg - m * z:.1f}" stroke="#25304e" stroke-width="1"/>')
        s.append(text(80, zg - m * z + 5, f"{m} m", 14, "#6a7aa8", 700, "end"))
    x = 110
    for name, fn, pal, hm, col in SCALE[:6]:
        hpx = hm * z
        wbox = wpm(fn, pal, name) * hpx
        if fn:
            s.append(place(fn, pal, (x, zg - hpx, wbox, hpx)))
        elif name == "Pilot":
            s.append(f'<path transform="translate({x + wbox / 2},{zg})" d="{C.human_sil(hpx)}" fill="{col}"/>')
        else:
            s.append(f'<path d="{ellipse(x + wbox / 2, zg - hpx / 2, wbox / 2, hpx / 2)}" fill="none" stroke="#7ff0ff" stroke-width="2" stroke-dasharray="6 5"/>')
        s.append(text(x + wbox / 2, zg + 30, f"{name} {hm:g} m", 16, "#ffffff", 800, "middle"))
        x += wbox + 30
    s.append(text(48, 1078, "Game scale is set against the 10 m mech (ground blocks are 5 m). * already in the game (v12.28), shown as outlines. "
                  "Sandmaw is 45 m long; only the front 18 m comes out.", 17, "#b8c4e4", 500))
    s.append('</svg>')
    return "\n".join(s)


def render(svgs, out):
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": W, "height": H})
        for name, svg in svgs:
            open(f"{out}/{name}.svg", "w").write(svg)
            pg.set_content(f'<html><body style="margin:0;background:#0e1222">{svg}</body></html>')
            pg.wait_for_timeout(150)
            pg.screenshot(path=f"{out}/{name}.png")
        b.close()


if __name__ == "__main__":
    out = sys.argv[1]
    names = {1: "grazer", 2: "prey", 3: "predator", 4: "burrower", 5: "snow_beast"}
    svgs = [(f"HL_Fauna_{sh['no']}_{names[sh['no']]}_{sh['name'].lower()}", sheet(sh)) for sh in SHEETS]
    svgs.append(("HL_Fauna_6_scale_chart", scale_chart()))
    render(svgs, out)
    print("\n".join(n for n, _ in svgs))
