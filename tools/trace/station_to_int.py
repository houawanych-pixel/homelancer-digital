#!/usr/bin/env python3
"""The owner's approved station deck plans (tools/trace/station_swtor.py, v3) -> the game's walkable station interiors
(assets/stations_int/deck_<model>.json + one map picture per deck), read by scripts/station_interior.gd.

Owner Nov 16 2026: "Make skill and build" (after the plans read right: five floors, each its own silhouette, red mech
ways joined up, rooms filling the deck, yellow-orange-red-purple cards).

What is written per deck (StationInterior's schema, metres, x = plan x, z = plan y, the lift axis at 0, 0):
  walls   every edge of the walkable floor (halls + pods + rooms + the doorway joining each room to its way), the
          walkable side on the left
  doors   one sliding door in every doorway: x, z, yaw (the way you walk through), w; plus key (0 open .. 4 purple),
          mech (a wide mech door) - the game tints the door by its card
  rooms   name, x, z, rad (the sign and "which room am I in"); kind, key, card, objective for the gameplay pass
  lifts   the main lift (every deck, same spot)
usage: python3 -I tools/trace/station_to_int.py [model ...]"""
import json, math, os, sys
import numpy as np, cv2
from shapely.geometry import Point, LineString, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union, nearest_points

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import station_swtor as T
import station_plans as SP

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "assets", "stations_int")
PX = T.PX
GK = 2.0             # game metres per plan metre (the pilot is 1.8 m: a 3.2 m mech way becomes 6.4 m, a mech fits)
DECK_H = 12.0        # wall height of a deck (doors are 8 m)
DECK_DY = 16.0       # floor to floor
MECH_DOOR = 3.0      # plan metres (6 m in the game)
PILOT_DOOR = 1.4     # plan metres (2.8 m)
MAP_PX = 512
KEY_BGR = T.DOOR_BGR
ROLE_ID = {"HANGAR": "D1", "ENGINEERING": "D2", "MAIN HUB": "D3", "HABITAT": "D4", "COMMAND": "D5"}


def g(v): return round(float(v) / PX * GK, 2)


def doorway(r, ways):
    """the doorway joining a room to its way: a short strip across the wall gap, centred on the room's door point"""
    a, b = nearest_points(ways, r["poly"])      # on the way, on the room
    dx, dy = b.x - a.x, b.y - a.y; L = math.hypot(dx, dy)
    if L < 0.05 * PX:
        c = r["poly"].centroid; dx, dy = c.x - a.x, c.y - a.y; L = math.hypot(dx, dy) or 1.0
    ux, uy = dx / L, dy / L
    w = (MECH_DOOR if r["kind"] == "mech" else PILOT_DOOR) * PX
    p0 = (a.x - ux * 0.8 * PX, a.y - uy * 0.8 * PX); p1 = (b.x + ux * 0.8 * PX, b.y + uy * 0.8 * PX)
    strip = LineString([p0, p1]).buffer(w / 2, cap_style=2)
    mid = ((a.x + b.x) / 2, (a.y + b.y) / 2)
    yaw = math.degrees(math.atan2(ux, -uy)) % 360.0     # clockwise from the front (-z): walking from the way into the room
    return strip, mid, yaw, w


def rings(walk):
    out = []
    for p in getattr(walk, "geoms", [walk]):
        p = orient(p.simplify(0.15 * PX), 1.0)
        for ring in [p.exterior] + list(p.interiors):
            pts = list(ring.coords)[:-1]
            if len(pts) < 3: continue
            # keep the walkable side on the left (station_interior: nrm = (e.z, 0, -e.x))
            k = max(range(len(pts)), key=lambda i: math.dist(pts[i], pts[(i + 1) % len(pts)]))
            (x0, y0), (x1, y1) = pts[k], pts[(k + 1) % len(pts)]
            ex, ey = x1 - x0, y1 - y0; L = math.hypot(ex, ey)
            nx, ny = ey / L, -ex / L
            if not walk.buffer(0.05 * PX).contains(Point((x0 + x1) / 2 + nx * 0.3 * PX, (y0 + y1) / 2 + ny * 0.3 * PX)): pts = pts[::-1]
            flat = []
            for x, y in pts: flat += [g(x), g(y)]
            out.append(flat)
    return out


def deck_map(L, rooms, doors, ext_m, path):
    """the deck's map: square, centred on the lift axis, ext_m across (station_interior's minimap)"""
    S = MAP_PX / (ext_m / GK * PX)
    def fill(q, col):
        for p in T.parts(q): cv2.fillPoly(img, [np.round(np.array(p.exterior.coords) * S + MAP_PX / 2).astype(np.int32)], col)
    def line(q):
        for p in T.parts(q): cv2.polylines(img, [np.round(np.array(p.exterior.coords) * S + MAP_PX / 2).astype(np.int32)], True, (240, 240, 240), 1, cv2.LINE_AA)
    img = np.full((MAP_PX, MAP_PX, 3), (40, 22, 8), np.uint8)
    fill(L["outline"], (90, 50, 18))
    floor = unary_union([q for _, q in L["halls"]] + L["pods"])
    fill(floor, (55, 45, 170))
    for r in rooms: fill(r["poly"], (45, 30, 120) if r["kind"] == "mech" else (175, 95, 30))
    line(floor)
    for r in rooms: line(r["poly"])
    for _, q in L["lifts"]: fill(q, (0, 215, 255))
    for d in doors:
        x, z = d["x"] / GK * PX * S + MAP_PX / 2, d["z"] / GK * PX * S + MAP_PX / 2
        s = 4 if d["mech"] else 2
        cv2.rectangle(img, (int(x - s), int(z - s)), (int(x + s), int(z + s)), KEY_BGR[d["key"]], -1)
    cv2.imwrite(path, img, [cv2.IMWRITE_JPEG_QUALITY, 85])


