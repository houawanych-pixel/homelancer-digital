#!/usr/bin/env python3
"""Veranthos Senate Station: five walkable decks measured from its own exterior model (v13.01 station rebuild).

Owner: "Replace the old Zelda-style station layouts ... built to the matching exterior silhouettes and new blueprint
concepts ... Measure the actual models ... Start with Veranthos." The blueprint picture
(HL_Unity_Veranthos-SenateStation_Hub3Level_BLUEPRINT_GENERATED_20261110_v3.png) is a ROOM-LAYOUT CONCEPT, not
geometry: the rooms it names are kept; every outline here comes from the model st3d_veranthos_senate.glb.

  python3 build_veranthos.py assets/stations3d/st3d_veranthos_senate.glb assets/stations_int [report_dir]

What is measured (and written to the report):
  - the model's size at the game's scale (STATION_WIDTH 340 m x st3d_scale 12.8 = 4352 m per model unit)
  - the hull footprint at each deck's height: every triangle crossing a thin slab at that height, drawn from above,
    closed, small holes filled, only the piece joined to the centre kept, then pulled in 9 m for the hull's thickness
  - the radial arms on the main deck (their directions are read from the model, not from the picture)
Decks: L3 MAIN, L2 UPPER and L4 LOWER follow the three pictured decks. L1 DOME and L5 KEEL are DESIGNED ADDITIONS
(marked "proposed"): the picture has no such floors; rooms the picture puts on its upper / lower map are moved there.
Lifts: four through-shafts on the diagonals at one radius, the same x,z on every deck. No central lift.
Not in this pass (owner): combat, quests, key locks.
Needs: numpy, opencv, trimesh.
"""
import json, sys, os
import numpy as np, cv2, trimesh

K = 340.0 * 12.8          # metres per model unit
PX = 3.0                  # metres per pixel of the working masks
N = 1500                  # mask size (4500 m square, the station in the middle)
HULL = 9.0                # m: hull thickness kept clear inside the measured footprint
WALL = 9.0                # m: wall between rooms
BODY_R = 1250.0           # m: a hole in a slab that lies wholly inside this radius is the body's own inside
LIFT_R = 440.0            # m: the four shafts' distance from the axis (inside the smallest deck, outside the hub)
LIFT_A = (45, 135, 225, 315)
C = N / 2.0

def P(x, z): return (int(round(C + x / PX)), int(round(C + z / PX)))
def pol(r, a):            # a: degrees clockwise from the front (-Z), as on the map (north up)
    t = np.radians(a); return r * np.sin(t), -r * np.cos(t)

def footprint(tri, y, half=0.012 * K, fill_holes_below=40000.0):
    m = (tri[:, :, 1].max(1) >= y - half) & (tri[:, :, 1].min(1) <= y + half)
    im = np.zeros((N, N), np.uint8)
    pts = (tri[m][:, :, [0, 2]] / PX + C).round().astype(np.int32)
    cv2.fillPoly(im, list(pts), 1)
    im = cv2.morphologyEx(im, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    cs, hier = cv2.findContours(im, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    for i, c in enumerate(cs):   # the model is a shell: the body's inside is filled; the open sky between the outer arcs is not
        if hier[0][i][3] < 0: continue
        far = float(np.hypot(c[:, 0, 0] - C, c[:, 0, 1] - C).max()) * PX
        if cv2.contourArea(c) * PX * PX < fill_holes_below or far < BODY_R: cv2.drawContours(im, cs, i, 1, -1)
    n, lab = cv2.connectedComponents(im, connectivity=8)
    core = (lab == lab[int(C), int(C)]).astype(np.uint8) if lab[int(C), int(C)] else np.zeros_like(im)
    k = int(round(HULL / PX))
    return cv2.erode(core, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * k + 1, 2 * k + 1))), core

