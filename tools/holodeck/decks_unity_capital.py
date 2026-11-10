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
PAD = 3   # px: a shut door's barrier reaches this far past its opening (the straightened walls leave thin slivers)
KEY_BGR = {0: (90, 255, 90), 1: (40, 230, 255), 2: (30, 140, 255), 3: (60, 60, 255)}
KEY_NAME = {0: "green", 1: "yellow", 2: "orange", 3: "red"}
# PROPOSED GAMEPLAY (not on any blueprint): which rooms sit behind which colour, and which guard carries which key.
MAIN_LOCKS = {"Armory (port)": 1, "Armory (starboard)": 1, "Engine Room": 2, "Bridge": 3}
KEY_GUARDS = [("main", "Medbay", 1), ("main", "Armory (port)", 2), ("main", "Engine Room", 3)]

def reach_at(floor, doors, access, start):
    """Floor you can walk to from start (px) when doors above your access level are shut."""
    f = floor.copy()
    for dr in doors:
        if dr["level"] > access:
            x0, y0, x1, y1 = [int(round(v)) for v in dr["rect"]]; f[y0 - PAD:y1 + PAD, x0 - PAD:x1 + PAD] = 0
    _, lab = cv2.connectedComponents(f, connectivity=4)
    s = lab[int(start[1]), int(start[0])]
    return (lab == s) & (s != 0)

def travel_axis(floor, rect):
    """Which way you walk through a doorway: "y" (bow-stern) when there is floor past its top and bottom ends."""
    x0, y0, x1, y1 = [int(round(v)) for v in rect]
    ends = floor[max(0, y0 - 5):y0 - 1, x0:x1].mean() + floor[y1 + 1:y1 + 5, x0:x1].mean()
    sides = floor[y0:y1, max(0, x0 - 5):x0 - 1].mean() + floor[y0:y1, x1 + 1:x1 + 5].mean()
    return "y" if ends >= sides else "x"

def near(mask, x, y, r=8):
    x, y = int(x), int(y)
    return bool(mask[max(0, y - r):y + r + 1, max(0, x - r):x + r + 1].any())

def lock_main(d, H, W):
    """Colour the main deck's own doors so each MAIN_LOCKS room is shut off below its level: the nearest open door
    to the room is shut, again and again, until the room cannot be reached without the key."""
    sh = d["shell"]
    floor = np.zeros((H, W), np.uint8)
    cv2.fillPoly(floor, [np.round(np.array(p).reshape(-1, 2) * CELL).astype(np.int32) for p in sh["walls"]], 1)
    for p in sh["cover"]: cv2.fillPoly(floor, [np.round(np.array(p).reshape(-1, 2) * CELL).astype(np.int32)], 0)
    doors = [{"rect": [v * CELL for v in dr["rect"]], "level": 0} for dr in sh["doors"]]
    start = [d["start"][0] * CELL, d["start"][1] * CELL]
    at = {r["name"]: (r["at"][0] * CELL, r["at"][1] * CELL) for r in d["rooms"]}
    # a room's own doors: shut EVERY door, see which patch of floor the room's label stands in, and take the doors
    # that touch that patch. (If the patch still holds the start, the room cannot be shut off: reported, left green.)
    shut = floor.copy()
    for dr in doors:
        x0, y0, x1, y1 = [int(round(v)) for v in dr["rect"]]; shut[y0 - PAD:y1 + PAD, x0 - PAD:x1 + PAD] = 0
    _, lab = cv2.connectedComponents(shut, connectivity=4)
    s0 = lab[int(start[1]), int(start[0])]
    d["lock_notes"] = []
    for name, lv in sorted(MAIN_LOCKS.items(), key=lambda kv: kv[1]):
        x, y = int(at[name][0]), int(at[name][1])
        win = lab[y - 10:y + 11, x - 10:x + 11]; ids = win[win > 0]
        if not len(ids): d["lock_notes"].append(name + ": no floor at its label"); continue
        rid = int(np.bincount(ids).argmax())
        if rid == s0: d["lock_notes"].append(name + ": open to the hangar with every door shut, left green"); continue
        patch = cv2.dilate((lab == rid).astype(np.uint8), np.ones((9, 9), np.uint8))
        n = 0
        for dr in doors:
            x0, y0, x1, y1 = [int(round(v)) for v in dr["rect"]]
            if patch[y0 - PAD:y1 + PAD, x0 - PAD:x1 + PAD].any(): dr["level"] = max(dr["level"], lv); n += 1
        d["lock_notes"].append("%s: %d door(s) %s" % (name, n, KEY_NAME[lv]))
    for i, dr in enumerate(doors): sh["doors"][i]["level"] = dr["level"]; sh["doors"][i]["ax"] = travel_axis(floor, dr["rect"])
    return floor, doors, start, at

