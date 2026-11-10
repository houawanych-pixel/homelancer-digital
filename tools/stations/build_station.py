#!/usr/bin/env python3
"""Station interiors from a spec (v13.01 station rebuild): the same method as build_veranthos.py, for the other stations.

Owner (10 Nov): rooms are purpose-shaped, districts are walled complexes with their own corridors (his ChatGPT
interior study of Veranthos), the outer line is clean geometry (a round body, straight spokes, shaped pods, docking
ports along the spokes), four lift shafts at the same place on every deck, no central lift.

  python3 build_station.py aurelion assets/stations3d assets/stations_int [report_dir]

Each deck: the body is the largest circle that fits inside the measured hull at that height (floor and 18 m of
headroom both inside the model), about the body's own centre (measured; the model need not be centred on its origin).
Needs: numpy, opencv, trimesh.
"""
import json, sys, os
import numpy as np, cv2, trimesh
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_veranthos as B
from build_veranthos import K, PX, N, C, WALL, P, pol, Deck, complex_, shape, scalloped, outlines, _w

SEC = "sector"
SPECS = {
    # Room names: the districts are the ones named on the owner's deck picture
    # (HL_Elyza_Aurelion-CapitalOrbitalCitadel_Hub3Level_HoloDeck_20261110_v3); the rooms inside each are working labels.
    "aurelion": {
        "name": "Aurelion Capital Orbital Citadel", "model": "st3d_aurelion_citadel", "system": "aurelion",
        "centre": (0.0, -210.0), "lift_r": 330.0, "ring": (300.0, 360.0), "av_w": 24.0,
        "arm_names": {0: "North Docking Approach", 180: "South Docking Approach", 90: "East Hangar Approach", 270: "West Hangar Approach"},
        "levels": [
            {"id": "L1", "name": "SPIRE DECK", "y": 130.0, "proposed": True, "hub": "Observation", "hub_doors": (0, 90, 180, 270), "G": 30.0,
             "districts": [(300, 60, [(1, [("Sanctum", 1.4, "apse"), ("Sanctum Antechamber", 1, SEC)])]),
                           (60, 180, [(1, [("Observation Lounge East", 1, "bays"), ("Star Chart Room", 1, "oct")])]),
                           (180, 300, [(1, [("Observation Lounge West", 1, "bays"), ("Archive", 1, SEC)])])]},
            {"id": "L2", "name": "UPPER DECK", "y": 40.0, "proposed": False, "hub": "Command", "hub_doors": (0, 90, 180, 270), "G": 30.0,
             "districts": [(320, 40, [(1, [("Comms Room", 1, "oct"), ("Briefing Room", 1.2, "apse")])]),
                           (40, 140, [(1, [("Rest Quarters %d" % k, 1, (SEC if k != 2 else "oct")) for k in (1, 2, 3)])]),
                           (140, 220, [(1, [("Officers' Mess", 1.3, "capsule"), ("Wardroom", 1, SEC)])]),
                           (220, 320, [(1, [("Crew Quarters %d" % k, 1, (SEC if k != 2 else "keystone")) for k in (1, 2, 3)])])]},
            {"id": "L3", "name": "MAIN DECK", "y": -110.0, "proposed": False, "hub": "Central Public Hub", "hub_doors": (0, 45, 90, 135, 180, 225, 270, 315),
             "G": 34.0, "promenade": 50.0, "arms": True,
             "districts": [(330, 30, [(1.0, [("Arrivals Waiting Lounge", 1, "apse")]), (1.3, [("Customs Hall", 1, SEC), ("Screening Lanes", 1.3, "bays"), ("Baggage Inspection", 1, SEC)])]),
                           (30, 80, [(1.0, [("Pharmacy", 1, "oct")]), (1.3, [("Triage", 1, "keystone"), ("Ward", 1.2, SEC)])]),
                           (80, 130, [(1.0, [("Briefing Room A", 1, "oct")]), (1.3, [("Mission Terminal Hall", 1.3, "bays"), ("Briefing Room B", 1, SEC)])]),
                           (130, 180, [(1.0, [("Security Desk", 1, "apse")]), (1.3, [("Security Office", 1, SEC), ("Holding Cells", 1.2, "bays")])]),
                           (180, 250, [(1.0, [("Cantina Booths", 1, SEC)]), (1.4, [("Cantina Bar", 1.5, "capsule"), ("Lounge", 1, "hex")])]),
                           (250, 330, [(1.0, [("Market Stall %d" % k, 1, SEC) for k in (1, 2)]), (1.3, [("Market Stall %d" % k, 1, (SEC if k != 4 else "oct")) for k in (3, 4, 5, 6)])])]},
            {"id": "L4", "name": "LOWER DECK", "y": -190.0, "proposed": False, "hub": "Engineering", "hub_doors": (0, 90, 180, 270), "G": 34.0, "promenade": 44.0,
             "districts": [(300, 60, [(1.0, [("Security Office", 1, "oct"), ("Armory", 1, SEC)]), (1.3, [("Brig Cells", 1.3, "bays"), ("Security Store 1", 1, SEC), ("Security Store 2", 1, SEC)])]),
                           (60, 180, [(1.0, [("Cargo Office", 1, "oct"), ("Cargo Lift Lobby", 1, SEC)]), (1.3, [("Cargo Hold %d" % k, 1, (SEC if k != 2 else "keystone")) for k in (1, 2, 3, 4)])]),
                           (180, 300, [(1.0, [("Maintenance Office", 1, "oct"), ("Tool Store", 1, SEC)]), (1.3, [("Workshop A", 1.2, "bays"), ("Workshop B", 1, SEC), ("Parts Store", 1, SEC), ("Maintenance Bay", 1, "hex")])])]},
            {"id": "L5", "name": "KEEL DECK", "y": -300.0, "proposed": True, "hub": "Reactor", "hub_doors": (90, 270), "G": 30.0,
             "districts": [(300, 60, [(1, [("Reactor Control", 1.3, "bays"), ("Reactor Monitoring", 1, SEC)])]),
                           (60, 180, [(1, [("Life Support Control", 1, "oct"), ("Air Plant", 1.2, "capsule"), ("Water Plant", 1, SEC)])]),
                           (180, 300, [(1, [("Coolant Store", 1, SEC), ("Escape Pod", 1, "capsule"), ("Keel Store", 1, SEC)])])]},
        ],
    },
}

