# Homelancer tabletop: the 4 x 6 in LANDSCAPE reference card (front) and the token sheet. One template for everything:
# left 3.6 in = the art, right 2.4 in = the information panel. The back of a facility or ship card is its dungeon map.
import json, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
F = "/usr/share/fonts/opentype/inter/"
def fnt(n, sz): return ImageFont.truetype(F + n, int(sz))
HOLO = os.environ.get("HL_BOARD_HOLO", "/tmp/claude-0/board/wire")
CY = (95, 215, 255); FAC = {"Unity": (90, 190, 255), "Elyza": (255, 170, 80), "Imperium": (240, 90, 90), "Liberator": (110, 230, 170), "Raiders": (200, 200, 200)}
W, H, ART = 1800, 1200, 1080
def wrap(d, text, f, w):
    out, line = [], ""
    for wd in text.split():
        t = (line + " " + wd).strip()
        if d.textlength(t, font=f) > w: out.append(line); line = wd
        else: line = t
    return out + [line]
def holo_img(file, box_w, box_h, col=None):
    im = Image.open(f"{HOLO}/{file}.png").convert("RGBA"); im.thumbnail((box_w, box_h), Image.LANCZOS)
    if col:
        r_, g_, b_, a_ = im.split(); lum = Image.merge("RGB", (r_, g_, b_)).convert("L").point(lambda v: min(255, int(v * 1.5)))
        im = Image.merge("RGBA", [lum.point(lambda v, c=c: int(v * (0.35 + 0.65 * c / 255))) for c in col] + [a_])
    return im
def card(name, kind_line, faction, model, sections, code, art_note=None):
    col = FAC.get(faction, CY)
    c = Image.new("RGBA", (W, H), (6, 12, 26, 255)); d = ImageDraw.Draw(c)
    for y in range(0, H, 40): d.line([(0, y), (ART, y)], fill=(11, 30, 55))
    for x in range(0, ART, 40): d.line([(x, 0), (x, H)], fill=(11, 30, 55))
    # ART (left): the model as a hologram on the blueprint, glow in the side's colour
    glow = Image.new("RGBA", c.size, (0, 0, 0, 0)); ImageDraw.Draw(glow).ellipse([ART / 2 - 420, H / 2 - 300, ART / 2 + 420, H / 2 + 300], fill=col + (70,))
    c.alpha_composite(glow.filter(ImageFilter.GaussianBlur(110)))
    im = holo_img(model, ART - 120, H - 300, col)
    c.alpha_composite(im, (int(ART / 2 - im.width / 2), int(H / 2 - im.height / 2 + 20)))
    d = ImageDraw.Draw(c)
    d.text((40, 36), name.upper(), font=fnt("InterDisplay-Bold.otf", 56 if len(name) < 22 else 44), fill=(240, 250, 255), stroke_width=4, stroke_fill=(0, 0, 0))
    d.text((40, 104), kind_line, font=fnt("Inter-SemiBold.otf", 24), fill=col, stroke_width=3, stroke_fill=(0, 0, 0))
    if art_note: d.text((40, H - 56), art_note, font=fnt("Inter-SemiBold.otf", 18), fill=(150, 190, 220))
    # INFO (right): fixed headings, any section can grow
    d.rectangle([ART, 0, W, H], fill=(9, 20, 38, 255)); d.line([(ART, 0), (ART, H)], fill=col, width=6)
    y = 36; x = ART + 34; wmax = W - x - 34
    fh = fnt("InterDisplay-Bold.otf", 22); fb = fnt("Inter-SemiBold.otf", 21)
    for head, body in sections:
        d.text((x, y), head, font=fh, fill=col); y += 32
        lines = body if isinstance(body, list) else wrap(d, body, fb, wmax)
        for ln in lines:
            d.text((x, y), ln, font=fb, fill=(225, 238, 250)); y += 29
        y += 16
    d.text((x, H - 92), "HOMELANCER", font=fnt("InterDisplay-Bold.otf", 30), fill=(240, 250, 255))
    d.text((x, H - 54), "homelancergame.com", font=fnt("Inter-SemiBold.otf", 18), fill=CY)
    d.text((W - 34, H - 54), code, font=fnt("Inter-SemiBold.otf", 18), fill=(130, 210, 255), anchor="ra")
    return c.convert("RGB")

def token(model, label, col, w_in, h_in, fill=None):   # a flat cut-out token, top-down silhouette
    tw, th = int(w_in * 300), int(h_in * 300)
    t = Image.new("RGBA", (tw, th), (0, 0, 0, 0)); d = ImageDraw.Draw(t)
    d.rounded_rectangle([4, 4, tw - 5, th - 5], radius=34, fill=(10, 18, 32, 255), outline=col + (255,), width=10)
    if model:
        im = holo_img(model, tw - 70, th - 90, col)
        if w_in > h_in: im = holo_img(model, th - 90, tw - 70, col).rotate(-90, expand=True)   # (long ships lie along the token)
        t.alpha_composite(im, (int(tw / 2 - im.width / 2), int((th - 40) / 2 - im.height / 2 + 6)))
    elif fill:
        fill(d, tw, th)
    d.text((tw / 2, th - 22), label, font=fnt("InterDisplay-Bold.otf", 26 if h_in >= 1 else 20), fill=(240, 250, 255), anchor="ms")
    return t