def hull_px(d, H, W):
    h = np.array([[c != " " for c in row.ljust(d["w"])[:d["w"]]] for row in d["rows"]], np.uint8)
    h = cv2.resize(h, (d["w"] * CELL, d["h"] * CELL), interpolation=cv2.INTER_NEAREST)
    return np.pad(h, ((0, H - h.shape[0]), (0, W - h.shape[1])))

class Deck:
    def __init__(self, H, W):
        self.f = np.zeros((H, W), np.uint8); self.rooms = []; self.doors = []; self.H = H; self.W = W
    CX = CX
    def mir(self, pts): return [(2 * self.CX - x, y) for x, y in pts][::-1]
    def poly(self, pts, both=False):
        cv2.fillPoly(self.f, [np.round(np.array(pts)).astype(np.int32)], 1)
        if both: cv2.fillPoly(self.f, [np.round(np.array(self.mir(pts))).astype(np.int32)], 1)
    def box(self, x0, y0, x1, y1, ch=0, both=False):   # a room: chamfered corners, never a plain box
        self.poly([(x0 + ch, y0), (x1 - ch, y0), (x1, y0 + ch), (x1, y1 - ch), (x1 - ch, y1), (x0 + ch, y1), (x0, y1 - ch), (x0, y0 + ch)], both)
    def door(self, x0, y0, x1, y1, level):   # a doorway through a wall; level 0 green (open), 1 yellow, 2 orange, 3 red
        self.f[y0:y1, x0:x1] = 1; self.doors.append({"rect": [x0, y0, x1, y1], "level": level})
    def disc(self, x, y, r): cv2.circle(self.f, (int(x), int(y)), int(r), 1, -1)
    def room(self, name, x, y, names_both=None):
        self.rooms.append({"name": name, "at": [x, y]})
        if names_both: self.rooms.append({"name": names_both, "at": [2 * self.CX - x, y]})

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
    """Command level. Two loops round the lift lobby (no straight run end to end); the lounge is reached THROUGH
    the officers' quarters; Captain's Quarters = orange, Comms = yellow, Wardroom = red."""
    k = Deck(H, W)
    k.box(372, 464, 653, 484)                               # lift lobby, running out to both side passages
    k.box(447, 458, 479, 490, 4, True)                      # lift cars (463,474 and 557,474)
    k.box(372, 380, 392, 620, 0, True)                      # side passages (port and starboard)
    k.box(372, 380, 653, 400)                               # forward cross passage
    k.box(372, 600, 653, 620)                               # aft cross passage
    k.box(402, 410, 500, 454, 10); k.door(436, 398, 458, 412, 0); k.room("Ready Room", 451, 432)
    k.box(525, 410, 623, 454, 10); k.door(566, 452, 588, 466, 1); k.room("Comms Center", 574, 432)
    k.box(402, 494, 500, 590, 12); k.door(390, 530, 404, 552, 0); k.room("Chart Room", 451, 542)
    k.box(525, 494, 623, 590, 12); k.door(566, 588, 588, 602, 0); k.room("Signal Office", 574, 542)
    k.poly([(432, 292), (504, 292), (504, 368), (446, 368), (432, 354)]); k.door(462, 366, 484, 382, 2); k.room("Captain's Quarters", 468, 318)
    k.poly([(521, 292), (593, 292), (593, 354), (579, 368), (521, 368)]); k.door(541, 366, 563, 382, 0); k.room("Officers' Quarters", 557, 342)
    k.disc(512, 236, 40); k.door(524, 252, 546, 294, 0); k.room("Observation Lounge", 512, 228)
    k.poly([(440, 636), (585, 636), (600, 652), (600, 690), (575, 712), (450, 712), (425, 690), (425, 652)])
    k.door(596, 618, 618, 668, 3); k.box(596, 650, 604, 668); k.room("Wardroom", 512, 676)
    lifts = [[463, 474], [557, 474]]
    return k, lifts, (150, 730)