def build(sid, glbdir, outdir, repdir=None):
    sp = SPECS[sid]
    mesh = trimesh.load(os.path.join(glbdir, sp["model"] + ".glb"), force="scene")
    mesh = mesh.to_geometry() if hasattr(mesh, "to_geometry") else mesh.dump(concatenate=True)
    v = np.asarray(mesh.vertices) * K * sp.get("scale", 1.0)
    v[:, 0] -= sp["centre"][0]; v[:, 2] -= sp["centre"][1]            # work about the body's own centre
    tri = v[np.asarray(mesh.faces)]
    B._HM.clear()
    LIFT_R = sp["lift_r"]; ring = sp["ring"]; LIFT_A = (45, 135, 225, 315)
    lifts = [[round(q, 1) for q in pol(LIFT_R, a)] for a in LIFT_A]
    rep = {"model": sp["model"], "metres_per_model_unit": K, "body_centre_from_model_origin_m": list(sp["centre"]),
           "size_m": {"x": round(float(np.ptp(v[:, 0]))), "z": round(float(np.ptp(v[:, 2]))), "height": round(float(np.ptp(v[:, 1])))}}
    top, bot = B.heightmaps(tri)
    decks = []; levels_out = []
    for L in sp["levels"]:
        lid, y, G = L["id"], L["y"], L.get("G", 34.0)
        mfoot, raw = B.footprint(tri, y)
        tmp = Deck(mfoot)
        Rin = float(tmp.R[mfoot == 0].min())
        foot = (tmp.R < Rin).astype(np.uint8)
        arm_parts = []; ports = []
        if L.get("arms"):
            # arms: read from the model's outline round this deck's height (the hull within 120 m above or below it)
            sil = ((bot < y + 120.0) & (top > y - 120.0)).astype(np.uint8)
            sil = cv2.morphologyEx(sil, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
            beyond = (sil & (tmp.R > Rin + 60).astype(np.uint8))
            Rmax = float(tmp.R[beyond > 0].max()) if beyond.any() else Rin
            far = beyond & (tmp.R > Rin + 0.45 * (Rmax - Rin)).astype(np.uint8)
            h, _ = np.histogram(tmp.A[far > 0], bins=120, range=(0, 360)); on = h > 0.08 * h.max()
            segs = []; start = next((j for j in range(120) if not on[j]), 0)
            for j in range(start, start + 121):
                jj = j % 120
                if on[jj] and (not segs or segs[-1][0]): segs.append([False, 0.0, 0.0])
                if on[jj]: segs[-1][1] += h[jj] * (j * 3 + 1.5); segs[-1][2] += h[jj]
                elif segs and not segs[-1][0]: segs[-1][0] = True
            dirs = sorted(round((s_[1] / s_[2]) % 360, 1) for s_ in segs if s_[2] > 0)
            rep["arms"] = {"count": len(dirs), "directions_deg_clockwise_from_front": dirs}
            names = sp["arm_names"]; kinds = ("rotunda", "oct", "capsule")
            for ai, a_arm in enumerate(dirs):
                near = min(names, key=lambda q: abs((a_arm - q + 180) % 360 - 180))
                cardinal = abs((a_arm - near + 180) % 360 - 180) < 10
                nm = names[near] if cardinal else "Docking Arm %03d" % int(round(a_arm))
                dev = np.abs((tmp.A - a_arm + 180) % 360 - 180)
                pod = (far & (dev < 9)).astype(np.uint8)
                if pod.sum() == 0: continue
                ys, xs = np.nonzero(pod)
                a_true = float(np.degrees(np.arctan2((xs - C).mean(), -(ys - C).mean())) % 360)
                r_far = float(np.percentile(tmp.R[ys, xs], 97)); wid = float(cv2.distanceTransform(pod, cv2.DIST_L2, 5).max()) * PX
                size = float(np.clip(wid * 1.2, 70.0, 120.0)); r_pod = r_far - size
                if r_pod - size < Rin + 60: continue
                c = np.array(pol(r_pod, a_true))
                pm = shape("cross" if cardinal else kinds[ai % 3], c, a_true, size, size * (1.4 if cardinal else 0.8))
                spk = np.zeros((N, N), np.uint8); cv2.line(spk, P(*pol(Rin - 12, a_true)), P(*c), 1, int(round(36.0 / PX)))
                node = np.zeros((N, N), np.uint8)
                for fr in ((0.5,) if r_pod - size - Rin < 320 else (0.3, 0.7)):     # docking ports on both sides of the spoke
                    rr_p = Rin + (r_pod - size - Rin) * fr
                    for sg in (-1, 1):
                        pc = _w(np.array(pol(rr_p, a_true)), a_true, 0.0, sg * 38.0)
                        node |= shape("oct", pc, a_true, 30.0, 24.0)
                        ports.append({"x": round(float(pc[0]), 1), "z": round(float(pc[1]), 1), "arm": nm, "side": "cw" if sg > 0 else "ccw"})
                foot |= pm | spk | node
                arm_parts.append({"name": nm, "a": a_true, "pod": pm, "spoke": spk | node, "c": c, "r_pod": r_pod})
        dk = Deck(foot)
        dk.corridor(dk.band(ring[0], ring[1]))
        hub = dk.room(L["hub"], scalloped(dk, ring[0] - WALL, 12 if ring[0] < 350 else 16, L["hub_doors"]))
        for a in L["hub_doors"]: dk.rdoor(ring[0] - WALL / 2, a, hub, w=22.0)
        prom = L.get("promenade")
        Ro = Rin - 6
        if prom: dk.corridor(dk.band(Rin - prom, Rin)); Ro = Rin - prom - WALL
        avs = sorted({d[0] for d in L["districts"]})
        for a in avs: dk.avenue(a, ring[1], (Rin - prom) if prom else Ro - 16, sp["av_w"])
        for a0, a1, rows in L["districts"]:
            complex_(dk, ring[1] + WALL, Ro, a0, a1, rows, G=G, av_half=sp["av_w"] / 2)
        got = []
        for ap in arm_parts:
            dk.f |= ap["spoke"] | ap["pod"]
            dm = cv2.distanceTransform(ap["pod"], cv2.DIST_L2, 5); cp = P(*ap["c"])
            dk.rooms.append({"name": ap["name"], "mask": ap["pod"], "at": (float(ap["c"][0]), float(ap["c"][1])), "rad": float(dm[cp[1], cp[0]]) * PX, "doors": 1, "links": set()})
            x, z = pol(Rin + 14, ap["a"])
            dk.doors.append({"x": round(float(x), 1), "z": round(float(z), 1), "yaw": round(ap["a"], 1), "w": 36.0})
            got.append({"name": ap["name"], "direction_deg": round(ap["a"], 1), "pod_centre_from_axis_m": round(ap["r_pod"])})
        if got: rep["main_deck_arms_built"] = got
        for (x, z) in lifts:
            m = np.zeros((N, N), np.uint8); cv2.circle(m, P(x, z), int(24 / PX), 1, -1); dk.f |= (m & foot)
        dk.f &= foot
        er = cv2.erode(dk.f, np.ones((3, 3), np.uint8))
        _, lab = cv2.connectedComponents(er, connectivity=4)
        lx = [P(x, z) for x, z in lifts]
        s0 = lab[lx[0][1], lx[0][0]]
        live = cv2.dilate((lab == s0).astype(np.uint8), np.ones((5, 5), np.uint8)) if s0 else np.zeros_like(dk.f)
        cut = [r["name"] for r in dk.rooms if not live[int(C + r["at"][1] / PX), int(C + r["at"][0] / PX)]]
        dk.f &= live
        dk.rooms = [r for r in dk.rooms if r["name"] not in cut]
        outside = int((dk.f & (1 - raw)).sum())
        rep[lid] = {"name": L["name"], "height_m": round(y), "proposed_addition": L["proposed"], "hull_inscribed_radius_m": round(Rin),
                    "floor_area_km2": round(float(dk.f.sum()) * PX * PX / 1e6, 3), "floor_outside_measured_hull_m2": round(outside * PX * PX),
                    "rooms": len(dk.rooms), "doors": len(dk.doors), "rooms_dropped_unreachable": cut,
                    "lifts_on_walkable_floor": [bool(s0 and lab[p[1], p[0]] == s0) for p in lx],
                    "one_door_rooms": sorted(r["name"] for r in dk.rooms if r["doors"] < 2)}
        decks.append((L, dk))
        hullm = cv2.dilate(foot, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13, 13)))
        im = np.zeros((N, N, 3), np.uint8); im[:] = (40, 16, 8); im[hullm > 0] = (62, 30, 12); im[dk.f > 0] = (110, 62, 20)
        cs, _ = cv2.findContours(hullm, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE); cv2.drawContours(im, cs, -1, (200, 150, 60), 2, cv2.LINE_AA)
        cs, _ = cv2.findContours(dk.f, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE); cv2.drawContours(im, cs, -1, (255, 230, 90), 1, cv2.LINE_AA)
        # crop to the station, so the map fills its frame
        ext = max(Rin + 120.0, float(Deck(foot).R[foot > 0].max()) + 80.0); h_ = int(min(C, ext / PX))
        for d_ in dk.doors: cv2.circle(im, P(d_["x"], d_["z"]), 3, (90, 255, 90), -1)
        for (x, z), nm in zip(lifts, ("NE", "SE", "SW", "NW")):
            p = P(x, z); cv2.rectangle(im, (p[0] - 7, p[1] - 7), (p[0] + 7, p[1] + 7), (255, 255, 255), 2)
        im = im[int(C) - h_:int(C) + h_, int(C) - h_:int(C) + h_]
        sc = 1500.0 / im.shape[0]; im = cv2.resize(im, (1500, 1500), interpolation=cv2.INTER_AREA if sc < 1 else cv2.INTER_CUBIC)
        def Q(x, z): return (int(750 + x / PX * sc), int(750 + z / PX * sc))
        for (x, z), nm in zip(lifts, ("NE", "SE", "SW", "NW")):
            p = Q(x, z); cv2.putText(im, "LIFT " + nm, (p[0] - 26, p[1] - 14), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1, cv2.LINE_AA)
        for r in dk.rooms:
            t = r["name"].upper(); fs = 0.42 if r["rad"] * sc > 60 else 0.32
            sz = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, fs, 1)[0]; p = Q(*r["at"])
            cv2.putText(im, t, (p[0] - sz[0] // 2, p[1] + 4), cv2.FONT_HERSHEY_SIMPLEX, fs, (255, 255, 255), 1, cv2.LINE_AA)
        cv2.putText(im, "%s  -  %s %s" % (sp["name"].upper(), lid, L["name"]), (30, 44), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 240, 170), 2, cv2.LINE_AA)
        cv2.putText(im, ("DESIGNED ADDITION - not on the blueprint picture" if L["proposed"] else "districts from the blueprint concept") + "  |  clean outline fitted to %s at %+d m" % (sp["model"], round(y)),
                    (30, 72), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (120, 200, 255), 1, cv2.LINE_AA)
        mp = "%s_%s.jpg" % (sid, lid.lower())
        cv2.imwrite(os.path.join(outdir, mp), cv2.resize(im, (1024, 1024), interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 85])
        if repdir: cv2.imwrite(os.path.join(repdir, "%s_%s_full.jpg" % (sid, lid.lower())), im, [cv2.IMWRITE_JPEG_QUALITY, 88])
        levels_out.append({"id": lid, "name": L["name"], "y": round(y, 1), "proposed": L["proposed"], "map": mp, "map_extent_m": round(2 * h_ * PX, 1),
                           "walls": outlines(dk.f), "doors": dk.doors,
                           "rooms": [{"name": r["name"], "x": round(r["at"][0], 1), "z": round(r["at"][1], 1), "rad": round(r["rad"] * 1.4, 1)} for r in dk.rooms],
                           "lifts": lifts, "ports": ports})
    rep["lifts"] = {"shafts_xz_m": dict(zip(("NE", "SE", "SW", "NW"), lifts)), "distance_from_axis_m": LIFT_R,
                    "serve": "all four shafts serve every deck" if all(all(rep[L["id"]]["lifts_on_walkable_floor"]) for L in sp["levels"]) else "NOT all shafts reach every deck"}
    main = next(L for L in sp["levels"] if L["id"] == sp.get("start_level", "L3"))
    out = {"id": sid, "name": sp["name"], "model": sp["model"], "system": sp["system"], "extent_m": N * PX,
           "start": {"level": main["id"], "x": lifts[2][0] + 30.0, "z": lifts[2][1]},
           "note": "Clean outline fitted to the exterior model. Districts follow the blueprint concept; room names are working labels. No combat, quests or key locks in this pass.",
           "levels": levels_out}
    json.dump(out, open(os.path.join(outdir, sid + ".json"), "w"), separators=(",", ":"))
    if repdir:
        json.dump(rep, open(os.path.join(repdir, sid + "_report.json"), "w"), indent=1)
        S = 0.25; W_ = 1200; H_ = 700
        im = np.zeros((H_, W_, 3), np.uint8); im[:] = (40, 16, 8)
        pts = np.stack([v[:, 0] * S + W_ / 2, -v[:, 1] * S + H_ / 2], 1)
        cv2.fillPoly(im, list(pts[np.asarray(mesh.faces)].round().astype(np.int32)), (120, 80, 40))
        for L, dk in decks:
            xs = np.nonzero(dk.f.any(axis=0))[0]; x0, x1 = (xs.min() - C) * PX, (xs.max() - C) * PX
            yv = int(-L["y"] * S + H_ / 2)
            cv2.line(im, (int(x0 * S + W_ / 2), yv), (int(x1 * S + W_ / 2), yv), (90, 255, 255) if not L["proposed"] else (90, 160, 255), 3)
            cv2.putText(im, "%s %s  %+d m" % (L["id"], L["name"], round(L["y"])), (20, yv + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1, cv2.LINE_AA)
        ys_ = [L["y"] for L in sp["levels"]]
        for a in LIFT_A:
            x = pol(LIFT_R, a)[0]
            cv2.line(im, (int(x * S + W_ / 2), int(-max(ys_) * S + H_ / 2)), (int(x * S + W_ / 2), int(-min(ys_) * S + H_ / 2)), (255, 255, 255), 1)
        cv2.putText(im, "SIDE VIEW (from the front): %s at game scale, deck floors and lift shafts" % sp["model"], (20, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 240, 170), 1, cv2.LINE_AA)
        cv2.imwrite(os.path.join(repdir, sid + "_side.jpg"), im, [cv2.IMWRITE_JPEG_QUALITY, 88])
    print(json.dumps({k: (v_ if not isinstance(v_, dict) or k in ("lifts", "arms") else {q: v_[q] for q in v_ if q in ("hull_inscribed_radius_m", "rooms", "doors", "rooms_dropped_unreachable", "lifts_on_walkable_floor", "one_door_rooms", "floor_outside_measured_hull_m2")}) for k, v_ in rep.items() if k not in ("main_deck_arms_built",)}, indent=0))

if __name__ == "__main__":
    build(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)
