#!/usr/bin/env python3
"""Unity Capital: a PROPOSED upper deck and lower deck (v13.00, owner: "two more ship levels, top and lower,
different rooms and smaller ... put in the elevator system ... only two or four").

There is no blueprint for these two decks. The layouts below are a graybox PROPOSAL for the owner to approve or
replace with his own plans; the room names are working labels, not lore. What is taken from the real plan:
the hull outline (each deck sits inside it, smaller) and the four lift shafts, which stay in the same place on
every deck: the two forward lifts (by the CIC) go UP, the two aft lifts (by the hangar) go DOWN.

  python3 decks_unity_capital.py assets/holodeck/unity_capital.json assets/holodeck [debug_dir]

Writes "decks" into the json (each: id, level, name, proposed, shell outlines, rooms, lifts, map) and a map
picture per deck (same framing as the plan, so the GPS dot lines up).
"""
import json, sys
import numpy as np, cv2

CELL = 4; EPS = 1.2; PLAYER_R = 3; CX = 512.5

def hull_px(d, H, W):
    h = np.array([[c != " " for c in row.ljust(d["w"])[:d["w"]]] for row in d["rows"]], np.uint8)
    h = cv2.resize(h, (d["w"] * CELL, d["h"] * CELL), interpolation=cv2.INTER_NEAREST)
    return np.pad(h, ((0, H - h.shape[0]), (0, W - h.shape[1])))

class Deck:
    def __init__(self, H, W):
        self.f = np.zeros((H, W), np.uint8); self.rooms = []; self.H = H; self.W = W
    def mir(self, pts): return [(2 * CX - x, y) for x, y in pts][::-1]
    def poly(self, pts, both=False):
        cv2.fillPoly(self.f, [np.round(np.array(pts)).astype(np.int32)], 1)
        if both: cv2.fillPoly(self.f, [np.round(np.array(self.mir(pts))).astype(np.int32)], 1)
    def box(self, x0, y0, x1, y1, ch=0, both=False):   # a room: chamfered corners, never a plain box
        self.poly([(x0 + ch, y0), (x1 - ch, y0), (x1, y0 + ch), (x1, y1 - ch), (x1 - ch, y1), (x0 + ch, y1), (x0, y1 - ch), (x0, y0 + ch)], both)
    def disc(self, x, y, r): cv2.circle(self.f, (int(x), int(y)), int(r), 1, -1)
    def room(self, name, x, y, names_both=None):
        self.rooms.append({"name": name, "at": [x, y]})
        if names_both: self.rooms.append({"name": names_both, "at": [2 * CX - x, y]})

def outlines(mask, want=1):
    H, W = mask.shape
    cs, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    out = []
    for c in cs:
        if len(c) < 12: continue
        a = cv2.approxPolyDP(c, EPS, True).reshape(-1, 2).astype(float)
        if len(a) < 3: continue
        a += 0.5; votes = 0
        for k in range(len(a)):
            p, q = a[k], a[(k + 1) % len(a)]; e = q - p; L = np.hypot(*e)
            if L < 3: continue
            m = (p + q) / 2 + np.array([e[1], -e[0]]) / L * 2.5
            x, y = int(m[0]), int(m[1])
            if 0 <= x < W and 0 <= y < H: votes += 1 if mask[y, x] == want else -1
        if votes < 0: a = a[::-1]
        out.append([round(float(v) / CELL, 3) for v in a.reshape(-1)])
    return out

def upper(H, W):
    k = Deck(H, W)
    # spine and the lift cross-passage (lifts at 463,474 and 557,474)
    k.box(503, 236, 522, 612)
    k.box(446, 464, 579, 484)
    k.box(447, 458, 479, 490, 4, True)                      # lift cars
    k.disc(512, 208, 40); k.room("Observation Lounge", 512, 200)
    k.box(417, 262, 492, 338, 12, True); k.box(490, 292, 505, 306, 0, True)
    k.room("Ready Room", 455, 300, "Comms Center")
    k.poly([(398, 360), (492, 360), (492, 446), (424, 446), (398, 420)], True); k.box(490, 396, 505, 410, 0, True)
    k.room("Captain's Quarters", 445, 400, "Officers' Quarters")
    k.poly([(430, 520), (492, 520), (492, 590), (452, 590), (430, 568)], True); k.box(490, 548, 505, 562, 0, True)
    k.room("Chart Room", 462, 552, "Signal Office")
    k.poly([(440, 622), (585, 622), (600, 640), (600, 690), (575, 712), (450, 712), (425, 690), (425, 640)])
    k.box(503, 606, 522, 626); k.room("Wardroom", 512, 668)
    lifts = [[463, 474], [557, 474]]
    return k, lifts, (150, 730)