class Deck:
    def __init__(self, foot):
        self.foot = foot; self.f = np.zeros((N, N), np.uint8); self.rooms = []; self.doors = []
        yy, xx = np.mgrid[0:N, 0:N]
        self.R = np.hypot(xx - C, yy - C) * PX
        self.A = (np.degrees(np.arctan2(xx - C, -(yy - C))) % 360.0)
    def band(self, r0, r1, a0=None, a1=None):
        m = (self.R >= r0) & (self.R < r1)
        if a0 is not None:
            a0 %= 360; a1 %= 360
            m &= ((self.A >= a0) & (self.A < a1)) if a0 < a1 else ((self.A >= a0) | (self.A < a1))
        return m.astype(np.uint8)
    def corridor(self, m): self.f |= (m & self.foot)
    def avenue(self, a, r0, r1, w):                       # a straight radial passage
        x0, z0 = pol(r0, a); x1, z1 = pol(r1, a)
        m = np.zeros((N, N), np.uint8); cv2.line(m, P(x0, z0), P(x1, z1), 1, int(round(w / PX)))
        self.corridor(m)
    def room(self, name, m, min_area=1800.0):
        m = (m & self.foot & (1 - cv2.dilate(self.f, np.ones((2 * int(WALL / PX) + 1,) * 2, np.uint8)))).astype(np.uint8)
        n, lab, st, _ = cv2.connectedComponentsWithStats(m, connectivity=4)
        if n < 2: return None
        i = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
        if st[i, cv2.CC_STAT_AREA] * PX * PX < min_area: return None
        m = (lab == i).astype(np.uint8)
        dm = cv2.distanceTransform(m, cv2.DIST_L2, 5); y, x = np.unravel_index(int(np.argmax(dm)), dm.shape)
        self.f |= m
        r = {"name": name, "mask": m, "at": ((x - C) * PX, (y - C) * PX), "rad": float(dm[y, x]) * PX, "doors": 0}
        self.rooms.append(r); return r
    def door(self, x, z, yaw, w=14.0, depth=None, room=None, clip=False):
        """A doorway cut through a wall at (x, z); yaw (degrees) = the direction you walk through it."""
        depth = depth or (WALL + 12.0)
        t = np.radians(yaw); d = np.array([np.sin(t), -np.cos(t)]); s = np.array([d[1], -d[0]])
        c = np.array([x, z])
        pts = [c + a * s * w / 2 + b * d * depth / 2 for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        m = np.zeros((N, N), np.uint8); cv2.fillPoly(m, [np.array([P(*p) for p in pts], np.int32)], 1)
        if clip: m &= self.foot
        elif (m & (1 - self.foot)).any(): return False
        self.f |= m
        self.doors.append({"x": round(float(x), 1), "z": round(float(z), 1), "yaw": round(float(yaw), 1), "w": w})
        if room is not None: room["doors"] += 1
        return True
    def rdoor(self, r, a, room=None, w=14.0, clip=False):  # a door through a ring wall (you walk along the radius)
        x, z = pol(r, a); return self.door(x, z, a, w, room=room, clip=clip)
    def tdoor(self, r, a, room=None, w=14.0):             # a door through a radial wall (you walk round the ring)
        x, z = pol(r, a); return self.door(x, z, a + 90, w, room=room)

def district(dk, name, r0, r1, a0, a1, rows, seed, inner=True, outer=True, sides=(None, None)):
    """A district between two ring passages, cut into a varied cluster of rooms (never equal wedges): `rows` gives
    how many rooms each row across the depth holds; the cuts are uneven. Each room opens onto the passage it faces;
    a middle-row room opens into its neighbours. Returns the rooms made."""
    rng = np.random.RandomState(seed)
    span = (a1 - a0) % 360
    edges = np.linspace(r0, r1, len(rows) + 1)
    if len(rows) > 1: edges[1:-1] += rng.uniform(-0.12, 0.12, len(rows) - 1) * (r1 - r0) / len(rows)
    made = []; k = 0
    for ri, cnt in enumerate(rows):
        ra, rb = edges[ri] + (WALL / 2 if ri else 0), edges[ri + 1] - (WALL / 2 if ri < len(rows) - 1 else 0)
        cuts = np.sort(rng.uniform(0.25, 0.75, cnt - 1) * 0 + (np.arange(1, cnt) / cnt + rng.uniform(-0.3, 0.3, cnt - 1) / cnt)) if cnt > 1 else []
        ang = [0.0] + list(cuts) + [1.0]
        gap = np.degrees(WALL / 2 / ((ra + rb) / 2))
        row = []
        for ci in range(cnt):
            b0 = a0 + ang[ci] * span + (gap if ci else 0); b1 = a0 + ang[ci + 1] * span - (gap if ci < cnt - 1 else 0)
            k += 1
            r = dk.room("%s %d" % (name, k) if sum(rows) > 1 else name, dk.band(ra, rb, b0, b1))
            if r is None: row.append(None); continue
            mid = a0 + (ang[ci] + ang[ci + 1]) / 2 * span
            if ri == 0 and inner: dk.rdoor(r0 - WALL / 2, mid, r)
            if ri == len(rows) - 1 and outer: dk.rdoor(r1 + WALL / 2, mid, r)
            r["_mid"] = mid; r["_r"] = (ra, rb); r["_b"] = (b0, b1); row.append(r); made.append(r)
        for ci in range(cnt - 1):                          # neighbours along the row
            if row[ci] and row[ci + 1] and (row[ci]["doors"] < 2 or row[ci + 1]["doors"] < 2 or rng.rand() < 0.5):
                if dk.tdoor((ra + rb) / 2, a0 + ang[ci + 1] * span, row[ci]): row[ci + 1]["doors"] += 1
        if ri > 0:                                         # and through to the row inside it
            prev = [p for p in made if p.get("_row") == ri - 1]
            for r in row:
                if r is None: continue
                for p in prev:
                    lo, hi = max(r["_b"][0], p["_b"][0]), min(r["_b"][1], p["_b"][1])
                    if hi - lo > 2 * np.degrees(12.0 / ra) and (r["doors"] < 2 or p["doors"] < 2):
                        if dk.rdoor(ra - WALL / 2, (lo + hi) / 2, r): p["doors"] += 1
                        break
        for r in row:
            if r is not None: r["_row"] = ri
    # the district's end rooms open onto the avenues beside it
    for r in made:
        for side, av in ((0, sides[0]), (1, sides[1])):
            if av is None: continue
            edge = r["_b"][side]
            if abs(((edge - (a0 if side == 0 else a1)) + 180) % 360 - 180) < 1.5 and r["doors"] < 2:
                rr = (r["_r"][0] + r["_r"][1]) / 2
                off = np.degrees((WALL / 2 + 1) / rr) * (-1 if side == 0 else 1)
                dk.tdoor(rr, (a0 if side == 0 else a1) + off * 0 + (np.degrees(WALL / 2 / rr) * (-1 if side == 0 else 1)), r)
    return made

def outlines(mask):
    cs, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    out = []
    for c in cs:
        if len(c) < 10: continue
        a = cv2.approxPolyDP(c, 0.6, True).reshape(-1, 2).astype(float)
        if len(a) < 3: continue
        a += 0.5; votes = 0
        for k in range(len(a)):
            p, q = a[k], a[(k + 1) % len(a)]; e = q - p; L = np.hypot(*e)
            if L < 2: continue
            m = (p + q) / 2 + np.array([e[1], -e[0]]) / L * 1.6
            x, y = int(m[0]), int(m[1])
            if 0 <= x < N and 0 <= y < N: votes += 1 if mask[y, x] else -1
        if votes < 0: a = a[::-1]
        out.append([round(float(v), 1) for v in ((a - C) * PX).reshape(-1)])
    return out

def lifts_xy(): return [[round(v, 1) for v in pol(LIFT_R, a)] for a in LIFT_A]

def ring_core(dk, hub_name, hub_r, ring=(410.0, 470.0), hub_doors=(0, 90, 180, 270)):
    """What every deck shares: the central room, the lift concourse round it with the four shafts on it."""
    dk.corridor(dk.band(ring[0], ring[1]))
    hub = dk.room(hub_name, dk.band(0, ring[0] - WALL))
    for a in hub_doors: dk.rdoor(ring[0] - WALL / 2, a, hub, w=22.0)
    return hub

def build(glb, outdir, repdir=None):
    mesh = trimesh.load(glb, force="scene")
    mesh = mesh.to_geometry() if hasattr(mesh, "to_geometry") else mesh.dump(concatenate=True)
    v = np.asarray(mesh.vertices) * K; tri = v[np.asarray(mesh.faces)]
    rep = {"model": os.path.basename(glb), "metres_per_model_unit": K,
           "size_m": {"x": round(float(np.ptp(v[:, 0]))), "z": round(float(np.ptp(v[:, 2]))), "height": round(float(np.ptp(v[:, 1])))}}
    # the radial arms, read from the model: hull between 1300 and 1700 m from the axis, by direction
    cen = tri.mean(1); rr = np.hypot(cen[:, 0], cen[:, 2]); aa = np.degrees(np.arctan2(cen[:, 0], -cen[:, 2])) % 360
    h, _ = np.histogram(aa[(rr > 1300) & (rr < 1700)], bins=120, range=(0, 360))
    hs = np.convolve(np.r_[h[-2:], h, h[:2]], np.ones(3) / 3, "valid")[1:-1] if False else h.astype(float)
    arms = []; i = 0; on = hs > 0.04 * hs.max()
    start = next(j for j in range(120) if not on[j])
    for j in range(start, start + 121):
        jj = j % 120
        if on[jj] and (not arms or arms[-1][1] is not None): arms.append([jj, None, 0.0, 0.0])
        if on[jj]: arms[-1][2] += hs[jj] * (j * 3 + 1.5); arms[-1][3] += hs[jj]
        elif arms and arms[-1][1] is None: arms[-1][1] = jj
    arm_dirs = sorted(round((a[2] / a[3]) % 360, 1) for a in arms if a[3] > 0)
    rep["arms"] = {"count": len(arm_dirs), "directions_deg_clockwise_from_front": arm_dirs, "blueprint_picture_shows": 10}
    LEVELS = [("L1", "DOME DECK", 0.11, True), ("L2", "UPPER DECK", 0.06, False), ("L3", "MAIN DECK", -0.035, False),
              ("L4", "LOWER DECK", -0.065, False), ("L5", "KEEL DECK", -0.11, True)]
    decks = []; levels_out = []
    for lid, lname, ym, proposed in LEVELS:
        foot, raw = footprint(tri, ym * K)
        dk = Deck(foot)
        Rin = float(dk.R[foot == 0].min()) if (foot == 0).any() else 9999.0     # the biggest circle about the axis inside the hull
        if lid == "L3":
            ring_core(dk, "Central Public Hub / Senate Rotunda", 380.0, hub_doors=(0, 45, 90, 135, 180, 225, 270, 315))
            Rp0 = Rin - 150.0                                   # the promenade follows the rim, 150 m wide
            dk.corridor(dk.band(Rp0, Rin + 5))
            spans = [("Customs / Arrivals", 336, 22, (2, 3)), ("Medbay", 22, 62, (2, 2)), ("Mission Center", 62, 108, (1, 2)),
                     ("Security Post", 108, 166, (2, 2)), ("Cantina / Lounge", 192, 244, (2, 3)),
                     ("Embassy Row", 244, 292, (3, 2)), ("Market / Shops", 292, 336, (3, 4))]
            bounds = sorted({s[1] for s in spans} | {s[2] for s in spans} | {166, 192})
            for a in bounds: dk.avenue(a, 470.0, Rp0, 30.0)     # avenues between the districts, ring to promenade
            av = np.degrees(15.0 + WALL) / 1.0
            for si, (nm, a0, a1, rows) in enumerate(spans):
                pad0 = np.degrees((15.0 + WALL) / 700.0)
                district(dk, nm, 470.0 + WALL, Rp0 - WALL, a0 + pad0, a1 - pad0, rows, 11 + si)
            ep = dk.room("Escape Pod", dk.band(470.0 + WALL, 640.0, 166 + 2.4, 192 - 2.4))
            if ep: dk.rdoor(470.0 + WALL / 2, 179, ep)
            # the arms, the outer arcs and the pods: whatever of the measured footprint lies beyond the rim is walkable
            # as measured. Each arm the model has (directions read from the model above) gets a gate on the promenade
            # and its pod is a named place.
            beyond = (foot & (dk.R > Rin + 5 + WALL).astype(np.uint8))
            dk.f |= beyond
            names = {0: "North Docking Bay", 180: "South Docking Bay", 90: "East Hangar Approach", 270: "West Hangar Approach"}
            got = []
            for a_arm in arm_dirs:
                near_name = min(names, key=lambda q: abs((a_arm - q + 180) % 360 - 180))
                nm = names[near_name] if abs((a_arm - near_name + 180) % 360 - 180) < 8 else "Docking Arm %03d" % int(round(a_arm))
                dev = np.abs((dk.A - a_arm + 180) % 360 - 180)
                pod = (beyond & (dev < 7) & (dk.R > 1650)).astype(np.uint8)
                neck = (beyond & (dev < 4) & (dk.R < Rin + 120)).astype(np.uint8)
                if pod.sum() == 0 or neck.sum() == 0: got.append({"name": nm, "direction_deg": a_arm, "built": False}); continue
                dm = cv2.distanceTransform(pod, cv2.DIST_L2, 5); y, x = np.unravel_index(int(np.argmax(dm)), dm.shape)
                r = {"name": nm, "mask": pod, "at": ((x - C) * PX, (y - C) * PX), "rad": float(dm[y, x]) * PX, "doors": 1}
                dk.rooms.append(r)
                nys, nxs = np.nonzero(neck); a_gate = float(np.degrees(np.arctan2(nxs.mean() - C, -(nys.mean() - C))) % 360)
                wn = float(cv2.distanceTransform(neck, cv2.DIST_L2, 5).max()) * PX * 2
                dk.rdoor(Rin + 5 + WALL / 2, a_gate, None, w=min(18.0, max(8.0, wn - 4)), clip=True)
                got.append({"name": nm, "direction_deg": a_arm, "built": True, "reaches_m": round(float(dk.R[pod > 0].max())), "arm_inside_width_m": round(wn, 1)})
            rep["main_deck_arms_built"] = got
        elif lid == "L2":
            ring_core(dk, "Senate Chamber", 380.0)
            Ro = Rin - 6
            spans = [("Delegate Offices (north)", 330, 30, (3,)), ("Delegate Offices", 30, 140, (5,)), ("Officer Quarters", 140, 250, (6,)), ("Command / Comms", 250, 330, (3,))]
            for a in (330, 30, 140, 250): dk.avenue(a, 470.0, Ro, 24.0)
            for si, (nm, a0, a1, rows) in enumerate(spans):
                pad0 = np.degrees((12.0 + WALL) / 560.0)
                district(dk, nm, 470.0 + WALL, Ro, a0 + pad0, a1 - pad0, rows, 31 + si, outer=False)
        elif lid == "L1":
            dk.corridor(dk.band(410.0, min(470.0, Rin)))
            arch = dk.room("Archives / Records", dk.band(0, 210.0))
            gal = dk.room("Observation Gallery", dk.band(210.0 + WALL, 400.0 - WALL / 2))
            for a in (0, 90, 180, 270): dk.rdoor(405.0 - WALL / 2, a, gal, w=22.0)
            for a in (60, 240): dk.rdoor(210.0 + WALL / 2, a, arch)
            if gal: gal["doors"] += 2
        elif lid == "L4":
            ring_core(dk, "Engineering", 380.0)
            Ro0 = Rin - 70.0
            dk.corridor(dk.band(Ro0, Rin - 30.0))                # the outer service ring
            spans = [("Security / Brig", 300, 60, (3, 4)), ("Life Support", 60, 180, (2, 3)), ("Maintenance", 180, 300, (4, 3))]
            for a in (300, 60, 180): dk.avenue(a, 470.0, Ro0, 30.0)
            for si, (nm, a0, a1, rows) in enumerate(spans):
                pad0 = np.degrees((15.0 + WALL) / 760.0)
                district(dk, nm, 470.0 + WALL, Ro0 - WALL, a0 + pad0, a1 - pad0, rows, 51 + si)
        else:
            ring_core(dk, "Reactor", 380.0, hub_doors=(90, 270))
            Ro = Rin - 6
            for a in (150, 210, 330, 30): dk.avenue(a, 470.0, Ro, 20.0)
            pad0 = np.degrees((10.0 + WALL) / 520.0)
            district(dk, "Cargo", 470.0 + WALL, Ro, 210 + pad0, 330 - pad0, (3,), 71, outer=False)
            district(dk, "Cargo (starboard hold)", 470.0 + WALL, Ro, 30 + pad0, 150 - pad0, (2,), 72, outer=False)
            ep = dk.room("Escape Pod", dk.band(470.0 + WALL, Ro, 150 + pad0, 210 - pad0))
            if ep: dk.rdoor(470.0 + WALL / 2, 180, ep)
            st_ = dk.room("Reactor Control", dk.band(470.0 + WALL, Ro, 330 + pad0, 30 - pad0))   # (working label: a designed addition)
            if st_: dk.rdoor(470.0 + WALL / 2, 0, st_)
        for (x, z) in lifts_xy():                                # the shafts: a lobby bay on the concourse
            m = np.zeros((N, N), np.uint8); cv2.circle(m, P(x, z), int(26 / PX), 1, -1); dk.f |= (m & foot)
        dk.f &= foot
        # keep what you can walk to from the first lift (a person 1.5 m wide: shrink the floor a pixel)
        er = cv2.erode(dk.f, np.ones((3, 3), np.uint8))
        _, lab = cv2.connectedComponents(er, connectivity=4)
        lx = [P(x, z) for x, z in lifts_xy()]
        s0 = lab[lx[0][1], lx[0][0]]
        live = cv2.dilate((lab == s0).astype(np.uint8), np.ones((5, 5), np.uint8)) if s0 else np.zeros_like(dk.f)
        cut = [r["name"] for r in dk.rooms if not live[int(C + r["at"][1] / PX), int(C + r["at"][0] / PX)]]
        dk.f &= live
        dk.rooms = [r for r in dk.rooms if r["name"] not in cut]
        outside = int((dk.f & (1 - raw)).sum())
        lifts_ok = [bool(s0 and lab[p[1], p[0]] == s0) for p in lx]
        one_door = sorted(r["name"] for r in dk.rooms if r["doors"] < 2)
        rep[lid] = {"name": lname, "height_m": round(ym * K), "proposed_addition": proposed, "hull_inscribed_radius_m": round(Rin),
                    "floor_area_km2": round(float(dk.f.sum()) * PX * PX / 1e6, 3), "floor_outside_measured_hull_px": outside,
                    "rooms": len(dk.rooms), "doors": len(dk.doors), "rooms_dropped_unreachable": cut,
                    "lifts_on_walkable_floor": lifts_ok, "one_door_rooms": one_door}
        decks.append((lid, lname, ym, proposed, dk, raw))
        # the deck map (north up = the docking front), the measured hull behind the rooms
        im = np.zeros((N, N, 3), np.uint8); im[:] = (40, 16, 8); im[raw > 0] = (70, 34, 14); im[dk.f > 0] = (110, 62, 20)
        cs, _ = cv2.findContours(raw, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE); cv2.drawContours(im, cs, -1, (160, 110, 40), 2, cv2.LINE_AA)
        cs, _ = cv2.findContours(dk.f, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE); cv2.drawContours(im, cs, -1, (255, 230, 90), 1, cv2.LINE_AA)
        for d_ in dk.doors: cv2.circle(im, P(d_["x"], d_["z"]), 3, (90, 255, 90), -1)
        for (x, z), nm in zip(lifts_xy(), ("NE", "SE", "SW", "NW")):
            p = P(x, z); cv2.rectangle(im, (p[0] - 8, p[1] - 8), (p[0] + 8, p[1] + 8), (255, 255, 255), 2)
            cv2.putText(im, "LIFT " + nm, (p[0] - 26, p[1] - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1, cv2.LINE_AA)
        for r in dk.rooms:
            t = r["name"].upper(); fs = 0.42 if r["rad"] > 60 else 0.3
            sz = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, fs, 1)[0]; p = P(*r["at"])
            cv2.putText(im, t, (p[0] - sz[0] // 2, p[1] + 4), cv2.FONT_HERSHEY_SIMPLEX, fs, (255, 255, 255), 1, cv2.LINE_AA)
        cv2.putText(im, "VERANTHOS SENATE STATION  -  %s %s" % (lid, lname), (30, 44), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 240, 170), 2, cv2.LINE_AA)
        cv2.putText(im, ("DESIGNED ADDITION - not on the blueprint picture" if proposed else "rooms from the blueprint concept") + "  |  outline measured from st3d_veranthos_senate at %+d m" % round(ym * K),
                    (30, 72), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (120, 200, 255), 1, cv2.LINE_AA)
        mp = "veranthos_%s.jpg" % lid.lower()
        cv2.imwrite(os.path.join(outdir, mp), cv2.resize(im, (1024, 1024), interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 85])
        if repdir: cv2.imwrite(os.path.join(repdir, "veranthos_%s_full.jpg" % lid.lower()), im, [cv2.IMWRITE_JPEG_QUALITY, 88])
        levels_out.append({"id": lid, "name": lname, "y": round(ym * K, 1), "proposed": proposed, "map": mp,
                           "walls": outlines(dk.f), "doors": dk.doors,
                           "rooms": [{"name": r["name"], "x": round(r["at"][0], 1), "z": round(r["at"][1], 1), "rad": round(r["rad"] * 1.4, 1)} for r in dk.rooms],
                           "lifts": lifts_xy()})
    # lift alignment: the same x,z on every deck, on walkable floor on every deck
    rep["lifts"] = {"shafts_xz_m": dict(zip(("NE", "SE", "SW", "NW"), lifts_xy())), "distance_from_axis_m": LIFT_R,
                    "serve": "all four shafts serve L1-L5" if all(all(rep[l[0]]["lifts_on_walkable_floor"]) for l in LEVELS) else "NOT all shafts reach every deck: see each deck"}
    out = {"id": "veranthos", "name": "Veranthos Senate Station", "model": "st3d_veranthos_senate", "system": "veranthos",
           "extent_m": N * PX, "start": {"level": "L3", "x": lifts_xy()[2][0] + 30.0, "z": lifts_xy()[2][1]},
           "note": "Outlines measured from the exterior model. Rooms follow the blueprint concept on L2-L4; L1 and L5 are designed additions. No combat, quests or key locks in this pass.",
           "levels": levels_out}
    json.dump(out, open(os.path.join(outdir, "veranthos.json"), "w"), separators=(",", ":"))
    if repdir:
        json.dump(rep, open(os.path.join(repdir, "veranthos_report.json"), "w"), indent=1)
        # side view: the model's profile with the five deck floors (their real width at that height) drawn on it
        S = 0.25; W_ = 1200; H_ = 700
        im = np.zeros((H_, W_, 3), np.uint8); im[:] = (40, 16, 8)
        pts = np.stack([v[:, 0] * S + W_ / 2, -v[:, 1] * S + H_ / 2], 1)
        cv2.fillPoly(im, list(pts[np.asarray(mesh.faces)].round().astype(np.int32)), (120, 80, 40))
        for lid, lname, ym, proposed, dk, raw in decks:
            xs = np.nonzero(dk.f.any(axis=0))[0]; x0, x1 = (xs.min() - C) * PX, (xs.max() - C) * PX
            y = int(-ym * K * S + H_ / 2)
            cv2.line(im, (int(x0 * S + W_ / 2), y), (int(x1 * S + W_ / 2), y), (90, 255, 255) if not proposed else (90, 160, 255), 3)
            cv2.putText(im, "%s %s  %+d m" % (lid, lname, round(ym * K)), (20, y + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1, cv2.LINE_AA)
        for a in LIFT_A:
            x = pol(LIFT_R, a)[0]
            cv2.line(im, (int(x * S + W_ / 2), int(-0.11 * K * S + H_ / 2)), (int(x * S + W_ / 2), int(0.11 * K * S + H_ / 2)), (255, 255, 255), 1)
        cv2.putText(im, "SIDE VIEW (from the front): st3d_veranthos_senate at game scale, deck floors and lift shafts", (20, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 240, 170), 1, cv2.LINE_AA)
        cv2.imwrite(os.path.join(repdir, "veranthos_side.jpg"), im, [cv2.IMWRITE_JPEG_QUALITY, 88])
    print(json.dumps(rep, indent=1))

if __name__ == "__main__":
    build(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
