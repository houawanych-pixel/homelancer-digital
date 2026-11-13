#!/usr/bin/env python3
"""Gameplay pass for any fleet ship (proven on the Imperium Troop Transport): reads eng/plan.json + eng/gameplay.json,
checks the card order (each card's guard is reachable with the cards before it, each target needs its card) and
draws gameplay.png / gameplay_on_map.jpg.   usage: python3 -I tools/trace/gameplay_check.py tools/trace/fleet_<id>"""
import json, os, sys
import cv2, numpy as np
from shapely.geometry import shape, box
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import planlib

FOLDER = os.path.abspath(sys.argv[1]); HERE = os.path.join(FOLDER, "eng")
PJ = json.load(open(os.path.join(HERE, "plan.json")))
G = json.load(open(os.path.join(HERE, "gameplay.json")))
class _P:   # the plan as the old per-ship module looked to this code
    T, DOOR = PJ["thickness"], PJ["door"]
    DOORS = [tuple(d) for d in PJ["doors"]]
    door_box = staticmethod(planlib.door_box)
    raster = staticmethod(planlib.raster)
    @staticmethod
    def build(): return shape(PJ["floor"]), shape(PJ["walls"])
    class S: pass
P = _P
P.S.src = os.path.join(FOLDER, "source.jpg"); P.S.R = {k: shape(v) for k, v in PJ["rooms"].items()}; P.S.PROPOSED_DOORS = [tuple(d[:2]) for d in PJ.get("proposed_doors", [])]
P.draw = staticmethod(lambda floor, walls, a, b: planlib.draw(P.S, floor, walls, a, b))
SRC_H, SRC_W = cv2.imread(P.S.src).shape[:2]
COL = {0: (80, 255, 80), 1: (40, 230, 255), 2: (20, 140, 255), 3: (60, 60, 255)}   # BGR: green, yellow, orange, red

def draw():
    floor, walls = P.build()
    P.draw(floor, walls, "/tmp/_g_plan.png", "/tmp/_g_ov.jpg")
    out = []
    for path in ("/tmp/_g_plan.png", "/tmp/_g_ov.jpg"):
        im = cv2.imread(path)
        locked = {tuple(l["door"]): l["key"] for l in G["locks"]}
        for x, y, o in P.DOORS:
            k = locked.get((x, y), 0)
            w, d = (P.DOOR / 2 + 2, 5) if o == "h" else (5, P.DOOR / 2 + 2)
            cv2.rectangle(im, (int(x - w), int(y - d)), (int(x + w), int(y + d)), COL[k], -1)
        for pt in G["patrols"]:
            cv2.polylines(im, [np.array(pt["path"], np.int32)], len(pt["path"]) > 2, (150, 150, 150), 1, cv2.LINE_AA)
        for g in G["guards"]:
            x, y = g["at"]
            cv2.circle(im, (x, y), 13, COL[g["key"]], -1); cv2.circle(im, (x, y), 13, (0, 0, 0), 2)
            cv2.putText(im, "K", (x - 6, y + 6), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 0), 2)
        for kind, t in G["targets"].items():
            x, y = t["at"]
            star = np.array([[x + 16 * np.cos(a) * (1 if i % 2 == 0 else 0.45), y + 16 * np.sin(a) * (1 if i % 2 == 0 else 0.45)]
                             for i, a in enumerate(np.linspace(-np.pi / 2, 3 * np.pi / 2, 11)[:-1])], np.int32)
            cv2.fillPoly(im, [star], (255, 0, 255))
            cv2.putText(im, kind.upper(), (x + 18, y + 5), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 0, 255), 1, cv2.LINE_AA)
        for wr in G["wreck"]:
            x, y = wr["at"]
            cv2.rectangle(im, (x - 10, y - 5), (x + 10, y + 5), (0, 120, 255), -1)
            for i in range(-10, 10, 4): cv2.line(im, (x + i, y - 5), (x + i + 4, y + 5), (0, 0, 0), 1)
            cv2.putText(im, "CUT", (x + 13, y + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.38, (0, 120, 255), 1, cv2.LINE_AA)
        for lf in G["lifts"]:
            x, y = lf["at"]; cv2.rectangle(im, (x - 9, y - 9), (x + 9, y + 9), (255, 255, 0), 2)
        x, y = G["entry"]["at"]
        cv2.arrowedLine(im, (x - 70, y), (x - 18, y), (255, 255, 255), 3, tipLength=0.4)
        cv2.putText(im, "BOARD / EXIT", (x - 95, y - 14), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1, cv2.LINE_AA)
        # key
        lx, ly = 20, SRC_H - 200
        for i, (t, c) in enumerate([("GREEN open", COL[0]), ("YELLOW card", COL[1]), ("ORANGE card", COL[2]),
                                    ("K  guard with that card", (200, 200, 200)), ("target (sabotage / capture / rescue)", (255, 0, 255)),
                                    ("CUT  wreckage short cut", (0, 120, 255)), ("lift", (255, 255, 0))]):
            cv2.rectangle(im, (lx, ly + i * 26), (lx + 16, ly + i * 26 + 14), c, -1)
            cv2.putText(im, t, (lx + 24, ly + i * 26 + 13), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (230, 230, 230), 1, cv2.LINE_AA)
        out.append(im)
    cv2.imwrite(os.path.join(HERE, "gameplay.png"), out[0])
    cv2.imwrite(os.path.join(HERE, "gameplay_on_map.jpg"), out[1], [cv2.IMWRITE_JPEG_QUALITY, 88])

def check():
    """the card order works: each card's guard is reachable with the cards before it; targets need the last card"""
    floor, walls = P.build()
    shape = (SRC_H, SRC_W)
    base = np.zeros(shape, np.uint8); base[P.raster(floor, shape) > 0] = 1; base[P.raster(walls, shape) > 0] = 0
    def reach(cards):
        m = base.copy()
        for l in G["locks"]:
            if l["key"] > cards:
                x, y = l["door"]; o = [d[2] for d in P.DOORS if d[0] == x and d[1] == y][0]
                g = P.door_box(x, y, o, P.T * 2.6); bx = [int(v) for v in g.bounds]
                m[bx[1]:bx[3] + 1, bx[0]:bx[2] + 1] = 0
        n, lab = cv2.connectedComponents(m, connectivity=4)
        s = lab[G["entry"]["at"][1], G["entry"]["at"][0]]
        return lambda p: lab[p[1], p[0]] == s
    ok = True
    for g in G["guards"]:
        r = reach(g["key"] - 1)(g["at"]); print("guard", g["key"], g["room"], "reachable with the cards before:", r); ok &= bool(r)
    for k, t in G["targets"].items():
        before, after = reach(t["key"] - 1)(t["at"]), reach(t["key"])(t["at"])
        print("target", k, "locked before card", t["key"], not before, "open after", after); ok &= (not before) and bool(after)
    return ok


if __name__ == "__main__":
    print("all good" if check() else "PROBLEM")
    draw()