def lower(H, W):
    """Service level. A loop round a block of four rooms; Life Support hangs off the aft passage by a dog-leg and
    the Pump Room is reached only THROUGH Life Support. Brig = yellow, Life Support = orange, Pump Room = red."""
    k = Deck(H, W)
    k.box(326, 831, 699, 851)                               # lift lobby
    k.box(350, 824, 382, 857, 4, True)                      # lift cars (366,840 and 658,840)
    k.box(326, 831, 346, 1040, 0, True)                     # side passages
    k.box(326, 1020, 699, 1040)                             # aft cross passage
    k.box(356, 862, 500, 932, 12); k.door(416, 849, 438, 864, 1); k.room("Brig", 428, 898)
    k.box(525, 862, 669, 932, 12); k.door(667, 886, 681, 908, 0); k.room("Machine Shop", 597, 898)
    k.box(356, 944, 500, 1010, 12); k.door(344, 966, 358, 988, 0); k.room("Munitions Store", 428, 978)
    k.box(525, 944, 669, 1010, 12); k.door(586, 1008, 608, 1022, 0); k.room("Water Reclamation", 597, 978)
    k.poly([(236, 864), (314, 864), (314, 1000), (262, 1000), (236, 974)]); k.door(312, 920, 328, 942, 0); k.room("Storage A", 276, 930)
    k.poly([(711, 864), (789, 864), (789, 974), (763, 1000), (711, 1000)]); k.door(697, 920, 713, 942, 0); k.room("Storage B", 749, 930)
    k.box(436, 1038, 456, 1108); k.box(436, 1088, 462, 1108)   # the dog-leg down to Life Support
    k.disc(512, 1118, 50); k.door(456, 1088, 478, 1108, 2); k.room("Life Support", 512, 1118)
    k.box(556, 1108, 586, 1128); k.box(566, 1108, 586, 1196)   # and on, round to the Pump Room
    k.poly([(455, 1208), (570, 1208), (588, 1224), (588, 1262), (565, 1280), (460, 1280), (440, 1262), (440, 1224)])
    k.door(566, 1190, 586, 1212, 3); k.room("Pump Room", 512, 1246)
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
    for dr in k.doors:
        x0, y0, x1, y1 = dr["rect"]
        cv2.rectangle(im, (x0, y0), (x1, y1), KEY_BGR[dr["level"]], -1)
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
    mfloor, mdoors, mstart, mat = lock_main(d, H, W)
    report = {"main_doors": {KEY_NAME[l]: sum(1 for q in mdoors if q["level"] == l) for l in range(4)}}
    world = {"main": (mfloor, mdoors, mstart, mat)}
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
        world[did] = (k.f, k.doors, lifts[0], {r["name"]: tuple(r["at"]) for r in k.rooms})
        decks.append({"id": did, "level": level, "name": name, "proposed": True,
                      "shell": {"walls": outlines(k.f), "cover": [],
                                "doors": [{"rect": [round(v / CELL, 2) for v in q["rect"]], "level": q["level"], "ax": travel_axis(k.f, q["rect"])} for q in k.doors]},
                      "rooms": [{"name": r["name"], "at": [round(r["at"][0] / CELL, 2), round(r["at"][1] / CELL, 2)],
                                 "rad": round(float(dist[int(r["at"][1]), int(r["at"][0])]) * 1.45 / CELL, 2)} for r in k.rooms],
                      "lifts": [[l[0] / CELL, l[1] / CELL] for l in lifts],
                      "start": [lifts[0][0] / CELL, lifts[0][1] / CELL], "map": mp,
                      "check": {"cut_off": bad, "clipped_px": outside}})
        print(did, json.dumps({"rooms": len(k.rooms), "doors": len(k.doors), "cut_off": bad, "clipped_px": outside}))
    # the key chain: what each access level opens, and that each guard can be reached with the key before his
    opens = {}
    for a in range(4):
        got = []
        for did, (fl, drs, st, at) in world.items():
            m = reach_at(fl, drs, a, st)
            got += ["%s/%s" % (did, n) for n, p in at.items() if near(m, *p)]
        opens[a] = got
    report["rooms_by_access"] = {KEY_NAME[a]: len(opens[a]) for a in range(4)}
    report["new_with_key"] = {KEY_NAME[a]: sorted(set(opens[a]) - set(opens[a - 1])) for a in range(1, 4)}
    report["total_rooms"] = sum(len(w[3]) for w in world.values())
    guards = []; chain_ok = True
    for did, room, lv in KEY_GUARDS:
        ok = ("%s/%s" % (did, room)) in opens[lv - 1]
        chain_ok &= ok
        at = world[did][3][room]
        guards.append({"deck": did, "room": room, "key": lv, "at": [round((at[0] + 14) / CELL, 2), round((at[1] + 10) / CELL, 2)]})
    report["lock_notes"] = d.get("lock_notes", [])
    report["key_chain_ok"] = bool(chain_ok); report["all_reachable_with_red"] = len(opens[3]) == report["total_rooms"]
    lifts_ok = all(near(reach_at(mfloor, mdoors, 0, mstart), l[0] * CELL, l[1] * CELL) for l in d["lifts"])
    report["lifts_open_without_keys"] = bool(lifts_ok)
    d["decks"] = decks
    d["key_guards"] = guards
    d["gameplay_note"] = "PROPOSED: door colours and key guards are a gameplay proposal, not on the blueprint"
    json.dump(d, open(jpath, "w"), separators=(",", ":"))
    print(json.dumps(report, indent=1))

if __name__ == "__main__":
    main(*sys.argv[1:4])
