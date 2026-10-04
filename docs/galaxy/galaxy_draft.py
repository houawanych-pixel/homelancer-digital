#!/usr/bin/env python3
"""Homelancer galaxy, 11 x 11 FIRST DRAFT (owner call, 3 Oct 2026). Draws the map picture and writes the tile list.
usage: python3 galaxy_draft.py   -> galaxy_11x11_draft.png, galaxy_11x11_tiles.csv, galaxy_11x11_gates.csv"""
import csv, itertools, math
from PIL import Image, ImageDraw, ImageFont

COLS = "ABCDEFGHIJK"
FAC = {  # fill, text, label
    "Unity": ("#bfeefc", "#06222c"), "Elyza": ("#2f5fd0", "#ffffff"), "Solarion": ("#f0a81e", "#241500"),
    "Imperium": ("#b3182c", "#ffffff"), "Covenant": ("#7a3fc0", "#ffffff"), "Orion": ("#16995a", "#ffffff"),
    "Savagers": ("#c2561c", "#ffffff"), "Liberator": ("#1fa5a0", "#041f1e"), "Enemy": ("#33343b", "#ffffff"),
    "Neutral": ("#b9a98a", "#1c160c"), "Hidden": ("#101018", "#ffffff"), "Void": ("#1a2233", "#9fb0c8"),
    "Heart": ("#fff3c4", "#2a1c00"),
}
ACCENT = {"Void System": "#e0202a", "Cynthara": "#7be33a", "Kronos": "#9fd8ff", "Cybernet": "#ff3fc8",
          "Noctyra": "#a060ff", "Genesis": "#f2e21c", "Shadow": "#8a5cff", "Radiant": "#ffd84a"}
# name: (tile, faction, role, planets, stations)
S = {
 "Veranthos": ("F4", "Unity", "capital", 5, 4), "Keldrix": ("F1", "Unity", "", 3, 1), "Aurentum": ("E2", "Unity", "", 3, 2), "Federis": ("G3", "Unity", "", 2, 2),
 "Synthari Capital": ("H4", "Solarion", "capital", 6, 4), "Nexarion": ("I3", "Solarion", "", 3, 2), "Kellova": ("J2", "Solarion", "", 3, 1), "Techanis": ("H2", "Solarion", "", 3, 2), "Crossma Major": ("J4", "Solarion", "", 4, 2),
 "Malachar": ("H6", "Imperium", "capital", 5, 3), "Shadenvex": ("J6", "Imperium", "", 2, 1), "Vorreth": ("I5", "Imperium", "", 3, 1), "Obsidrath": ("K7", "Imperium", "", 3, 1), "Empire Major": ("I7", "Imperium", "", 4, 2),
 "Sepheron": ("H8", "Covenant", "capital", 4, 3), "Valdris": ("J8", "Covenant", "", 3, 1), "Sanctum Major": ("I10", "Covenant", "", 3, 2),
 "Dreadholm": ("F8", "Orion", "capital", 5, 4), "Ironvast": ("F10", "Orion", "", 3, 2), "Korrath": ("E9", "Orion", "", 2, 1), "Battlespire": ("G9", "Orion", "", 2, 2), "Vortegan": ("E11", "Orion", "", 3, 1), "Omicron Major": ("G11", "Orion", "", 4, 2),
 "Raptian Major": ("D8", "Savagers", "capital", 4, 3), "Scavaris": ("C9", "Savagers", "", 2, 1), "Plundros": ("B8", "Savagers", "", 3, 1), "Derelicta": ("B10", "Savagers", "", 2, 2), "Ravage Major": ("D10", "Savagers", "", 3, 1),
 "Vantara": ("D6", "Liberator", "capital", 4, 3), "Exodus Point": ("B6", "Liberator", "", 2, 2), "Kiral": ("C5", "Liberator", "", 3, 1), "Republic Major": ("C7", "Liberator", "", 3, 2),
 "Aurelion": ("D4", "Elyza", "capital", 5, 3), "Crystara": ("C3", "Elyza", "", 3, 1), "Selenvar": ("B2", "Elyza", "", 2, 1), "Velanthos": ("D2", "Elyza", "", 3, 1), "Zillance Major": ("B4", "Elyza", "", 4, 2),
 "Void System": ("C1", "Enemy", "Solrath home", 3, 2), "Kronos": ("H1", "Enemy", "Arctides home", 3, 1), "Cynthara": ("A5", "Enemy", "Gadversee home", 3, 1),
 "Cybernet": ("A8", "Enemy", "Cybermorph home", 2, 2), "Noctyra": ("K8", "Enemy", "Phenom home", 2, 1), "Genesis": ("H11", "Enemy", "Kaijurai home", 3, 1),
 "Radiant": ("K1", "Hidden", "hidden", 1, 1), "Shadow": ("A11", "Hidden", "hidden", 2, 1),
 "Rimgate": ("E5", "Neutral", "", 2, 1), "Vexara": ("G5", "Neutral", "", 2, 1), "Ogden": ("E7", "Neutral", "", 2, 1), "Foggiest": ("G7", "Neutral", "", 2, 1),
 "Farreach Outpost": ("A3", "Neutral", "", 1, 1), "Perimeter": ("K3", "Neutral", "", 2, 1), "Nullpoint": ("K5", "Neutral", "", 1, 1), "Omega": ("K10", "Neutral", "", 3, 1),
 "Sigma-19": ("J10", "Neutral", "", 2, 1), "Beta-7": ("A1", "Neutral", "", 1, 1), "Voidtex": ("C11", "Neutral", "", 2, 1), "Shroud": ("A10", "Neutral", "", 2, 1), "Nebulax": ("J1", "Neutral", "", 1, 1),
 "Void 1": ("I1", "Void", "void", 1, 0), "Void 2": ("K11", "Void", "void", 1, 0), "Void 3": ("A7", "Void", "void", 1, 0),
 "Void 4": ("K9", "Void", "void", 1, 0), "Void 5": ("D11", "Void", "void", 1, 0), "Void 6": ("A2", "Void", "void", 1, 0),
 "THE HEART": ("F6", "Heart", "centre", 0, 0),
 # the two systems already built in the game (the test pair). Solara hangs off Veranthos, Vega off Solara.
 "Solara": ("F3", "Unity", "start", 1, 1), "Vega": ("F2", "Neutral", "frontier", 1, 1),
}
PRESS = {"Void System": ("Unity", "Elyza"), "Kronos": ("Solarion", "Unity"), "Cynthara": ("Elyza", "Liberator"),
         "Cybernet": ("Liberator", "Savagers"), "Noctyra": ("Imperium", "Covenant"), "Genesis": ("Orion", "Covenant")}
