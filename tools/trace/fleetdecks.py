#!/usr/bin/env python3
"""The proven Covenant Destroyer upper (command) / lower (hold) deck layout, as a template for the other fleet ships.

Everything is placed relative to the ship's own lift shaft: the template's lift row sits on the ship's main-deck
lift, rooms are mirrored about the ship's axis, and the layout can be scaled (s) for bigger hulls. Corridor widths,
door widths and wall thickness never scale. A short corridor joins an off-axis lift to the spine; a lift on the
centreline splits the spine (doors fore and aft).

    import fleetdecks
    fleetdecks.build("unity_capital", HERE, ax=512, lift=box(468, 460, 498, 490), s=1.1,
                     names={"Targeting": "Fleet Ops"}, move={"Gunnery Control": (0, -20)})

names: rename rooms (keys = template names, twins too). move: {template name: (dx, dy)} in source px after scaling.
size: {template name: factor}. drop: template rooms to leave out (with their links). Exit code 1 if the check fails."""
import json, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from planlib import hall, circle
import decklib
from decklib import lib, Deck
from shapely.geometry import Polygon, LineString, box, shape

SERVICE = ["conduit", "duct", "power trunk", "coolant loop", "crawlspace", "machinery", "structure", "wiring run", "fuse bay"]
TAX, TLY = 512.0, 484.0      # template axis and lift row


def ring(cx, cy, r): return circle(cx, cy, r).exterior
def junction(cx, cy, d=4.4): return lib("tianjin_10", cx, cy, w=d, h=d)
def arc(cx, cy, r, a0, a1, n=24):
    return LineString([(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)])
def sector(cx, cy, r0, r1, a0, a1):
    return Polygon(list(arc(cx, cy, r1, a0, a1).coords) + list(arc(cx, cy, r0, a1, a0).coords))


