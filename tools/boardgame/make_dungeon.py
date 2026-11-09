# Homelancer tabletop: a facility or battleship interior as a playable top-down map (the back of its 4 x 6 landscape card).
# Drawn straight from the game's own layout (Boarding.facility / Boarding.SHIP_ROOMS, dumped by HL_DUNGEONS).
import json, math, os, sys, ast
from PIL import Image, ImageDraw, ImageFont
F = "/usr/share/fonts/opentype/inter/"
def fnt(n, sz): return ImageFont.truetype(F + n, int(sz))
CY = (95, 215, 255); RED = (240, 80, 80); GRN = (110, 240, 150); AMB = (255, 196, 90)
W, H = 1800, 1200
def depth_col(k):   # shallow = light steel, deep = dark blue
    a = (150, 175, 200); b = (40, 70, 120)
    return tuple(int(a[i] + (b[i] - a[i]) * k) for i in range(3))
def room_poly(r, R):
    x0, x1, z0, z1 = r["r"]; cx, cz, hx, hz = (x0 + x1) / 2, (z0 + z1) / 2, (x1 - x0) / 2, (z1 - z0) / 2
    if r.get("shape") == "poly" and r.get("poly"):
        pts = ast.literal_eval(r["poly"]); return [(cx + px * hx, cz + pz * hz) for px, pz in pts]
    if r.get("shape") == "ring": return [(cx + math.cos(a) * hx, cz + math.sin(a) * hz) for a in [i * math.tau / 32 for i in range(32)]]
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
def draw_plan(d, rooms, box, route_in, route_out, core_key, deck_filter=None, ylo=None, yhi=None, bounds_from=None):
    keys = [k for k in rooms if deck_filter is None or deck_filter(rooms[k])]
    bf = bounds_from if bounds_from is not None else {q: rooms[q] for q in keys}
    xs = [v for r in bf.values() for v in r["r"][:2]]; zs = [v for r in bf.values() for v in r["r"][2:]]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    bx0, by0, bx1, by1 = box
    k = min((bx1 - bx0) / (x1 - x0), (by1 - by0) / (z1 - z0)) * 0.96
    ox = bx0 + ((bx1 - bx0) - (x1 - x0) * k) / 2 - x0 * k; oy = by0 + ((by1 - by0) - (z1 - z0) * k) / 2 - z0 * k
    P = lambda x, z: (ox + x * k, oy + z * k)
    yl = [min(r["y"]) for r in rooms.values()]; lo, hi = (min(yl) if ylo is None else ylo), (max(yl) if yhi is None else yhi)
    # tunnels first (under the rooms), then rooms
    order = sorted(keys, key=lambda q: 0 if rooms[q].get("hex") else 1)
    for q in order:
        r = rooms[q]; dk = (hi - min(r["y"])) / max(hi - lo, 1)
        poly = [P(x, z) for x, z in room_poly(r, rooms)]
        col = depth_col(dk)
        if r.get("hex"):
            d.polygon(poly, fill=tuple(int(c * 0.55) for c in col) + (255,), outline=(170, 205, 235, 255), width=2)
        else:
            d.polygon(poly, fill=col + (255,), outline=(235, 248, 255, 255), width=4)
            # a movement grid inside the room (one square = 40 m)
            rx0, rx1, rz0, rz1 = r["r"]; g = 40.0
            gx = rx0 + g
            while gx < rx1: d.line([P(gx, rz0), P(gx, rz1)], fill=(255, 255, 255, 50), width=1); gx += g
            gz = rz0 + g
            while gz < rz1: d.line([P(rx0, gz), P(rx1, gz)], fill=(255, 255, 255, 50), width=1); gz += g
    # sloped tunnels / ramps: an arrow going down
    for q in keys:
        r = rooms[q]
        if r.get("hex") and abs(r["y"][0] - r["y"][1]) > 1:
            x0r, x1r, z0r, z1r = r["r"]; c = P((x0r + x1r) / 2, (z0r + z1r) / 2)
            d.text(c, "▼" if True else "", font=fnt("Inter-SemiBold.otf", 22), fill=(255, 255, 255, 230), anchor="mm")
    # guards: red squares spread in the room; labels for the key rooms
    for q in keys:
        r = rooms[q]; x0r, x1r, z0r, z1r = r["r"]; n = int(r.get("guards", 0))
        for i in range(n):
            gx = x0r + (x1r - x0r) * (0.3 + 0.4 * ((i * 0.618) % 1)); gz = z0r + (z1r - z0r) * (0.3 + 0.4 * ((i * 0.382 + 0.5) % 1))
            px, py = P(gx, gz); s = 9
            d.rectangle([px - s, py - s, px + s, py + s], fill=RED + (255,), outline=(255, 255, 255, 255), width=2)
    return P, k
