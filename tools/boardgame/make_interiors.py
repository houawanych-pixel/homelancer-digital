# Homelancer tabletop: interiors drawn like a real deck plan — rooms nested inside the hull, sharing walls, doors in
# the walls, numbered, with a key. Battleship: three decks cut through the Imperium battleship's own top-down outline.
# Facility: a Zelda-style dungeon on the game's own room grid (Boarding.facility), rooms touching, doors where the
# game's tunnels join them, ramps where the floor drops a level.
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
F = "/usr/share/fonts/opentype/inter/"
def fnt(n, sz): return ImageFont.truetype(F + n, int(sz))
HOLO = os.environ.get("HL_BOARD_HOLO", "/tmp/claude-0/board/wire")
W, H = 1800, 1200
FLOOR = (232, 226, 212); WALL = (58, 62, 70); HULL = (120, 126, 136); HULL_D = (78, 84, 94)
KIND = {"command": (150, 190, 235), "hangar": (176, 200, 150), "cargo": (214, 196, 150), "crew": (226, 214, 190), "armory": (222, 150, 140),
        "reactor": (255, 168, 80), "engine": (170, 160, 150), "med": (190, 225, 215), "lift": (120, 140, 170), "corridor": (205, 199, 186), "hall": (236, 228, 210)}
RED = (225, 60, 60); GRN = (60, 190, 100); AMB = (240, 150, 40); CYN = (40, 150, 210)

def label_walls(lab, wall_px):   # walls wherever two different rooms (or a room and the outside) meet
    L = lab
    edge = np.zeros(L.shape, bool)
    for dy, dx in ((0, 1), (1, 0)):
        a = L[:L.shape[0] - dy, :L.shape[1] - dx]; b = L[dy:, dx:]
        diff = a != b
        edge[:L.shape[0] - dy, :L.shape[1] - dx] |= diff; edge[dy:, dx:] |= diff
    e = Image.fromarray((edge * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(wall_px))
    return np.array(e) > 0

def render_rooms(lab, rooms, doors, size, grid=36):
    """lab: int array (0 = outside); rooms: {id: dict(kind, num)}; doors: list of (x, y, w, h) rects to open."""
    Hh, Ww = lab.shape
    rgb = np.zeros((Hh, Ww, 3), np.uint8)
    for rid, r in rooms.items():
        rgb[lab == rid] = KIND.get(r["kind"], FLOOR)
    walls = label_walls(lab, 7)
    for (x, y, w, h) in doors: walls[max(0, y):y + h, max(0, x):x + w] = False
    inside = lab > 0
    # a faint movement grid on the floors
    gmask = np.zeros_like(inside)
    gmask[::grid, :] = True; gmask[:, ::grid] = True
    rgb[gmask & inside & ~walls] = (rgb[gmask & inside & ~walls] * 0.86).astype(np.uint8)
    rgb[walls & (inside | (Image.fromarray((inside * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(9)) is not None))] = WALL
    a = np.where(inside | walls, 255, 0).astype(np.uint8)
    img = Image.fromarray(np.dstack([rgb, a]), "RGBA")
    return img

# ------------------------------------------------------------------ battleship
def hull_mask(w, h):
    im = Image.open(f"{HOLO}/t_imp_battleship.png").convert("RGBA").rotate(-90, expand=True)   # nose to the right
    a = im.split()[3].point(lambda v: 255 if v > 40 else 0)
    bb = a.getbbox(); a = a.crop(bb).resize((w, h), Image.LANCZOS).point(lambda v: 255 if v > 128 else 0)
    # fill the little gaps between the hull's fins so the decks are solid
    a = a.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))
    return np.array(a) > 0, im.crop(bb).resize((w, h), Image.LANCZOS)