def build(sid, here, ax, lift, s=1.0, names=None, move=None, size=None, drop=(), upper_title="UPPER DECK - COMMAND",
          lower_title="LOWER DECK - HOLD", lift_room="Lift (port)", src=None, coverage=(0.55, 0.65), lower_outline="close",
          hatch_up=True, extra_upper=None, extra_lower=None):
    names, move, size = names or {}, move or {}, size or {}
    src = src or os.path.join(here, "..", "source.jpg")
    lx0, ly0, lx1, ly1 = lift.bounds
    shaft = (round((lx0 + lx1) / 2, 1), round((ly0 + ly1) / 2, 1))
    on_axis = lx0 < ax < lx1
    oy = shaft[1] - TLY * s
    def X(x): return ax + (x - TAX) * s
    def Y(y): return oy + y * s
    def N(k): return names.get(k, k)
    def P(k, x, y):   # a template position, scaled, plus any per-ship move
        dx, dy = move.get(k, (0, 0)); return X(x) + dx, Y(y) + dy
    def W(k, w): return w * s * size.get(k, 1.0)
    SP = ax - 11                                                  # spine's port edge (2.2 m spine)
    main = json.load(open(os.path.join(here, "plan.json")))
    lift_ok = [] if shape(main["rooms"][lift_room]).buffer(1).contains(lift) else ["the shaft is not the main deck's %s" % lift_room]
    checks = dict(service=SERVICE, lift_ok=lift_ok, outline_style="ring", coverage=coverage)

    def spine(y0, y1, w=22):
        """the centreline corridor from y0 to y1, broken round a centreline lift; plus the lift's side corridor"""
        out = []
        if on_axis:
            if y0 < ly0 < y1: out += [hall((ax, y0), (ax, ly0), w=w), hall((ax, ly1), (ax, y1), w=w)]
            else: out.append(hall((ax, y0), (ax, y1), w=w))
        else:
            out.append(hall((ax, y0), (ax, y1), w=w))
            if y0 < shaft[1] < y1:
                if lx1 <= ax: out.append(hall((lx1 - 1, shaft[1]), (ax - 5, shaft[1]), w=16))
                else: out.append(hall((lx0 + 1, shaft[1]), (ax + 5, shaft[1]), w=16))
        return out
    def lift_doors(D):
        if on_axis: D.door(ax, ly0, "h", both=False); D.door(ax, ly1, "h", both=False)
        elif lx1 <= ax: D.door(lx1, shaft[1], "v", both=False)
        else: D.door(lx0, shaft[1], "v", both=False)
    def has(k): return k not in drop

    # ================================================================= UPPER DECK - COMMAND
    U = Deck(ax); M = U.M
    dome = P("Observation Dome", 512, 262); rd = 42 * s * size.get("Observation Dome", 1.0)
    U.room(N("Observation Dome"), lib("malgus_11", *dome, w=W("Observation Dome", 8.4)), "malgus_11 command hub, railing ring",
           feat=[ring(*dome, 24 * s), ring(*dome, 10 * s)])
    U.room("Lift", lift, "lift car (the main deck's %s shaft)" % lift_room)
    UP = [("Navigation", "kasparov_a_03", 456, 352, 5.8, 6.3, {}, "kasparov_a_03 ops (round alcove)", "Sensors"),
          ("Security Office", "fury_08", 450, 425, 5.6, 4.8, {}, "fury_08 secondary quarters (angled)", "Weapons Locker"),
          ("Captain's Quarters", "fury_04", 440, 540, 9.2, 6.4, {"flip": True}, "fury_04 captain's quarters", "First Officer"),
          ("Targeting", "kasparov_a_09", 446, 612, 9.7, 5.2, {}, "kasparov_a_09 central hall (chamfered)", "Fleet Ops"),
          ("Lounge P", "fury_06", 421, 700, 13.0, 4.5, {}, "fury_06 lounge + holoterminal", "Lounge S"),
          ("Cabins A", "kasparov_b_03", 419, 771, 10.9, 6.5, {}, "kasparov_b_03 passenger quarters", "Cabins B"),
          ("Galley", "tianjin_01", 436, 862, 6.9, 7.3, {"flip": True}, "tianjin_01 galley (quarter round)", "Wardroom")]
    for k, rid, x, y, w, h, kw, why, tw in UP:
        if has(k): U.room(N(k), lib(rid, *P(k, x, y), w=W(k, w), h=W(k, h), **kw), why, twin=N(tw))
    mess = P("Officers' Mess", 512, 860); rm = 37 * s * size.get("Officers' Mess", 1.0)
    U.room(N("Officers' Mess"), lib("kasparov_b_06", *mess, w=W("Officers' Mess", 7.4), h=W("Officers' Mess", 7.4)), "kasparov_b_06 dining area (round)")
    if has("Gunnery Control"):
        U.room(N("Gunnery Control"), lib("tianjin_26", *P("Gunnery Control", 512, 957), w=W("Gunnery Control", 9.1), h=W("Gunnery Control", 7.6), rot=90),
               "tianjin_26 gunnery (tapered)")
    yb = mess[1] - rm - 23                                          # the spine stops 2.3 m short of the mess
    U.H += spine(dome[1] + rd, yb) + [junction(ax, Y(380)), junction(ax, Y(560)), junction(ax, Y(740)), junction(ax, yb)]
    yl = Y(740)
    U.hall(hall((ax, yl), (P("Cabins A", 370, 0)[0], yl), w=18))
    WHU = {N("Observation Dome"), "Lift", N("Officers' Mess")}
    if extra_upper: extra_upper(U, X, Y)
    U.R = decklib.settle(U.R, U.H, whole=WHU, twins=U.TW, mirror_fn=M, mode="close")
    U.door(ax, round(dome[1] + rd, 1), "h", both=False); lift_doors(U)
    for k, y in (("Navigation", 352), ("Security Office", 425), ("Captain's Quarters", 540), ("Targeting", 610)):
        if has(k): U.link(N(k), (SP, P(k, 0, y)[1]))
    if has("Lounge P"): U.link(N("Lounge P"), (P("Lounge P", 421, 0)[0], yl - 9))
    if has("Cabins A"): U.link(N("Cabins A"), (P("Cabins A", 421, 0)[0], yl + 9))
    U.link(N("Officers' Mess"), (ax, yb + 10), both=False)
    if has("Galley"): U.link(N("Galley"), (mess[0] - rm, mess[1]))
    if has("Gunnery Control"):
        g, m = U.R[N("Gunnery Control")], U.R[N("Officers' Mess")]; xg = ax - 16
        gt = g.intersection(LineString([(xg, mess[1]), (xg, 3000)])).bounds[1]; mb = m.intersection(LineString([(xg, mess[1] - 100), (xg, 3000)])).bounds[3]
        U.H.append(hall((xg, mb), (xg, gt), w=16).difference(g).difference(m)); U.door(xg, round(mb, 1), "h", both=False); U.door(xg, round(gt, 1), "h", both=False)
    U.R = decklib.finalize(U.R, U.H, list(U.R), U.TW, M, keep=WHU)
    U.D = list(dict.fromkeys(U.D))
    for k, f in [("Targeting", lambda x, y: [ring(x, y, 9 * s)]), ("Officers' Mess", lambda x, y: [ring(x, y, 14 * s)]),
                 ("Captain's Quarters", lambda x, y: [box(x - 14 * s, y - 7 * s, x + 14 * s, y + 7 * s)]), ("Lounge P", lambda x, y: [ring(x, y, 8 * s)]),
                 ("Navigation", lambda x, y: [ring(x, y, 8 * s)])]:
        if has(k): U.feat(N(k), f(*U.ctr(N(k))))
    for k, sd, lab in [("Captain's Quarters", "w", "locker"), ("Security Office", "w", "weapon rack"), ("Cabins A", "w", "locker"),
                       ("Lounge P", "n", "med station"), ("Galley", "w", "fuse box"), ("Targeting", "w", "console")]:
        if has(k): U.wallniche(N(k), sd, 0, lab)
    if hatch_up: U.hatch((ax, round(Y(680), 1)), "v"); U.hatch((round(X(400), 1), round(yl, 1)), "h")
    SH = {"Observation Dome": "Observation", "Captain's Quarters": "Captain", "First Officer": "1st Officer", "Security Office": "Security",
          "Weapons Locker": "Weapons", "Officers' Mess": "Mess", "Gunnery Control": "Gunnery"}
    short = {N(k): v for k, v in SH.items() if k not in names}
    short.update({v: v[:11] for v in names.values() if len(v) > 12})
    bad = decklib.run(sid, here, src, ax, "upper", 1, U.R, U.H, U.D, [shaft], title=upper_title, features=U.F, short=short,
                      whole=WHU, niches=U.NICHE, hatches=U.HATCH, source=U.FROM, fits=U.FIT, round_rooms={N("Observation Dome"), N("Officers' Mess")}, **checks)

    # ================================================================= LOWER DECK - HOLD
    L = Deck(ax)
    L.room("Lift", lift, "lift car (the main deck's %s shaft)" % lift_room)
    ls = P("Life Support", 440, 420)
    L.room(N("Life Support"), lib("kasparov_a_14", *ls, w=W("Life Support", 6.4), h=W("Life Support", 6.4)), "kasparov_a_14 round machine room",
           twin=N("Water Recycling"), feat=[ring(ls[0] + 5 * s, ls[1] - 2 * s, 15 * s), circle(ls[0] + 5 * s, ls[1] - 2 * s, 6 * s).exterior])
    L.room(N("Brig"), lib("malgus_07", *P("Brig", 512, 647), w=W("Brig", 3.8), h=W("Brig", 11.4), rot=90), "malgus_07 entry corridor as the cell corridor")
    BX0, BY0, BX1, BY1 = [round(v, 1) for v in L.R[N("Brig")].bounds]
    hh = (BY1 - BY0) / 3
    for i in range(3):
        y = BY0 + hh * (i + 0.5)
        L.room(N("Cell %d" % (i + 1)), lib("kasparov_b_01", BX0 - 36 * s, y, w=7.2 * s, h=hh / 10), "kasparov_b_01 cabin",
               twin=N(["Detention", "Cell 4", "Cell 5"][i]), feat=[box(BX0 - 56 * s, y - 7 * s, BX0 - 46 * s, y + 7 * s)])
    LO = [("Cargo Hold A", "kasparov_b_11", 361, 696, 8.2, 5.8, {"rot": 90}, "kasparov_b_11 cargo bay", "Cargo Hold B"),
          ("Torpedo Store P", "fury_01", 300, 762, 8.6, 6.0, {"rot": 90}, "fury_01 cargo hold", "Torpedo Store S"),
          ("Machine Shop", "tianjin_29", 437, 886, 8.2, 5.4, {}, "tianjin_29 machineshop", "Fuel Store")]
    for k, rid, x, y, w, h, kw, why, tw in LO:
        if has(k): L.room(N(k), lib(rid, *P(k, x, y), w=W(k, w), h=W(k, h), **kw), why, twin=N(tw))
    sg = P("Shield Gen P", 433, 816)
    if has("Shield Gen P"):
        L.room(N("Shield Gen P"), lib("kasparov_a_14", *sg, w=W("Shield Gen P", 8.4), h=W("Shield Gen P", 8.4)), "kasparov_a_14 round machine room",
               twin=N("Shield Gen S"), feat=[ring(sg[0] + 8 * s, sg[1] - 6 * s, 18 * s), circle(sg[0] + 8 * s, sg[1] - 6 * s, 8 * s).exterior])
    cp = P("Coolant Pumps", 512, 982); rc = 38 * s
    L.room(N("Coolant Pumps"), circle(*cp, rc), "tianjin_14 round room (pump in a ring walkway), drawn true round", feat=[ring(*cp, 22 * s), circle(*cp, 9 * s).exterior])
    bt = P("Battery P", 457, 1036)
    if has("Battery P"):
        L.room(N("Battery P"), lib("kasparov_a_14", *bt, w=W("Battery P", 5.8), h=W("Battery P", 5.8)), "kasparov_a_14 round machine room", twin=N("Battery S"),
               feat=[ring(bt[0] + 4 * s, bt[1] + 4 * s, 13 * s), circle(bt[0] + 4 * s, bt[1] + 4 * s, 5 * s).exterior])
    pc = P("Escape Pods", 512, 1060); r0, r1 = 52 * s, 82 * s
    if has("Escape Pods"):
        L.room(N("Escape Pods"), sector(*pc, r0, r1, 45, 135), "carrick ring corridor (arc, 3 m), pod hatches along the hull")
    y570, y740, y920 = Y(570), Y(740), Y(920)
    L.H += spine(ls[1] - 12, y570) + [hall((ax, y740), (ax, y920), w=22), junction(ax, y570, 4.0), junction(ax, y740), junction(ax, y920)]
    if has("Battery P"): L.H.append(hall((bt[0] + 30 * s, pc[1]), (2 * ax - bt[0] - 30 * s, pc[1]), w=16))
    xs = X(409)
    L.hall(hall((ax, y570), (xs, y570), w=18)); L.hall(hall((xs, y570), (xs, y740), w=18)); L.hall(hall((ax, y740), (X(331), y740), w=18))
    WHL = {"Lift", N("Life Support"), N("Water Recycling"), N("Shield Gen P"), N("Shield Gen S"), N("Coolant Pumps"), N("Battery P"), N("Battery S"), N("Escape Pods")}
    if extra_lower: extra_lower(L, X, Y)
    L.R = decklib.settle(L.R, L.H, whole=WHL, twins=L.TW, mirror_fn=L.M, mode="close")
    lift_doors(L)
    L.link(N("Life Support"), (SP, ls[1])); L.door(ax, BY0, "h", both=False)
    for i in range(3): L.door(BX0, round(L.R[N("Cell %d" % (i + 1))].centroid.y, 1), "v")
    if has("Cargo Hold A"): L.link(N("Cargo Hold A"), (xs - 9, P("Cargo Hold A", 0, 696)[1]))
    if has("Shield Gen P"): L.link(N("Shield Gen P"), (sg[0] + 8 * s, y740 + 9))
    if has("Torpedo Store P"): L.link(N("Torpedo Store P"), (P("Torpedo Store P", 341, 0)[0], y740 + 9))
    if has("Machine Shop"): L.link(N("Machine Shop"), (SP, P("Machine Shop", 0, 880)[1]))
    c = L.R[N("Coolant Pumps")]; ct, cb = c.bounds[1], c.bounds[3]
    L.H.append(hall((ax, y920 + 9), (ax, ct), w=16).difference(c)); L.door(ax, round(ct, 1), "h", both=False)
    if has("Escape Pods"):
        L.H.append(hall((ax, cb), (ax, pc[1] - 8), w=16).difference(c)); L.door(ax, round(cb, 1), "h", both=False)
        pt = L.R[N("Escape Pods")].intersection(LineString([(ax, pc[1]), (ax, pc[1] + 300)])).bounds[1]
        L.H.append(hall((ax, pc[1] + 8), (ax, pt), w=16).difference(L.R[N("Escape Pods")])); L.door(ax, round(pt, 1), "h", both=False)
    if has("Battery P"): L.link(N("Battery P"), (bt[0] + 30 * s, pc[1]))
    L.R = decklib.finalize(L.R, L.H, list(L.R), L.TW, L.M, keep=WHL)
    L.D = list(dict.fromkeys(L.D))
    def crates(k):
        x0, y0, x1, y1 = L.R[k].bounds; cx, cy = L.ctr(k); w, h = (x1 - x0) * 0.1, (y1 - y0) * 0.12
        return [box(cx - 2.6 * w, cy - h, cx - 0.6 * w, cy + h), box(cx + 0.6 * w, cy - h, cx + 2.6 * w, cy + h)]
    for k in ("Cargo Hold A", "Torpedo Store P"):
        if has(k): L.feat(N(k), crates(N(k)))
    if has("Machine Shop"): L.feat(N("Machine Shop"), [ring(*L.ctr(N("Machine Shop")), 6 * s)])
    for k, sd, lab in [("Cargo Hold A", "n", "console"), ("Machine Shop", "w", "fuse box")]:
        if has(k): L.wallniche(N(k), sd, 0, lab)
    if has("Escape Pods"):
        for a in (70, 90, 110):
            L.NICHE.append((N("Escape Pods"), (round(pc[0] + r1 * math.cos(math.radians(a)), 1), round(pc[1] + r1 * math.sin(math.radians(a)), 1)), "s", "pod hatch"))
    L.hatch((ax, round(Y(860), 1)), "v")
    SH = {"Life Support": "Life Sup.", "Water Recycling": "Water", "Coolant Pumps": "Coolant", "Escape Pods": "Pods", "Machine Shop": "Machine",
          "Shield Gen P": "Shield P", "Shield Gen S": "Shield S", "Torpedo Store P": "Torpedo P", "Torpedo Store S": "Torpedo S"}
    short = {N(k): v for k, v in SH.items() if k not in names}
    short.update({v: v[:11] for v in names.values() if len(v) > 12})
    bad += decklib.run(sid, here, src, ax, "lower", -1, L.R, L.H, L.D, [shaft], title=lower_title, features=L.F, short=short,
                       whole=WHL, niches=L.NICHE, hatches=L.HATCH, source=L.FROM, fits=L.FIT, anchor={N("Escape Pods"): (pc[0], pc[1] + 68 * s)},
                       round_rooms={N("Life Support"), N("Water Recycling"), N("Shield Gen P"), N("Shield Gen S"), N("Coolant Pumps"), N("Battery P"),
                                    N("Battery S"), N("Escape Pods")},
                       **dict(checks, outline_style=lower_outline))
    decklib.both(os.path.join(here, "deck_upper.png"), os.path.join(here, "deck_lower.png"), os.path.join(here, "decks_plan.jpg"))
    decklib.both(os.path.join(here, "deck_upper_on_map.jpg"), os.path.join(here, "deck_lower_on_map.jpg"), os.path.join(here, "decks_on_map.jpg"))
    decklib.source_sheet([os.path.join(here, "deck_upper.json"), os.path.join(here, "deck_lower.json")], os.path.join(here, "decks_sources.jpg"))
    print("TOTAL FAILURES (both decks):", len(bad))
    return bad