def lower(H, W):
    k = Deck(H, W)
    # lift cross-passage (lifts at 366,840 and 658,840) and the spine
    k.box(326, 831, 699, 850)
    k.box(350, 824, 382, 857, 4, True)                      # lift cars
    k.box(503, 840, 522, 1215)
    k.poly([(395, 868), (492, 868), (492, 948), (420, 948), (395, 924)], True); k.box(490, 900, 505, 914, 0, True)
    k.room("Brig", 444, 906, "Machine Shop")
    k.poly([(292, 880), (382, 880), (382, 1010), (318, 1010), (292, 984)], True); k.box(330, 848, 346, 884, 0, True)
    k.room("Storage A", 338, 944, "Storage B")
    k.box(398, 968, 492, 1048, 12, True); k.box(490, 1000, 505, 1014, 0, True)
    k.room("Munitions Store", 445, 1008, "Water Reclamation")
    k.disc(512, 1118, 50); k.room("Life Support", 512, 1100)
    k.box(503, 1160, 522, 1215)
    k.poly([(455, 1208), (570, 1208), (585, 1224), (585, 1262), (565, 1280), (460, 1280), (440, 1262), (440, 1224)])
    k.room("Pump Room", 512, 1246)
    lifts = [[366, 840], [658, 840]]
    return k, lifts, (800, 1300)

def draw_map(k, hull, lifts, title, path):
    """A stand-in deck map in the plan's colours (dark blue, cyan lines), same framing as the real plan."""
    H, W = k.f.shape
    im = np.zeros((H, W, 3), np.uint8); im[:] = (40, 16, 8)
    im[hull > 0] = (70, 34, 14)
    im[k.f > 0] = (110, 62, 20)
    cs, _ = cv2.findContours(hull, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    cv2.drawContours(im, cs, -1, (160, 110, 40), 2, cv2.LINE_AA)
    cs, _ = cv2.findContours(k.f, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    cv2.drawContours(im, cs, -1, (255, 230, 90), 2, cv2.LINE_AA)
    for x, y in lifts:
        cv2.rectangle(im, (x - 11, y - 11), (x + 11, y + 11), (255, 255, 255), 2)
        cv2.putText(im, "LIFT", (x - 14, y + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.33, (255, 255, 255), 1, cv2.LINE_AA)
    for r in k.rooms:
        t = r["name"].upper(); sz = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, 0.36, 1)[0]
        cv2.putText(im, t, (int(r["at"][0] - sz[0] / 2), int(r["at"][1] + 4)), cv2.FONT_HERSHEY_SIMPLEX, 0.36, (255, 255, 255), 1, cv2.LINE_AA)
    cv2.putText(im, title, (48, 70), cv2.FONT_HERSHEY_SIMPLEX, 0.95, (255, 240, 170), 2, cv2.LINE_AA)
    cv2.putText(im, "PROPOSED LAYOUT - NOT A BLUEPRINT", (48, 104), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (120, 200, 255), 1, cv2.LINE_AA)
    cv2.imwrite(path, im, [cv2.IMWRITE_JPEG_QUALITY, 86])

def main(jpath, outdir, dbg=None):
    d = json.load(open(jpath))
    H, W = d["h"] * CELL, d["w"] * CELL
    hull = hull_px(d, H, W)
    decks = []
    for did, level, name, fn in (("upper", 1, "UPPER DECK", upper), ("lower", -1, "LOWER DECK", lower)):
        k, lifts, (y0, y1) = fn(H, W)
        # this deck's hull: the real hull, pulled in 22 px (3.3 m) and only the stretch the deck covers
        dh = cv2.erode(hull, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (45, 45)))
        dh[:y0] = 0; dh[y1:] = 0
        outside = int((k.f & (1 - dh)).sum())
        k.f &= dh
        er = cv2.erode(k.f, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * PLAYER_R + 1,) * 2))
        _, lab = cv2.connectedComponents(er, connectivity=4)
        s = lab[lifts[0][1], lifts[0][0]]
        bad = [r["name"] for r in k.rooms if s == 0 or lab[int(r["at"][1]), int(r["at"][0])] != s]
        bad += ["lift %d" % i for i, l in enumerate(lifts) if s == 0 or lab[l[1], l[0]] != s]
        dist = cv2.distanceTransform(k.f, cv2.DIST_L2, 5)   # how far each room centre is from a wall: its rough size
        mp = "unity_capital_%s.jpg" % did
        draw_map(k, dh, lifts, "UNITY CAPITAL SHIP  -  " + name, outdir + "/" + mp)
        decks.append({"id": did, "level": level, "name": name, "proposed": True,
                      "shell": {"walls": outlines(k.f), "cover": []},
                      "rooms": [{"name": r["name"], "at": [round(r["at"][0] / CELL, 2), round(r["at"][1] / CELL, 2)],
                                 "rad": round(float(dist[int(r["at"][1]), int(r["at"][0])]) * 1.45 / CELL, 2)} for r in k.rooms],
                      "lifts": [[l[0] / CELL, l[1] / CELL] for l in lifts],
                      "start": [lifts[0][0] / CELL, lifts[0][1] / CELL], "map": mp,
                      "check": {"cut_off": bad, "clipped_px": outside}})
        print(did, json.dumps({"rooms": len(k.rooms), "outlines": len(decks[-1]["shell"]["walls"]), "cut_off": bad, "clipped_px": outside}))
    d["decks"] = decks
    json.dump(d, open(jpath, "w"), separators=(",", ":"))

if __name__ == "__main__":
    main(*sys.argv[1:4])