# each deck: rooms along the hull from the stern (left, x=0) to the nose (right, x=1), above / below the spine
DECKS = [
  ("DECK 1 · COMMAND", 0.62, [   # (kind, name, side, x0, x1, guards, mark)
    ("engine", "LIFE SUPPORT", "both", 0.05, 0.2, 0, ""), ("command", "COMMS ARRAY", "top", 0.2, 0.42, 0, ""),
    ("crew", "OBSERVATION LOUNGE", "bot", 0.2, 0.42, 1, ""), ("crew", "OFFICERS' QUARTERS", "top", 0.42, 0.56, 0, ""), ("armory", "ARMORY", "bot", 0.42, 0.56, 1, ""),
    ("lift", "BRIDGE LIFT", "both", 0.56, 0.61, 0, "lift"), ("crew", "CAPTAIN'S QUARTERS", "top", 0.61, 0.74, 0, ""),
    ("command", "NAVICOMPUTER", "bot", 0.61, 0.74, 0, ""), ("command", "BRIDGE", "both", 0.74, 1.0, 1, "mech")]),
  ("DECK 2 · MAIN", 1.0, [
    ("engine", "AFT STORES", "both", 0.0, 0.12, 0, ""), ("hangar", "PORT LAUNCH BAY", "top", 0.12, 0.26, 0, "start"),
    ("hangar", "STARBOARD LAUNCH BAY", "bot", 0.12, 0.26, 0, "exit"), ("hall", "ENTRY TUNNEL", "top", 0.26, 0.33, 0, ""),
    ("crew", "BARRACKS", "bot", 0.26, 0.40, 1, ""), ("hall", "MUSTER HALL", "top", 0.33, 0.50, 3, ""),
    ("med", "MEDICAL BAY", "bot", 0.40, 0.50, 0, ""), ("lift", "DESCENT RAMP", "top", 0.50, 0.55, 0, "down"),
    ("lift", "BRIDGE LIFT", "bot", 0.56, 0.61, 0, "lift"), ("cargo", "CARGO HALL", "top", 0.55, 0.80, 3, ""),
    ("cargo", "FORWARD HOLD", "bot", 0.61, 0.76, 2, ""), ("lift", "FORWARD RAMP", "bot", 0.76, 0.82, 0, "down"), ("command", "SENSOR BAY", "both", 0.82, 1.0, 0, "")]),
  ("DECK 3 · BELLY", 0.92, [
    ("engine", "ENGINE ROOM", "both", 0.0, 0.18, 1, ""), ("engine", "FUEL & COOLANT", "top", 0.18, 0.30, 0, ""),
    ("engine", "MAINTENANCE", "bot", 0.18, 0.30, 0, ""), ("reactor", "REACTOR ROOM", "both", 0.30, 0.50, 2, "goal"),
    ("lift", "DESCENT RAMP", "top", 0.50, 0.55, 0, "up"), ("lift", "BELLY RAMP", "bot", 0.50, 0.55, 0, "up"),
    ("hall", "BELLY RUN", "both", 0.55, 0.76, 0, ""), ("lift", "FORWARD RAMP", "bot", 0.76, 0.82, 0, "up"), ("cargo", "MUNITIONS", "top", 0.76, 1.0, 1, ""), ("engine", "BALLAST", "bot", 0.82, 1.0, 0, "")]),
]
def battleship_back(code, out):
    c = Image.new("RGBA", (W, H), (236, 238, 240, 255)); d = ImageDraw.Draw(c)
    d.text((36, 22), "IMPERIUM BATTLESHIP · DECK PLAN", font=fnt("InterDisplay-Bold.otf", 44), fill=(30, 36, 46))
    d.text((36, 76), "BOARD AT THE PORT LAUNCH BAY · DOWN TO THE REACTOR · OUT THROUGH THE STARBOARD BAY", font=fnt("Inter-SemiBold.otf", 19), fill=(80, 90, 104))
    d.text((W - 36, 34), code, font=fnt("Inter-SemiBold.otf", 20), fill=(80, 90, 104), anchor="ra")
    PW, PH = 1290, 330
    legend = []; num = 0
    for di, (dname, scale, specs) in enumerate(DECKS):
        oy = 118 + di * (PH + 22)
        mw, mh = int(PW * scale), int(PH * (0.82 + 0.18 * scale))
        ox = 30 + (PW - mw) // 2 + (int(PW * (1 - scale) * 0.35) if scale < 1 else 0)
        mask, hull_img = hull_mask(mw, mh)
        # the hull itself (a darker shell round the decks)
        shell = Image.fromarray((mask * 255).astype(np.uint8))
        sh = Image.new("RGBA", (mw, mh), HULL + (255,)); c.paste(sh, (ox, oy + (PH - mh) // 2), shell)
        inner = np.array(shell.filter(ImageFilter.MinFilter(15))) > 0
        lab = np.zeros(mask.shape, np.int32)
        spine0, spine1 = int(mh * 0.45), int(mh * 0.55)
        rooms = {1: {"kind": "corridor"}}
        xs = np.arange(mw)[None, :]; ys = np.arange(mh)[:, None]
        lab[inner & (ys >= spine0) & (ys < spine1)] = 1   # the spine corridor, stern to nose
        doors = []
        rid = 2; marks = []
        for kind, name, side, x0, x1, guards, mk in specs:
            X0, X1 = int(x0 * mw), int(x1 * mw)
            yr = (ys < spine0) if side == "top" else (ys >= spine1) if side == "bot" else np.ones_like(ys, bool)
            reg = inner & (xs >= X0) & (xs < X1) & yr
            if side == "both": reg &= ~((ys >= spine0) & (ys < spine1)) | True
            if reg.sum() < 200: continue
            lab[reg] = rid
            num += 1
            rooms[rid] = {"kind": kind, "num": num}
            ry, rx = np.nonzero(reg); cx, cy = int(rx.mean()), int(ry.mean())
            if side != "both":   # a door onto the spine
                dy = spine0 - 6 if side == "top" else spine1 - 3
                doors.append((cx - 14, dy - 4, 28, 14))
            else:   # spine passes through: open both ends
                doors.append((X0 - 4, spine0 + 2, 10, spine1 - spine0 - 4)); doors.append((X1 - 6, spine0 + 2, 10, spine1 - spine0 - 4))
            marks.append((cx, cy, num, guards, mk, name, kind, rx.min(), rx.max(), ry.min(), ry.max()))
            legend.append((di + 1, num, name, kind))
            rid += 1
        # spine doors through every crossing wall
        for xx in range(0, mw, 6): pass
        img = render_rooms(lab, rooms, doors, (mw, mh))
        # open the spine all the way (it is one corridor)
        c.alpha_composite(img, (ox, oy + (PH - mh) // 2))
        d = ImageDraw.Draw(c); bx, by = ox, oy + (PH - mh) // 2
        for cx, cy, n, g, mk, name, kind, rx0, rx1, ry0, ry1 in marks:
            px, py = bx + cx, by + cy
            if mk == "start": d.polygon([(px - 16, py - 20), (px + 20, py), (px - 16, py + 20)], fill=GRN, outline=(255, 255, 255), width=3)
            elif mk == "goal": d.regular_polygon((px, py, 26), 5, fill=AMB, outline=(255, 255, 255))
            elif mk == "exit": d.rectangle([px - 18, py - 18, px + 18, py + 18], outline=CYN, width=6)
            elif mk in ("lift", "down", "up"): d.text((px, py), {"lift": "▲▼", "down": "▼", "up": "▲"}[mk], font=fnt("InterDisplay-Bold.otf", 24 if mk == "lift" else 30), fill=(255, 255, 255), anchor="mm", stroke_width=3, stroke_fill=WALL)
            if mk not in ("start", "goal", "exit", "lift", "down", "up"):
                d.ellipse([px - 17, py - 17, px + 17, py + 17], fill=(255, 255, 255), outline=WALL, width=3)
                d.text((px, py + 1), str(n), font=fnt("InterDisplay-Bold.otf", 19), fill=WALL, anchor="mm")
            else:
                d.ellipse([px + 22, py - 30, px + 50, py - 2], fill=(255, 255, 255), outline=WALL, width=2)
                d.text((px + 36, py - 16), str(n), font=fnt("InterDisplay-Bold.otf", 15), fill=WALL, anchor="mm")
            for gi in range(g):
                gx = bx + rx0 + (rx1 - rx0) * (0.25 + 0.5 * ((gi * 0.618 + 0.2) % 1)); gy = by + ry0 + (ry1 - ry0) * (0.25 + 0.5 * ((gi * 0.382 + 0.6) % 1))
                d.rectangle([gx - 8, gy - 8, gx + 8, gy + 8], fill=RED, outline=(255, 255, 255), width=2)
            if mk == "mech": d.text((px, py + 26), "MECH", font=fnt("InterDisplay-Bold.otf", 15), fill=RED, anchor="ma")
            if mk == "goal": d.text((px, py + 30), "BOSS", font=fnt("InterDisplay-Bold.otf", 15), fill=RED, anchor="ma")
        d.text((ox - 4, oy + 6), dname, font=fnt("InterDisplay-Bold.otf", 22), fill=(30, 36, 46))
    # the key
    kx = 1350; ky = 118
    d.rectangle([kx - 14, ky - 8, W - 20, H - 20], fill=(250, 250, 252), outline=(190, 196, 204), width=2)
    cur = 0; fk = fnt("Inter-SemiBold.otf", 17)
    for dk, n, name, kind in legend:
        if dk != cur:
            cur = dk; d.text((kx, ky), "DECK %d" % dk, font=fnt("InterDisplay-Bold.otf", 19), fill=(30, 36, 46)); ky += 28
        d.rectangle([kx, ky + 3, kx + 14, ky + 17], fill=KIND[kind], outline=WALL)
        d.text((kx + 22, ky), "%d  %s" % (n, name), font=fk, fill=(40, 46, 56)); ky += 24
    ky += 10
    for sym, txt, col in [("▶", "Start", GRN), ("★", "Reactor: objective", AMB), ("□", "Exit", CYN), ("■", "Guard", RED), ("▲▼", "Lift (up and down)", WALL), ("▼ ▲", "Ramp down / up to the next deck", WALL)]:
        d.text((kx, ky), sym, font=fnt("InterDisplay-Bold.otf", 17), fill=col); d.text((kx + 60, ky), txt, font=fk, fill=(40, 46, 56)); ky += 24
    d.text((kx, H - 66), "1 grid square = 1 move", font=fk, fill=(80, 90, 104))
    d.text((W - 36, H - 40), "HOMELANCER", font=fnt("InterDisplay-Bold.otf", 22), fill=(30, 36, 46), anchor="ra")
    c.convert("RGB").save(out, dpi=(300, 300))

if __name__ == "__main__":
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    battleship_back("HL-SOL-B01-B", f"{out}/battleship_back.png")
    print("ok")

# ------------------------------------------------------------------ facility (Zelda-style dungeon on the game's grid)
CELL = 360.0
def facility_back(F_, code, out):
    rooms = F_["rooms"]
    halls = {k: r for k, r in rooms.items() if not r.get("hex")}
    tunnels = {k: r for k, r in rooms.items() if r.get("hex")}
    cell = {}
    for k, r in halls.items():
        x0, x1, z0, z1 = r["r"]; cell[k] = (round(((x0 + x1) / 2) / CELL), round(((z0 + z1) / 2) / CELL))
    cxs = [v[0] for v in cell.values()]; czs = [v[1] for v in cell.values()]
    ncol, nrow = max(cxs) - min(cxs) + 1, max(czs) - min(czs) + 1
    MW, MH = 1740, 760
    S = int(min(MW / ncol, MH / nrow, 240))
    gw, gh = S * ncol, S * nrow
    ox, oy = 30 + (MW - gw) // 2, 130 + (MH - gh) // 2
    lab = np.zeros((gh, gw), np.int32)
    order = [k for k in F_["route_in"] + F_["route_out"] if k in halls]
    order = list(dict.fromkeys(order)) + [k for k in halls if k not in order]
    num = {k: i + 1 for i, k in enumerate(order)}
    ys = sorted(set(round(min(r["y"])) for r in halls.values()), reverse=True)
    nlev = max(1, int(F_["info"].get("levels", len(ys))))   # the game's own floor count; the many small drops are banded into it
    depth = {k: round(ys.index(round(min(halls[k]["y"]))) * (nlev - 1) / max(1, len(ys) - 1)) for k in halls}
    info = {}
    for i, k in enumerate(order):
        cx, cz = cell[k][0] - min(cxs), cell[k][1] - min(czs)
        lab[cz * S:(cz + 1) * S, cx * S:(cx + 1) * S] = i + 1
        info[i + 1] = {"kind": "reactor" if k == "reactor" else "hangar" if k in ("lbay", "sbay") else "hall"}
    # doors: where a tunnel joins two rooms in neighbouring cells
    doors = []; ramps = []
    for tk, t in tunnels.items():
        tx0, tx1, tz0, tz1 = t["r"]; tcx, tcz = (tx0 + tx1) / 2 / CELL, (tz0 + tz1) / 2 / CELL
        px = (tcx - min(cxs) + 0.5) * S; pz = (tcz - min(czs) + 0.5) * S
        horiz = (tx1 - tx0) > (tz1 - tz0)
        doors.append((int(px - 8), int(pz - S * 0.13), 16, int(S * 0.26)) if horiz else (int(px - S * 0.13), int(pz - 8), int(S * 0.26), 16))
        if abs(t["y"][0] - t["y"][1]) > 1: ramps.append((px, pz))
    img = render_rooms(lab, info, doors, (gw, gh), grid=max(18, S // 6))
    # deeper rooms darker (each depth is a floor further down)
    arr = np.array(img).astype(np.float32)
    for i, k in enumerate(order):
        m = lab == (i + 1); f = 1.0 - 0.32 * depth[k] / max(1, nlev - 1)
        arr[m, :3] *= f
    img = Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA")
    c = Image.new("RGBA", (W, H), (236, 238, 240, 255)); d = ImageDraw.Draw(c)
    d.text((36, 22), F_["name"].upper() + " · DUNGEON", font=fnt("InterDisplay-Bold.otf", 42), fill=(30, 36, 46))
    d.text((36, 76), "%s FACILITY · LEVEL %d · %d FLOORS · ENTRY BAY DOWN TO THE REACTOR HALL, OUT BY THE EXIT SHAFT" % (F_["faction"].upper(), F_["level"], nlev), font=fnt("Inter-SemiBold.otf", 19), fill=(80, 90, 104))
    d.text((W - 36, 34), code, font=fnt("Inter-SemiBold.otf", 20), fill=(80, 90, 104), anchor="ra")
    # rock round the dungeon
    rock = Image.new("RGBA", (gw + 40, gh + 40), (150, 140, 128, 255)); c.alpha_composite(rock, (ox - 20, oy - 20))
    c.alpha_composite(img, (ox, oy)); d = ImageDraw.Draw(c)
    for i, k in enumerate(order):
        r = halls[k]; cx, cz = cell[k][0] - min(cxs), cell[k][1] - min(czs)
        x0, y0 = ox + cx * S, oy + cz * S; mx, my = x0 + S / 2, y0 + S / 2
        sh = r.get("shape", "rect")
        if sh == "ring": d.ellipse([mx - S * 0.22, my - S * 0.22, mx + S * 0.22, my + S * 0.22], outline=WALL, width=5)
        if sh == "pillars":
            for sx in (-1, 1):
                for sz in (-1, 1): d.rectangle([mx + sx * S * 0.24 - 9, my + sz * S * 0.24 - 9, mx + sx * S * 0.24 + 9, my + sz * S * 0.24 + 9], fill=WALL)
        if sh == "split": d.line([(x0 + S * 0.2, my), (x0 + S * 0.42, my)], fill=WALL, width=7); d.line([(x0 + S * 0.58, my), (x0 + S * 0.8, my)], fill=WALL, width=7)
        if sh == "poly":
            q = S * 0.16
            for (ax, ay, bx, by) in [(x0, y0, 1, 1), (x0 + S, y0, -1, 1), (x0, y0 + S, 1, -1), (x0 + S, y0 + S, -1, -1)]:
                d.polygon([(ax, ay), (ax + bx * q, ay), (ax, ay + by * q)], fill=WALL)
        n = num[k]
        if k == F_["route_in"][0]: d.polygon([(mx - 18, my - 22), (mx + 22, my), (mx - 18, my + 22)], fill=GRN, outline=(255, 255, 255), width=3)
        elif k == "reactor": d.regular_polygon((mx, my, 28), 5, fill=AMB, outline=(255, 255, 255)); d.text((mx, my + 34), "BOSS", font=fnt("InterDisplay-Bold.otf", 15), fill=RED, anchor="ma")
        elif k == F_["route_out"][-1]: d.rectangle([mx - 20, my - 20, mx + 20, my + 20], outline=CYN, width=6)
        d.ellipse([x0 + 8, y0 + 8, x0 + 40, y0 + 40], fill=(255, 255, 255), outline=WALL, width=3)
        d.text((x0 + 24, y0 + 25), str(n), font=fnt("InterDisplay-Bold.otf", 17), fill=WALL, anchor="mm")
        d.text((x0 + S - 10, y0 + 12), "B%d" % (depth[k] + 1), font=fnt("Inter-SemiBold.otf", 15), fill=(70, 76, 86), anchor="ra")
        for gi in range(int(r.get("guards", 0))):
            gx = x0 + S * (0.3 + 0.4 * ((gi * 0.618 + 0.15) % 1)); gy = y0 + S * (0.62 + 0.2 * ((gi * 0.382) % 1))
            d.rectangle([gx - 9, gy - 9, gx + 9, gy + 9], fill=RED, outline=(255, 255, 255), width=2)
    for px, pz in ramps: d.text((ox + px, oy + pz), "▼", font=fnt("InterDisplay-Bold.otf", 22), fill=(255, 255, 255), anchor="mm", stroke_width=4, stroke_fill=WALL)
    # the key, under the map in columns
    ky0 = 130 + MH + 16
    d.rectangle([20, ky0 - 8, W - 20, H - 16], fill=(250, 250, 252), outline=(190, 196, 204), width=2)
    fk = fnt("Inter-SemiBold.otf", 16)
    cols = [36, 470, 904]; per = 9
    for i2, k in enumerate(order[:per * 3]):
        r = halls[k]; x = cols[i2 // per]; y = ky0 + 4 + (i2 % per) * 21
        d.text((x, y), "%d  %s · B%d%s" % (num[k], r.get("label", k), depth[k] + 1, " · %d guards" % r["guards"] if r.get("guards") else ""), font=fk, fill=(40, 46, 56))
    kx, ky = 1338, ky0 + 4
    for sym, txt, col in [("▶", "Start (entry bay)", GRN), ("★", "Reactor: objective + boss", AMB), ("□", "Exit shaft", CYN), ("■", "Guard", RED), ("▼", "Ramp down a floor", WALL), ("B1", "Floor (deeper = darker)", WALL), ("", "1 grid square = 1 move", WALL)]:
        d.text((kx, ky), sym, font=fnt("InterDisplay-Bold.otf", 16), fill=col); d.text((kx + 40, ky), txt, font=fk, fill=(40, 46, 56)); ky += 21
    d.text((W - 36, H - 40), "HOMELANCER", font=fnt("InterDisplay-Bold.otf", 22), fill=(30, 36, 46), anchor="ra")
    c.convert("RGB").save(out, dpi=(300, 300))
