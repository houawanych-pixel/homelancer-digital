"""Space map layouts from the game's own data dump: every placement, sizes and distance to the tile border.
usage: python3 maps.py <game_dump.json> <out_dir>"""
import sys, os, json, csv, math, re
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
G = json.load(open(sys.argv[1])); OUT = sys.argv[2]; os.makedirs(OUT + '/system_layouts', exist_ok=True)
EDGE = G['constants']['SPACE_EDGE']; SW = 170.0
ST3D = {"st3d_aurelion_citadel": 1.6, "st3d_veranthos_senate": 1.6}; RET = {"Capital": 1.6, "Military": 1.15, "Trade": 1.3, "Outpost": 0.9}
OLD = {"savagers_cross_station": 1.45, "worlds_end_emporium": 1.6, "hollow_requiem": 2.2}
def st_width(model):
    if not model: return SW
    if model in ST3D: return SW * ST3D[model]
    if model in OLD: return SW * OLD[model]
    for k, v in RET.items():
        if model.startswith('HL_Station_') and '_%s_' % k in model: return SW * v
    return SW
rows = []
def P(p): return (p['x'], p['y'], p['z']) if isinstance(p, dict) else (None, None, None)
for sid, s in G['systems'].items():
    base = {'system_id': sid, 'system': s['name'], 'board_tile': s.get('tile', ''), 'faction': s.get('faction', ''), 'role': s.get('role', '')}
    def add(kind, name, pos, size, model='', note=''):
        x, y, z = P(pos)
        if x is None: return
        r = size or 0
        rows.append(dict(base, kind=kind, name=name, model=model, x=round(x, 1), y=round(y, 1), z=round(z, 1), size_m=round(size, 1) if size else '',
                         dist_from_centre_m=round(math.hypot(x, z), 1), margin_to_tile_border_m=round(EDGE - max(abs(x), abs(z)) - r, 1), note=note))
    for i, st in enumerate([s['station']] + list(s.get('more_stations') or [])):
        if isinstance(st, dict):
            m = st.get('model', ''); add('station', st.get('name', ''), st.get('pos', {'x': 0, 'y': 0, 'z': 0}), st_width(m), m, 'size = model width (170 m x style scale); main station' if i == 0 else 'size = model width')
    for pl in [s['planet']] + list(s.get('more_planets') or []):
        if isinstance(pl, dict): add('planet', pl.get('name', ''), pl.get('pos'), 2 * float(pl.get('radius', 0)), '', 'size = diameter (fly-in sphere)')
    for g in s.get('gates', []): add(g.get('gkind', 'jump') + '_gate', g.get('name', ''), g.get('pos'), 104.0 if g.get('gkind') != 'warp' else 110.0, '', 'to ' + g.get('to', '') + '; ring outer diameter 104 m (code-made stand-in)')
    a = s.get('asteroids') or {}
    if a.get('center'): add('asteroid_field', a.get('name', ''), a['center'], 2 * a.get('radius', 0), '', '%s rocks; size = diameter' % a.get('count', ''))
    n = s.get('nebula') or {}
    if n.get('center'): add('nebula', n.get('name', ''), n['center'], 2 * n.get('radius', 0), '', 'size = diameter')
    for i, p in enumerate(s.get('patrols') or []): add('patrol_point', 'patrol %d' % (i + 1), p, 0)
keys = list(rows[0].keys())
with open(OUT + '/space_placements_all_systems.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=keys); w.writeheader(); [w.writerow(r) for r in rows]
# per-system top-down plot (zoomed to the content, the 500 km border noted)
col = {'station': '#ffcc33', 'planet': '#55aaff', 'jump_gate': '#66ff99', 'warp_gate': '#cc66ff', 'rift_gate': '#ff5577', 'asteroid_field': '#aa8866', 'nebula': '#88aaff', 'patrol_point': '#ff6644'}
by = {}
for r in rows: by.setdefault(r['system_id'], []).append(r)
for sid, rs in by.items():
    fig, ax = plt.subplots(figsize=(9, 9), dpi=110); fig.patch.set_facecolor('#15171b'); ax.set_facecolor('#1c1f24')
    ext = max(max(abs(r['x']), abs(r['z'])) + (r['size_m'] or 0) / 2 for r in rs) * 1.15
    for r in rs:
        c = col.get(r['kind'], '#ffffff')
        if r['size_m'] and r['kind'] in ('planet', 'asteroid_field', 'nebula', 'station'):
            ax.add_patch(plt.Circle((r['x'], r['z']), r['size_m'] / 2, color=c, alpha=0.35 if r['kind'] != 'station' else 0.9, fill=True))
        ax.plot(r['x'], r['z'], 'o' if r['kind'] != 'patrol_point' else 'x', color=c, ms=5)
        if r['kind'] != 'patrol_point': ax.annotate(r['name'], (r['x'], r['z']), color='#e8e8e8', fontsize=7, xytext=(4, 4), textcoords='offset points')
    ax.set_xlim(-ext, ext); ax.set_ylim(ext, -ext); ax.set_aspect('equal')
    ax.tick_params(colors='#aaaaaa', labelsize=7); ax.grid(color='#33373d', lw=0.5)
    ax.set_xlabel('x (m)', color='#aaa'); ax.set_ylabel('z (m)  -- north (-Z) is up', color='#aaa')
    s = G['systems'][sid]
    ax.set_title('%s  [%s]  %s  -- everything here sits within %.0f m of the centre; tile border at +/- %d m (%.1f%% of the tile used)' % (s['name'], s.get('tile', ''), s.get('faction', ''), ext / 1.15, EDGE, 100 * ext / 1.15 / EDGE), color='#eee', fontsize=8)
    fig.savefig(OUT + '/system_layouts/%s_%s.png' % (s.get('tile', ''), sid), facecolor=fig.get_facecolor()); plt.close(fig)
# board
gd = open('scripts/galaxy_data.gd').read()
tiles = re.findall(r'\["(\w+)", "([^"]*)", "([A-K]\d+)", (\d+), (\d+), "([^"]*)", "([^"]*)"', gd)
with open(OUT + '/galaxy_board_11x11.csv', 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['system_id', 'name', 'tile', 'col', 'row', 'faction', 'note'])
    for t in tiles: w.writerow(t)
surf = G['surface']
with open(OUT + '/planet_surface_tiles.csv', 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['planet_id', 'name', 'system', 'grid (tiles per side)', 'tile types', 'locations'])
    for pid, p in surf['planets'].items(): w.writerow([pid, p.get('name'), p.get('system'), p.get('grid'), ' '.join(p.get('tiles', [])), len(p.get('locations', []))])
json.dump({'SPACE_EDGE_m': EDGE, 'space_tile_m': 2 * EDGE, 'board': '11 x 11 (columns A-K, rows 1-11), wraps at the edges', 'surface_TILE_m': surf['TILE'], 'surface_EDGE_m': surf['EDGE'],
           'station_width_m': SW, 'station_style_scale': RET, 'station_model_scale': {**ST3D, **OLD}, 'gate_ring': 'inner 44 m / outer 52 m radius (code-made), collision radius 55 m',
           'docking_ring_radius_m': 26, 'system_spread': 1.8}, open(OUT + '/boundaries_and_sizes.json', 'w'), indent=2)
print(len(rows), 'placements;', len(by), 'systems;', len(tiles), 'board tiles')