def convert(st, keep):
    model = st["model"]; K = keep[model]
    decks = K["decks"]
    ext = 0.0
    for D in decks: x0, y0, x1, y1 = D["_L"]["outline"].bounds; ext = max(ext, abs(x0), abs(x1), abs(y0), abs(y1))
    ext_m = round(2.2 * ext / PX * GK, 1)
    levels, problems = [], []
    for D in reversed(decks):   # (station_interior: level 0 is the top deck)
        L = D["_L"]; k = D["deck"] - 1; lid = ROLE_ID[D["role"]]
        ways = L["ways"]
        strips, doors, rooms = [], [], []
        for r in D["rooms"]:
            strip, mid, yaw, w = doorway(r, ways)
            strips.append(strip)
            doors.append({"x": g(mid[0]), "z": g(mid[1]), "yaw": round(yaw, 1), "w": round(w / PX * GK, 2), "key": int(r["key"]), "mech": r["kind"] == "mech"})
            c = r["poly"].representative_point() if not r["poly"].centroid.within(r["poly"]) else r["poly"].centroid
            rm = {"name": r["name"], "x": g(c.x), "z": g(c.y), "rad": round(math.sqrt(r["poly"].area / math.pi) / PX * GK * 1.05, 2),
                  "kind": r["kind"], "key": int(r["key"])}
            if r.get("card"): rm["card"] = int(r["card"])
            if r.get("objective"): rm["objective"] = True
            rooms.append(rm)
        lifts = [q for n, q in L["lifts"] if n == "Main lift"]   # (the freight lifts don't run in the game yet)
        walk = unary_union([q for _, q in L["halls"]] + L["pods"] + lifts + [r["poly"] for r in D["rooms"]] + strips)
        walk = walk.buffer(0.02 * PX, join_style=2).buffer(-0.02 * PX, join_style=2)
        ps = T.parts(walk)
        if len(ps) != 1:   # a scrap no way reaches: left out of the game (and said so)
            main = next((q for q in ps if q.intersects(lifts[0])), max(ps, key=lambda q: q.area))
            gone = [q for q in ps if q is not main]
            problems.append("%s: %d unreachable scraps left out (%.0f m2)" % (D["role"], len(gone), sum(q.area for q in gone) / PX / PX))
            keep = [i for i, r in enumerate(D["rooms"]) if r["poly"].intersects(main)]
            doors = [doors[i] for i in keep]; rooms = [rooms[i] for i in keep]
            walk = main
        mp = "deck_%s_%s.jpg" % (model, lid.lower())
        deck_map(L, D["rooms"], doors, ext_m, os.path.join(OUT, mp))
        levels.append({"id": lid, "name": D["role"] + " DECK", "y": round(k * DECK_DY, 1), "proposed": False, "map": mp, "h": DECK_H, "storeys": 1,
                       "decks_in": [], "walls": rings(walk), "doors": doors, "rooms": rooms, "lifts": [[0.0, 0.0]], "ports": [],
                       "card_door_note": "key 0 open, 1 yellow, 2 orange, 3 red, 4 purple"})
    H = next(D for D in decks if D["role"] == "HANGAR")
    pods = H["_L"]["pods"]
    sp = max(pods, key=lambda q: q.centroid.y).centroid if pods else Point(0, 6 * PX)
    data = {"id": "deck_" + model, "name": st["name"], "model": model, "system": st.get("system", ""), "extent_m": ext_m,
            "start": {"level": "D1", "x": g(sp.x), "z": g(sp.y)},
            "note": "v3 deck plans (tools/trace/station_swtor.py): five decks, each from the model's own slice; red mech ways, blue pilot rooms, cards yellow-orange-red-purple.",
            "chain": K["chain"], "levels": levels}
    json.dump(data, open(os.path.join(OUT, "deck_%s.json" % model), "w"), separators=(",", ":"))
    return problems


if __name__ == "__main__":
    S = json.load(open(os.path.join(SP.OUT, "stations.json")))
    T.KEEP = {}
    bad = 0
    for st in S:
        if sys.argv[1:] and st["model"] not in sys.argv[1:]: continue
        T.build(st)
        pr = convert(st, T.KEEP)
        T.KEEP.clear()
        if pr: bad += 1
        print(st["model"], "ok" if not pr else pr, flush=True)
    print("stations with problems:", bad)
