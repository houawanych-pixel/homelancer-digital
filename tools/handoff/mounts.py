"""Per-ship / per-mech mount points in game metres, from the rendered bounds (after the game yaw) and the game's mount rules.
usage: python3 mounts.py <views.json> <game_dump.json> <inventory.csv> <out_dir>"""
import sys, json, csv, os, glob
V = json.load(open(sys.argv[1])); G = json.load(open(sys.argv[2])); INV = {r['model']: r for r in csv.DictReader(open(sys.argv[3]))}; OUT = sys.argv[4]
C = G['constants']; T = G['glb_table']
rows = []
for key, m in V.items():
    r = INV.get(key, {})
    if r.get('category') not in ('ship',): continue
    L = T.get(key, [None, None])[1]
    sx, sy, sz = m['size']; longest = max(m['size'])
    if not L: rows.append({'model': key, 'note': 'no game length in the model table: mounts unknown'}); continue
    k = L / longest; hw = sx * k / 2; ln = sz * k; hh = sy * k / 2
    base = {'model': key, 'game_length_m': L, 'game_width_m': round(sx * k, 2), 'game_height_m': round(sy * k, 2), 'game_length_z_m': round(ln, 2), 'scale_file_to_game': round(k, 4)}
    pts = [('front gun (-1)', 0.0, -C['MOUNT_DROP'] * 1.4, -ln * 0.3), ('front gun 2 (-5, when 2 core guns)', hw * 0.14, -C['MOUNT_DROP'] * 1.4, -ln * 0.3), ('belly gun (-6)', 0.0, -C['MOUNT_DROP'] * 2.4, -ln * 0.05)]
    for side, nm in ((-1, 'left'), (1, 'right')):
        pts += [('%s shoulder mount (top)' % nm, side * hw * C['MOUNT_SHOULDER_AT'], C['MOUNT_DROP'], 0.0),
                ('%s mid mount (top, level 3)' % nm, side * hw * C['MOUNT_MID_AT'], C['MOUNT_DROP'], 0.0),
                ('%s tip mount (underneath)' % nm, side * hw * C['MOUNT_TIP_AT'], -C['MOUNT_DROP'], 0.0)]
    for nm, x, y, z in pts:
        rows.append(dict(base, mount=nm, x_m=round(x, 3), y_m=round(y, 3), z_m=round(z, 3), source='rule in scripts/hub.gd + Data.MOUNT_* (game convention: origin = bounds centre, nose -Z, +X = ship right)'))
keys = []
for r in rows:
    for k_ in r:
        if k_ not in keys: keys.append(k_)
with open(os.path.join(OUT, 'ship_mount_points_game_metres.csv'), 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=keys); w.writeheader(); [w.writerow(r) for r in rows]
os.makedirs(os.path.join(OUT, 'mech_joints'), exist_ok=True)
for j in glob.glob('art/characters/*_joints.json'):
    import shutil; shutil.copy2(j, os.path.join(OUT, 'mech_joints'))
print(len(rows), 'mount rows')