if __name__ == "__main__":
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    D = json.load(open(sys.argv[2])); P = json.load(open(sys.argv[3]))
    keys = sorted(D["facilities"])
    models = {}
    for pid, pl in P.items():
        for f in pl["facilities"]: models["%s|%s|%d" % (pid, f["name"], f["tile"])] = f.get("model", "")
    for i, k in enumerate(keys):
        F_ = D["facilities"][k]; pid = k.split("|")[0]; pl = P[pid]
        guards = sum(int(r.get("guards", 0)) for r in F_["rooms"].values())
        sec = "ABCDEFG"[F_["tile"] // pl["grid"]] + str(F_["tile"] % pl["grid"] + 1)
        nm = F_["name"].replace(pl["name"] + " ", "").replace("Solara Haven ", "").replace("Solara ", "")
        sections = [
            ("WHERE", "%s · sector %s (%s)" % (pl["name"], sec, pl["tiles"][F_["tile"]]["name"])),
            ("SECURITY", ["Level %d of 4" % F_["level"], "%d depths · %d areas" % (int(F_["info"].get("levels", 1)), len(F_["rooms"])), "%d guards inside" % guards]),
            ("OBJECTIVE", "Fight down to the REACTOR HALL and destroy the reactor, then get out through the EXIT SHAFT."),
            ("SPECIAL RULE", "When the reactor blows, the way you came in seals behind you. Escape by the escape halls."),
            ("REWARD", "1,500 cr (facility job)"),
            ("MAP", "Interior on the back of this card."),
        ]
        card(nm, "%s FACILITY · LEVEL %d" % (F_["faction"].upper(), F_["level"]), F_["faction"], models.get(k, "HL_FAC_Garage_HeavyRectangular"), sections, "HL-SOL-F%02d" % (i + 1)).save(f"{out}/facility_{i + 1}_front.png", dpi=(300, 300))
    S_ = D["ship"]; guards = sum(int(r.get("guards", 0)) for r in S_["rooms"].values())
    sections = [("WHERE", "Hidden in the Frost Veil (Solara B4), or leading an invasion fleet."),
        ("SECURITY", ["3 decks · %d areas" % len(S_["rooms"]), "%d guards, a boss at the reactor, a mech on the bridge" % guards]),
        ("OBJECTIVE", "Board at the PORT LAUNCH BAY, go down to the REACTOR ROOM in the belly and destroy it, then escape through the STARBOARD LAUNCH BAY."),
        ("SPECIAL RULE", "When the reactor blows, the descent ramp seals and the belly ramp opens: the only way out."),
        ("REWARD", "9,000 cr (disturbance: battleship)"), ("MAP", "Three decks on the back of this card.")]
    card("Imperium Battleship", "IMPERIUM CAPITAL SHIP · 3 DECKS", "Imperium", "imperium_battleship", sections, "HL-SOL-B01").save(f"{out}/battleship_front.png", dpi=(300, 300))
    # the token sheet: one 4 x 6 landscape card of cut-outs
    sheet = Image.new("RGBA", (W, H), (255, 255, 255, 255)); d = ImageDraw.Draw(sheet)
    d.text((30, 20), "SOLARA TOKENS · cut on the lines · 1 in, 2 x 1 in, 3 x 1 in", font=fnt("Inter-SemiBold.otf", 26), fill=(40, 60, 90))
    def star(d, tw, th): d.regular_polygon((tw / 2, (th - 40) / 2, 70), 5, fill=(255, 196, 90), outline=(255, 255, 255))
    def guard(d, tw, th): d.rectangle([tw / 2 - 55, (th - 40) / 2 - 55, tw / 2 + 55, (th - 40) / 2 + 55], fill=(240, 80, 80), outline=(255, 255, 255), width=6)
    row1 = [("t_cadet", "YOU · CADET", FAC["Unity"]), ("t_unity_fighter", "UNITY FIGHTER", FAC["Unity"]), ("t_lib_fighter", "LIBERATOR", FAC["Liberator"]),
            ("t_imp_fighter", "IMP. FIGHTER", FAC["Imperium"]), ("t_imp_gunship", "IMP. GUNSHIP", FAC["Imperium"])]
    x, y = 30, 80
    for m, lab, col in row1:
        tk = token(m, lab, col, 1, 1); sheet.alpha_composite(tk, (x, y)); x += 330
    x, y = 30, 420
    for m, lab, col, w in [("t_imp_frigate", "IMPERIUM FRIGATE", FAC["Imperium"], 2), ("t_freighter", "FREIGHTER (ESCORT)", FAC["Unity"], 2)]:
        tk = token(m, lab, col, w, 1); sheet.alpha_composite(tk, (x, y)); x += w * 300 + 30
    x, y = 30, 760
    tk = token("t_imp_battleship", "IMPERIUM BATTLESHIP · B01", FAC["Imperium"], 3, 1); sheet.alpha_composite(tk, (x, y)); x += 930
    for lab, fn in [("OBJECTIVE", star), ("GUARD", guard)]:
        tk = token(None, lab, (230, 230, 230), 1, 1, fn); sheet.alpha_composite(tk, (x, y)); x += 330
    d = ImageDraw.Draw(sheet)
    d.text((W - 30, H - 40), "HOMELANCER · HL-SOL-TOKENS-01", font=fnt("Inter-SemiBold.otf", 20), fill=(40, 60, 90), anchor="ra")
    sheet.convert("RGB").save(f"{out}/tokens_sheet.png", dpi=(300, 300))
    print("ok")