def wrap(d, text, f, w):
    out, line = [], ""
    for wd in text.split():
        t = (line + " " + wd).strip()
        if d.textlength(t, font=f) > w: out.append(line); line = wd
        else: line = t
    return out + [line]
def frame(title, sub, code):
    c = Image.new("RGBA", (W, H), (6, 12, 26, 255)); d = ImageDraw.Draw(c)
    for y in range(0, H, 40): d.line([(0, y), (W, y)], fill=(11, 30, 55))
    for x in range(0, W, 40): d.line([(x, 0), (x, H)], fill=(11, 30, 55))
    d.rectangle([0, 0, W, 110], fill=(8, 20, 40, 255)); d.line([(0, 110), (W, 110)], fill=CY, width=3)
    d.text((36, 18), title, font=fnt("InterDisplay-Bold.otf", 50), fill=(240, 250, 255))
    d.text((36, 74), sub, font=fnt("Inter-SemiBold.otf", 22), fill=CY)
    d.text((W - 36, 40), code, font=fnt("Inter-SemiBold.otf", 20), fill=(130, 210, 255), anchor="ra")
    return c, d
def legend(d, y):
    x = 36; f = fnt("Inter-SemiBold.otf", 20)
    items = [("start", GRN), ("goal", AMB), ("exit", CY), ("guard", RED)]
    d.polygon([(x, y), (x + 22, y + 11), (x, y + 22)], fill=GRN); d.text((x + 32, y), "START", font=f, fill=(220, 235, 250)); x += 140
    d.regular_polygon((x + 11, y + 11, 13), 5, fill=AMB); d.text((x + 32, y), "OBJECTIVE", font=f, fill=(220, 235, 250)); x += 190
    d.rectangle([x, y, x + 22, y + 22], outline=CY, width=4); d.text((x + 32, y), "EXIT", font=f, fill=(220, 235, 250)); x += 120
    d.rectangle([x + 2, y + 2, x + 20, y + 20], fill=RED, outline=(255, 255, 255), width=2); d.text((x + 32, y), "GUARD", font=f, fill=(220, 235, 250)); x += 150
    d.text((x, y), "▼ RAMP DOWN", font=f, fill=(220, 235, 250)); x += 190
    d.text((x, y), "1 GRID SQUARE = ONE MOVE", font=f, fill=(220, 235, 250)); x += 330
    for i, lab in enumerate(["SHALLOW", "DEEP"]):
        d.rectangle([x + i * 150, y, x + i * 150 + 22, y + 22], fill=depth_col(i)); d.text((x + i * 150 + 30, y), lab, font=f, fill=(220, 235, 250))