ENEMY = {"Void System": "Solrath", "Kronos": "Arctides", "Cynthara": "Gadversee", "Cybernet": "Cybermorphs", "Noctyra": "Phenom", "Genesis": "Kaijurai"}
WARP = [("Selenvar", "Aurentum"), ("Kellova", "Shadenvex"), ("Obsidrath", "Sanctum Major"), ("Ironvast", "Derelicta"),
        ("Plundros", "Kiral"), ("Omicron Major", "Sigma-19"), ("Perimeter", "Radiant"), ("Shroud", "Shadow")]
RIFT = [("Rimgate", "Nullpoint"), ("Velanthos", "Ravage Major")]

def xy(t): return COLS.index(t[0]), int(t[1:]) - 1
P = {n: xy(v[0]) for n, v in S.items()}
assert len(set(P.values())) == len(P), "two systems on one tile"
occ = {v: k for k, v in P.items()}

HELD = {}
for e in ENEMY:
    ex, ey = P[e]
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            t = (ex + dx, ey + dy)
            if t != (ex, ey) and 0 <= t[0] < 11 and 0 <= t[1] < 11 and t not in occ and t not in HELD: HELD[t] = e

def jump_ok(a, b):
    fa, fb = S[a][1], S[b][1]
    if "Solara" in (a, b) or "Vega" in (a, b): return {a, b} in ({"Solara", "Veranthos"}, {"Solara", "Vega"})
    if "Hidden" in (fa, fb): return False                       # hidden systems: warp only
    if "Heart" in (fa, fb): return {a, b} in ({"THE HEART", "Veranthos"}, {"THE HEART", "Dreadholm"})
    if {fa, fb} == {"Unity", "Orion"}: return False             # their one link runs through the Heart
    for e, f in ((a, fb), (b, fa)):
        if e in PRESS and f not in PRESS[e] + ("Neutral", "Void"): return False
    (x1, y1), (x2, y2) = P[a], P[b]
    dx, dy = abs(x1 - x2), abs(y1 - y2)
    if max(dx, dy) > 2 or dx + dy > 3: return False             # a jump gate hops at most over one empty tile
    if (dx, dy) in ((2, 0), (0, 2), (2, 2)) and ((x1 + x2) // 2, (y1 + y2) // 2) in occ: return False
    return True
def d(a, b): return math.dist(P[a], P[b])
cand = sorted((d(a, b) + (0 if S[a][1] == S[b][1] else 0.3), a, b) for a, b in itertools.combinations(S, 2) if jump_ok(a, b))
par = {n: n for n in S}
def find(n):
    while par[n] != n: par[n] = par[par[n]]; n = par[n]
    return n
JUMP, deg = [], {n: 0 for n in S}
for w, a, b in cand:                                             # spanning tree first: every system reachable
    if find(a) != find(b): par[find(a)] = find(b); JUMP.append((a, b)); deg[a] += 1; deg[b] += 1
for w, a, b in cand:                                             # then a few short loops, max 3 gates per system
    if (a, b) not in JUMP and w <= 1.8 and deg[a] < 3 and deg[b] < 3 and "Heart" not in (S[a][1], S[b][1]):
        JUMP.append((a, b)); deg[a] += 1; deg[b] += 1
if ("THE HEART", "Veranthos") not in JUMP and ("Veranthos", "THE HEART") not in JUMP: JUMP.append(("Veranthos", "THE HEART"))
groups = {}
for n in S: groups.setdefault(find(n), []).append(n)
print("jump", len(JUMP), "warp", len(WARP), "rift", len(RIFT) + 1, "| jump-only groups:", sorted(len(g) for g in groups.values()))
for g in groups.values():
    if len(g) < 5: print("  small group:", g)

# ---- picture ----
T, M, TOP, LEG = 236, 70, 150, 430
W, H = M * 2 + T * 11, TOP + T * 11 + LEG
im = Image.new("RGB", (W, H), "#070a12"); dr = ImageDraw.Draw(im)
def font(sz, bold=True): return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % ("-Bold" if bold else ""), sz)
def c(n): x, y = P[n]; return M + x * T + T // 2, TOP + y * T + T // 2
dr.text((M, 28), "HOMELANCER GALAXY  11 x 11  FIRST DRAFT", font=font(54), fill="#ffffff")
dr.text((M, 96), "121 tiles: 58 named systems, Solara and Vega, 6 void systems, the Heart, %d enemy-held open tiles, %d free open tiles." % (len(HELD), 54 - len(HELD)) + " Every edge wraps to the far side.", font=font(26, False), fill="#9fb0c8")
for i in range(11):
    dr.text((M + i * T + T // 2 - 10, TOP - 34), COLS[i], font=font(28), fill="#6f7f98")
    dr.text((22, TOP + i * T + T // 2 - 16), str(i + 1), font=font(28), fill="#6f7f98")
    for j in range(11):
        x0, y0 = M + i * T, TOP + j * T
        dr.rectangle([x0, y0, x0 + T, y0 + T], outline="#1b2436", width=2)
        if (i, j) in HELD:
            e = HELD[(i, j)]
            dr.rectangle([x0 + 5, y0 + 5, x0 + T - 5, y0 + T - 5], fill="#24252b", outline=ACCENT[e], width=4)
            dr.text((x0 + 14, y0 + 12), f"{COLS[i]}{j + 1}", font=font(18), fill="#8d909c")
            for k, l in enumerate((ENEMY[e], "space")):
                dr.text((x0 + T / 2 - dr.textlength(l, font=font(24)) / 2, y0 + T / 2 - 30 + k * 30), l, font=font(24), fill=ACCENT[e])
        elif (i, j) not in occ: dr.text((x0 + 10, y0 + 8), f"{COLS[i]}{j + 1}", font=font(18, False), fill="#2f3b52")
def line(a, b, col, wd, dash=None):
    (x1, y1), (x2, y2) = c(a), c(b)
    if not dash: dr.line([x1, y1, x2, y2], fill=col, width=wd); return
    L = math.dist((x1, y1), (x2, y2)); n = int(L // dash)
    for k in range(0, n, 2):
        t0, t1 = k / n, min(1, (k + 1) / n)
        dr.line([x1 + (x2 - x1) * t0, y1 + (y2 - y1) * t0, x1 + (x2 - x1) * t1, y1 + (y2 - y1) * t1], fill=col, width=wd)
for a, b in RIFT: line(a, b, "#c04cff", 7, 12)
for a, b in WARP: line(a, b, "#3d9bff", 8, 26)
for a, b in JUMP: line(a, b, "#35e06a", 9)
BW, BH = 204, 150
for n, (tile, fac, role, pl, st) in S.items():
    cx, cy = c(n); fill, tx = FAC[fac]
    box = [cx - BW // 2, cy - BH // 2, cx + BW // 2, cy + BH // 2]
    dr.rounded_rectangle(box, 16, fill=fill, outline=ACCENT.get(n, "#ffffff" if role == "capital" else "#000000"), width=7 if n in ACCENT or role == "capital" else 2)
    words, lines = n.split(), []
    for wd_ in words:
        if lines and dr.textlength(lines[-1] + " " + wd_, font=font(25)) <= BW - 16: lines[-1] += " " + wd_
        else: lines.append(wd_)
    y = box[1] + 10
    dr.text((box[0] + 10, y), tile, font=font(18), fill=tx); 
    if role == "capital": dr.text((box[2] - 104, y), "CAPITAL", font=font(18), fill=tx)
    y += 26
    for l in lines: dr.text((cx - dr.textlength(l, font=font(25)) / 2, y), l, font=font(25), fill=tx); y += 30
    if fac == "Heart": info = "heart of the galaxy"
    elif fac == "Void": info = "small sun, no life"
    else: info = f"{pl} planet{'s' if pl != 1 else ''} · {st} stn"
    dr.text((cx - dr.textlength(info, font=font(19, False)) / 2, box[3] - 52), info, font=font(19, False), fill=tx)
    sub = role if fac in ("Enemy",) else fac if fac not in ("Heart", "Void") else ""
    dr.text((cx - dr.textlength(sub, font=font(17, False)) / 2, box[3] - 28), sub, font=font(17, False), fill=tx)
hx, hy = c("THE HEART"); dr.ellipse([hx - 132, hy - 132, hx + 132, hy + 132], outline="#c04cff", width=6)
# legend
ly = TOP + T * 11 + 30
dr.text((M, ly), "FACTIONS", font=font(30), fill="#ffffff")
x = M
for k in ["Unity", "Elyza", "Solarion", "Imperium", "Covenant", "Orion", "Savagers", "Liberator", "Enemy", "Neutral", "Hidden", "Void"]:
    dr.rounded_rectangle([x, ly + 50, x + 196, ly + 100], 10, fill=FAC[k][0], outline="#ffffff", width=2)
    dr.text((x + 98 - dr.textlength(k, font=font(24)) / 2, ly + 60), k, font=font(24), fill=FAC[k][1]); x += 212
gy = ly + 140
dr.text((M, gy), "GATES", font=font(30), fill="#ffffff")
dr.line([M, gy + 70, M + 150, gy + 70], fill="#35e06a", width=9); dr.text((M + 170, gy + 54), f"JUMP gate ({len(JUMP)}): next system, hops over at most one open tile", font=font(26, False), fill="#d8e2f0")
for k in range(0, 150, 52): dr.line([M + k, gy + 118, M + k + 26, gy + 118], fill="#3d9bff", width=8)
dr.text((M + 170, gy + 102), f"WARP gate ({len(WARP)}): hidden in nebula, 3 to 4 tiles, the only way to Shadow and Radiant", font=font(26, False), fill="#d8e2f0")
for k in range(0, 150, 24): dr.line([M + k, gy + 166, M + k + 12, gy + 166], fill="#c04cff", width=7)
dr.text((M + 170, gy + 150), f"RIFT gate ({len(RIFT) + 1}): 6 to 8 tiles. Purple ring on the Heart = the rift gate to the one live REALM (off the grid; 3 more realms later)", font=font(26, False), fill="#d8e2f0")
dr.text((M, gy + 210), "White border = faction capital. Coloured border = enemy home (accent colour) or hidden system. Grey squares = open space held by the enemy home next to them.", font=font(24, False), fill="#9fb0c8")
dr.text((M, gy + 246), "Planet and station counts are the PROPOSED ones from the Star System Catalog v2. Draft for the owner to reshape.", font=font(24, False), fill="#9fb0c8")
im.save("galaxy_11x11_draft.png"); im.convert("RGB").save("galaxy_11x11_draft.jpg", quality=88)
with open("galaxy_11x11_tiles.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["tile", "system", "faction", "role", "planets", "stations", "sky file"])
    for n, v in sorted(S.items(), key=lambda kv: (xy(kv[1][0])[1], xy(kv[1][0])[0])):
        sky = "" if n == "THE HEART" else n.lower().replace(" ", "_").replace("-", "_") + ".jpg"
        w.writerow([v[0], n, v[1], v[2], v[3], v[4], sky])
with open("galaxy_11x11_gates.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["type", "from", "from tile", "to", "to tile"])
    for t, L in (("jump", JUMP), ("warp", WARP), ("rift", RIFT + [("THE HEART", "REALM")])):
        for a, b in L: w.writerow([t, a, S[a][0], b, S[b][0] if b in S else "off grid"])
with open("galaxy_11x11_tiles.csv", "a", newline="") as f:
    w = csv.writer(f)
    for (i, j), e in sorted(HELD.items(), key=lambda kv: (kv[0][1], kv[0][0])): w.writerow([f"{COLS[i]}{j + 1}", "(open space)", "Enemy", f"held by {ENEMY[e]} ({e})", 0, 0, ""])
import collections
print("held", len(HELD), dict(collections.Counter(ENEMY[e] for e in HELD.values())))
print(W, H)
