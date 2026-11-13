#!/usr/bin/env python3
"""Gameplay pass on the approved Imperium Troop Transport plan (PROPOSED, for the owner's OK): entry, key-card doors,
the guards who carry the cards, the three mission targets, lifts, the CUTTER wreckage short cut, the way out.
Writes gameplay.json (read by tools/trace/to_deck_json.py) and gameplay.png / gameplay_on_map.jpg."""
import json, os, sys
import cv2, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_plan as P

HERE = os.path.dirname(os.path.abspath(__file__))
G0 = {
    "entry": {"room": "Deploy Bay A", "at": [150, 840]},          # you board here and leave from here
    # door (x, y) on the plan -> key level 1 yellow, 2 orange, 3 red (every other door is green)
    "locks": [
        {"door": [494, 1095], "key": 1, "why": "the aft section (engineering, maint, supply, reactor)"},
        {"door": [494, 435], "key": 2, "why": "Command & Control from the lift lobby"},
        {"door": [436, 377], "key": 2, "why": "Command & Control, left"}, {"door": [552, 377], "key": 2, "why": "Command & Control, right"},
        {"door": [424, 298], "key": 2, "why": "sensor store A from the left spine"}, {"door": [564, 298], "key": 2, "why": "sensor store B"},
        {"door": [494, 1240], "key": 2, "why": "reactor from engineering"},
        {"door": [447, 1272], "key": 2, "why": "reactor, left"}, {"door": [541, 1272], "key": 2, "why": "reactor, right"},
    ],
    "guards": [
        {"key": 1, "room": "Barracks B", "at": [690, 650]},
        {"key": 2, "room": "Supply Depot", "at": [670, 1170]},
    ],
    "targets": {
        "sabotage": {"room": "Reactor Core", "at": [494, 1288], "key": 2},
        "capture": {"room": "Bridge", "at": [494, 140], "key": 2},
        "rescue": {"room": "Sensor Store B", "at": [560, 265], "key": 2},
    },
    "wreck": [{"at": [217, 1010], "across": "h", "why": "outer hall A -> vehicle bay: a side way round, never the only way"}],
    "lifts": [{"room": "Lift A", "at": [459, 490]}, {"room": "Lift B", "at": [529, 490]}],
    "patrols": [
        {"room": "Troop Bay", "path": [[420, 620], [420, 900], [570, 900], [570, 620]]},
        {"room": "Vehicle / Dropship Bay", "path": [[320, 1030], [670, 1030]]},
        {"room": "Engineering Deck", "path": [[430, 1160], [560, 1160]]},
        {"room": "Command & Control", "path": [[470, 360], [520, 400]]},
    ],
}
G = json.load(open(os.path.join(HERE, "gameplay.json"))) if os.path.exists(os.path.join(HERE, "gameplay.json")) else G0
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
        lx, ly = 20, 1250
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
    shape = (1591, 988)
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