def mark(d, P, rooms, key, kind):
    r = rooms[key]; x0, x1, z0, z1 = r["r"]; px, py = P((x0 + x1) / 2, (z0 + z1) / 2)
    if kind == "start": d.polygon([(px - 18, py - 22), (px + 24, py), (px - 18, py + 22)], fill=GRN, outline=(255, 255, 255), width=3)
    elif kind == "goal": d.regular_polygon((px, py, 30), 5, fill=AMB, outline=(255, 255, 255))
    else: d.rectangle([px - 22, py - 22, px + 22, py + 22], outline=CY, width=6)
    lab = r.get("label", key)
    d.text((px, py + 34), lab, font=fnt("InterDisplay-Bold.otf", 22), fill=(255, 255, 255), anchor="ma", stroke_width=4, stroke_fill=(0, 0, 0))

def facility_back(F_, code):
    rooms = F_["rooms"]; info = F_["info"]
    c, d = frame(F_["name"].upper() + " · INTERIOR", "%s FACILITY · LEVEL %d · %d DEPTHS · %d AREAS" % (F_["faction"].upper(), F_["level"], int(info.get("levels", 1)), len(rooms)), code)
    P, k = draw_plan(d, rooms, (36, 140, W - 36, H - 90), F_["route_in"], F_["route_out"], "reactor")
    mark(d, P, rooms, F_["route_in"][0], "start"); mark(d, P, rooms, "reactor", "goal"); mark(d, P, rooms, F_["route_out"][-1], "exit")
    legend(d, H - 60)
    return c.convert("RGB")

def ship_back(S_, name, code):
    rooms = S_["rooms"]
    c, d = frame(name.upper() + " · INTERIOR", "BATTLESHIP · 3 DECKS · %d AREAS" % len(rooms), code)
    def deck_of(r):
        lo, hi = min(r["y"]), max(r["y"])
        out = set()
        for i, (a, b) in enumerate([(30, 99), (-25, 29), (-999, -26)]):
            if (a <= lo <= b) or (a <= hi <= b): out.add(i)
        return out
    decks = [("BRIDGE DECK", lambda r: 0 in deck_of(r)), ("MAIN DECK", lambda r: 1 in deck_of(r)), ("BELLY DECK", lambda r: 2 in deck_of(r))]
    pw = (W - 36 * 2 - 40) / 3
    for i, (nm, flt) in enumerate(decks):
        bx0 = 36 + i * (pw + 20)
        d.rectangle([bx0, 140, bx0 + pw, H - 90], outline=(60, 110, 160), width=2)
        d.text((bx0 + 14, 150), "DECK %d · %s" % (i + 1, nm), font=fnt("InterDisplay-Bold.otf", 24), fill=CY)
        sub = {q: r for q, r in rooms.items() if flt(r)}
        P, k = draw_plan(d, sub, (bx0 + 10, 190, bx0 + pw - 10, H - 100), [], [], "", ylo=-100, yhi=40, bounds_from=rooms)
        for q, kind in [(S_["route_in"][0], "start"), ("reactor", "goal"), (S_["route_out"][-1], "exit")]:
            if q in sub: mark(d, P, sub, q, kind)
        for q, r in sub.items():   # lifts and ramps between decks
            if r.get("hex") and abs(r["y"][0] - r["y"][1]) > 1:
                x0, x1, z0, z1 = r["r"]; px, py = P((x0 + x1) / 2, (z0 + z1) / 2)
                d.text((px + 18, py + 30), "▲▼ " + r["label"], font=fnt("Inter-SemiBold.otf", 17), fill=(255, 255, 255), anchor="lm", stroke_width=3, stroke_fill=(0, 0, 0))
    legend(d, H - 60)
    return c.convert("RGB")

if __name__ == "__main__":
    D = json.load(open(sys.argv[1])); out = sys.argv[2]; os.makedirs(out, exist_ok=True)
    for i, key in enumerate(sorted(D["facilities"])):
        F_ = D["facilities"][key]
        facility_back(F_, "HL-SOL-F%02d-B" % (i + 1)).save(f"{out}/facility_{i + 1}_back.png", dpi=(300, 300))
    ship_back(D["ship"], "Imperium Battleship", "HL-SOL-B01-B").save(f"{out}/battleship_back.png", dpi=(300, 300))
    print("ok")
