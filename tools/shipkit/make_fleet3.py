#!/usr/bin/env python3
"""Build the three player ships from the owner's sheet of 3 ships + loose weapons (3 Oct 2026), weapons mounted.
  python3 tools/shipkit/make_fleet3.py SHEET.glb OUTDIR      (then decimate + repack: see make_fleet3.sh)
Sheet pieces (shipkit inspect --pieces --min-frac 0.002): 4 and 8 = the two smaller ships, 6 = the big ship with loose
parts 0,3 (nose pods) 1,2 (rods) 5,7 (brackets); 9 = long cannon, 10 = short cannon, 11 = round pod (kept as a spare).
Everything shares one material, so mounted weapons are simply merged into the ship mesh.
  starter: two short cannons side by side on top
  patrol:  one long cannon on top, a short cannon on each wing
  heavy:   a long cannon on each wing; a short cannon each side of the nose, joining the loose pod to the hull"""
import json, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import shipkit as sk

def rot_y(ang):
    c, s = np.cos(ang), np.sin(ang)
    return np.array([[c, 0, -s], [0, 1, 0], [s, 0, c]])

def take(g, tcl, ids):
    tri = g["tri"][np.isin(tcl, ids)]
    return sk.compact(g["pos"], g["nrm"], g["uv"], tri)

def canon_weapon(pos, nrm):
    """Long axis along Z, the thin (barrel) end pointing -Z (forward), centred."""
    c = pos - pos.mean(0)
    w, v = np.linalg.eigh(c.T @ c)
    z = v[:, 2]
    if abs(z[1]) > 0.9: z = v[:, 1]
    z = z / np.linalg.norm(z)
    up = np.array([0, 1.0, 0]); x = np.cross(up, z); x /= np.linalg.norm(x); y = np.cross(z, x)
    R = np.stack([x, y, z])
    p = c @ R.T; n = nrm @ R.T
    L = np.ptp(p[:, 2])
    ends = [np.prod(np.ptp(p[(p[:, 2] * s) > (L / 2 - 0.2 * L) + (0 if s > 0 else 0)][:, :2], axis=0)) for s in (1, -1)]
    if ends[1] > ends[0]:      # the -Z end is the fat one: turn it round
        F = np.diag([-1.0, 1.0, -1.0]); p = p @ F.T; n = n @ F.T
    p = p - (p.min(0) + p.max(0)) / 2
    return p, n

def top_at(ship, nrm, x, z, r):
    """Height of the upward-facing skin near (x, z): the middle of it, so a thin fin nearby does not lift the mount."""
    d = np.hypot(ship[:, 0] - x, ship[:, 2] - z)
    near = (d < r) & (nrm[:, 1] > 0.5)
    if near.sum() < 8: near = d < r * 2
    return float(np.percentile(ship[near, 1], 60)) if near.any() else float(np.median(ship[:, 1]))

def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    g, js, binc = sk.load_geometry(src)
    tcl, info = sk.piece_clusters(g, 0.002)
    assert len(info) == 12, "sheet pieces changed: %d" % len(info)
    weapons = {}
    for name, i in (("long", 9), ("short", 10), ("pod", 11)):
        p, n, u, t = take(g, tcl, [i]); p, n = canon_weapon(p, n); weapons[name] = (p, n, u, t)
    mats, images, mat_map = sk.remap_materials(js, binc, [0], 512)
    report = {}
    for ship, ids, yaw_fit, flip in (("starter", [4], True, False), ("patrol", [8], True, False), ("heavy", [6, 0, 1, 2, 3, 5, 7], False, True)):   # nose (pointed end) must come out at -Z, the way the cannons point.
    # v1.4l: starter and patrol were built tail-first (flip was True), so their cannons pointed backwards.
        p, n, u, t = take(g, tcl, ids)
        marks = np.array([g["pos"][np.unique(g["tri"][tcl == k])].mean(0) for k in (0, 1, 2, 3)]) if ship == "heavy" else np.zeros((0, 3))
        if yaw_fit:
            c = p[:, [0, 2]] - p[:, [0, 2]].mean(0)
            w, v = np.linalg.eigh(c.T @ c)
            R = rot_y(np.arctan2(v[0, 1], v[1, 1]))
            p = p @ R.T; n = n @ R.T
        allp, alln, rep = sk.orient(np.concatenate([p, marks]), np.concatenate([n, np.zeros_like(marks)]), flip, "z")
        p, n, marks = allp[:len(p)], alln[:len(n)], allp[len(p):]
        hx, hz = np.ptp(p[:, 0]) / 2, np.ptp(p[:, 2]) / 2
        L = hz * 2
        parts = [(p, n, u, t)]
        def mount(kind, x, z, length_frac, y=None, sink=0.3):
            wp, wn, wu, wt = weapons[kind]
            s = (L * length_frac) / np.ptp(wp[:, 2])
            q = wp * s
            if y is None: y = top_at(p, n, x, z, np.ptp(q[:, 0]) * 0.6) + np.ptp(q[:, 1]) * (0.5 - sink)
            parts.append((q + np.array([x, y, z]), wn, wu, wt))
        if ship == "starter":
            for sx in (-1, 1): mount("short", sx * hx * 0.2, hz * 0.05, 0.24)
        elif ship == "patrol":
            mount("long", 0.0, hz * 0.1, 0.34)
            for sx in (-1, 1): mount("short", sx * hx * 0.5, hz * 0.2, 0.22)
        else:
            for sx in (-1, 1): mount("long", sx * hx * 0.55, hz * 0.25, 0.3)
            for a, b in ((0, 1), (3, 2)):       # pod + rod on each side of the nose: a cannon between them joins them
                m = (marks[a] + marks[b]) / 2
                mount("short", m[0], m[2], 0.2, y=m[1])
        P = np.concatenate([x[0] for x in parts]); N = np.concatenate([x[1] for x in parts]); U = np.concatenate([x[2] for x in parts])
        off = np.cumsum([0] + [len(x[0]) for x in parts[:-1]])
        T = np.concatenate([x[3] + o for x, o in zip(parts, off)])
        P = P - (P.min(0) + P.max(0)) / 2
        sk.write_glb(os.path.join(out, ship + "_full.glb"), [(P, N, U, T, mat_map.get(0, -1))], mats, images, ship)
        tt = T if len(T) <= 70000 else T[np.random.default_rng(0).choice(len(T), 70000, replace=False)]
        sk.sheet([sk.render(P, tt, v, 520, title="%s %s" % (ship, v)) for v in ("top", "side", "persp")], os.path.join(out, ship + "_preview.png"))
        report[ship] = {"tris": int(len(T)), "size": np.ptp(P, axis=0).round(3).tolist(), "nose": rep}
    for name in ("long", "short", "pod"):
        wp, wn, wu, wt = weapons[name]
        sk.write_glb(os.path.join(out, "weapon_%s_full.glb" % name), [(wp, wn, wu, wt, mat_map.get(0, -1))], mats, images, "weapon_" + name)
    print(json.dumps(report))

if __name__ == "__main__":
    main()
