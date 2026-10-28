"""tools/handoff/analyze.py -- builds the asset handoff from COPIES (the originals are only read).
usage: python3 tools/handoff/analyze.py <game_dump.json> <drive_originals.csv> <out_dir>"""
import sys, os, json, struct, shutil, csv, re, glob, subprocess
import numpy as np
DUMP, DRIVE, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
G = json.load(open(DUMP))
os.makedirs(OUT, exist_ok=True)

def glb_read(path):
    b = open(path, 'rb').read()
    if b[:4] != b'glTF': return None, None
    off = 12; js = None; binc = b''
    while off < len(b):
        ln, typ = struct.unpack('<I4s', b[off:off+8]); chunk = b[off+8:off+8+ln]; off += 8 + ln
        if typ == b'JSON': js = json.loads(chunk)
        elif typ == b'BIN\x00': binc = chunk
    return js, binc

def mat4(n):
    if 'matrix' in n: return np.array(n['matrix'], float).reshape(4, 4).T
    t = np.eye(4); t[:3, 3] = n.get('translation', [0, 0, 0])
    x, y, z, w = n.get('rotation', [0, 0, 0, 1])
    r = np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)], [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)], [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])
    s = np.diag(n.get('scale', [1, 1, 1]))
    m = np.eye(4); m[:3, :3] = r @ s
    return t @ m

def analyze(path):
    js, binc = glb_read(path)
    if js is None: return None
    nodes = js.get('nodes', []); meshes = js.get('meshes', []); acc = js.get('accessors', [])
    tris = 0; lo = np.full(3, np.inf); hi = np.full(3, -np.inf)
    children = {c for n in nodes for c in n.get('children', [])}
    roots = js.get('scenes', [{}])[js.get('scene', 0)].get('nodes', [i for i in range(len(nodes)) if i not in children]) if js.get('scenes') else [i for i in range(len(nodes)) if i not in children]
    def walk(i, M):
        nonlocal tris, lo, hi
        n = nodes[i]; W = M @ mat4(n)
        if 'mesh' in n:
            for pr in meshes[n['mesh']].get('primitives', []):
                pa = acc[pr['attributes']['POSITION']]
                if 'indices' in pr: tris += acc[pr['indices']]['count'] // 3
                else: tris += pa['count'] // 3
                if 'min' in pa and 'max' in pa:
                    mn, mx = pa['min'], pa['max']
                    for cx in (mn[0], mx[0]):
                        for cy in (mn[1], mx[1]):
                            for cz in (mn[2], mx[2]):
                                p = W @ np.array([cx, cy, cz, 1.0])
                                lo = np.minimum(lo, p[:3]); hi = np.maximum(hi, p[:3])
        for c in n.get('children', []): walk(c, W)
    for r in roots: walk(r, np.eye(4))
    maps = []
    for mi, m in enumerate(js.get('materials', [])):
        pbr = m.get('pbrMetallicRoughness', {})
        mm = {'material': m.get('name', 'mat%d' % mi),
              'base_color': 'baseColorTexture' in pbr, 'metallic_roughness': 'metallicRoughnessTexture' in pbr,
              'normal': 'normalTexture' in m, 'occlusion': 'occlusionTexture' in m, 'emissive': 'emissiveTexture' in m,
              'base_color_factor': pbr.get('baseColorFactor'), 'metallic_factor': pbr.get('metallicFactor'), 'roughness_factor': pbr.get('roughnessFactor'),
              'tex': {}}
        for key, ref in [('base_color', pbr.get('baseColorTexture')), ('metallic_roughness', pbr.get('metallicRoughnessTexture')), ('normal', m.get('normalTexture')), ('occlusion', m.get('occlusionTexture')), ('emissive', m.get('emissiveTexture'))]:
            if ref is not None:
                t = js['textures'][ref['index']]; mm['tex'][key] = t.get('source')
        maps.append(mm)
    names = [n.get('name', '') for n in nodes]
    return {'js': js, 'bin': binc, 'tris': int(tris), 'bbox_min': [round(float(v), 4) for v in lo] if np.isfinite(lo).all() else None,
            'bbox_max': [round(float(v), 4) for v in hi] if np.isfinite(hi).all() else None, 'materials': maps, 'node_names': names,
            'skins': len(js.get('skins', [])), 'animations': [a.get('name', '') for a in js.get('animations', [])],
            'images': len(js.get('images', [])), 'meshes': len(meshes), 'external_images': [im.get('uri') for im in js.get('images', []) if 'uri' in im],
            'generator': js.get('asset', {}).get('generator', '')}

def extract_images(info, dst, prefix):
    js, binc = info['js'], info['bin']; out = {}
    os.makedirs(dst, exist_ok=True)
    for i, im in enumerate(js.get('images', [])):
        if 'bufferView' not in im: continue
        bv = js['bufferViews'][im['bufferView']]; data = binc[bv.get('byteOffset', 0): bv.get('byteOffset', 0) + bv['byteLength']]
        ext = {'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/ktx2': 'ktx2'}.get(im.get('mimeType', ''), 'bin')
        roles = [k for m in info['materials'] for k, v in m['tex'].items() if v == i]
        fn = '%s_img%02d_%s.%s' % (prefix, i, '+'.join(sorted(set(roles))) or 'unused', ext)
        open(os.path.join(dst, fn), 'wb').write(data); out[i] = fn
    return out

# ---- the game's use of each model key
uses = {}
for sid, s in G['ships'].items(): uses.setdefault(s.get('model',''), []).append('player ship: %s (%s)' % (s['name'], sid))
for eid, e in G['enemies'].items(): uses.setdefault(e.get('model','enemy'), []).append('enemy: %s (%s)%s' % (e['name'], eid, (' faction ' + e['faction']) if e.get('faction') else ''))
for mid, m in G['mechs'].items(): uses.setdefault(m.get('model',''), []).append('mech frame: %s (%s)' % (m['name'], mid))
code = ''
for f in glob.glob('scripts/*.gd'):
    if f.endswith(('ships.gd', 'autotest.gd', 'room_people.gd')): continue
    code += open(f).read()
station_keys = {}
for sid, s in G['systems'].items():
    for st in [s.get('station', {})] + list(s.get('more_stations', []) or []):
        if isinstance(st, dict) and st.get('model'): station_keys.setdefault(st['model'], []).append('%s (%s, %s)' % (st.get('name', '?'), s.get('name', sid), s.get('faction', '')))

FACTIONS = ['Savagers', 'Liberator', 'Unity', 'Imperium', 'Elyza', 'Covenant', 'Solarion', 'Orion', 'Cybermorph', 'Solrath', 'Gadversee', 'Arctides', 'Phenom', 'Kaijurai']
def faction_of(key, path, use):
    if '/wing_guns/' in path or '/weapons/' in path: return 'shared equipment (any faction)'
    if '/cargo/' in path: return 'shared prop'
    if 'mecha' in key and 'rigged' in key: return 'Player mech frame (rig source)'
    for u in use:
        m = re.search(r'\(([^,()]+), (\w+)\)$', u)
        if m and m.group(2) not in ('',): return m.group(2) + ' (from the system it sits in)'
    for u in use:
        m = re.search(r'faction (\w+)', u)
        if m: return m.group(1)
    low = (key + ' ' + path).lower()
    for f in FACTIONS:
        if f.lower().rstrip('s') in low: return f
    if 'savager' in low or key in ('enemy', 'enemy2'): return 'Savagers'
    if key in ('cadet', 'ranger', 'lancer', 'bulk', 'bulk_empty', 'hauler'): return 'Player (any)'
    if key.startswith(('fleet', 'tanker', 'carrier')): return 'Civilian traffic'
    if key.startswith(('mech', 'mf_')): return 'Player mech frame'
    return 'unknown'

records = []
def add(category, key, path, used, use_notes, length=None, yaw=None, source=None):
    records.append({'category': category, 'key': key, 'path': path, 'used': used, 'use_notes': use_notes, 'length': length, 'yaw': yaw, 'source': source})

table = G['glb_table']
for key, v in table.items():
    path = v[0].replace('res://', ''); cat = 'ship'
    if '/wing_guns/' in path or '/weapons/' in path: cat = 'equipment'
    elif '/mech' in path: cat = 'mech'
    elif '/stations/' in path: cat = 'station'
    elif '/cargo/' in path: cat = 'prop'
    use = uses.get(key, [])
    used = bool(use) or ('"%s"' % key) in code
    if not use and used: use = ['referenced in game code']
    add(cat, key, path, used, use, v[1], v[2])
for p in sorted(glob.glob('assets/stations3d/*.glb')):
    if '_lod' in p: continue
    k = os.path.splitext(os.path.basename(p))[0]
    use = station_keys.get(k, [])
    used = bool(use) or ('"%s"' % k) in code
    add('station', k, p, used, use or (['referenced in game code'] if used else []))
for p in sorted(glob.glob('assets/structures/*.glb')):
    k = os.path.splitext(os.path.basename(p))[0]; used = ('"%s"' % k) in code or os.path.basename(p) in code
    add('station', k, p, used, ['referenced in game code'] if used else [])
for p in sorted(glob.glob('art/stations3d/*.glb')):
    if '_lod' in p: continue
    add('station', os.path.splitext(os.path.basename(p))[0], p, False, ['not in the game build (art/ only)'])
for p in sorted(glob.glob('art/characters/*mecha*_rigged*.glb')):
    add('mech', os.path.splitext(os.path.basename(p))[0], p, False, ['rigged source of a game mech frame (the game uses the baked .scn)'])
for p in sorted(glob.glob('art/ships/**/*.glb', recursive=True)) + sorted(glob.glob('art/models/*.glb')):
    add('ship' if 'ships' in p else 'prop', os.path.splitext(os.path.basename(p))[0], p, False, ['art/ only, not loaded by the game'])

# ---- analyse, copy, extract
inv_rows = []; tex_rows = []; spec_rows = []
for r in records:
    p = r['path']; ext = os.path.splitext(p)[1].lower()
    fac = faction_of(r['key'], p, r['use_notes'])
    dst = os.path.join(OUT, '02_models', r['category'] + 's', r['key'])
    os.makedirs(dst, exist_ok=True)
    row = {'model': r['key'], 'category': r['category'], 'faction': fac, 'file_path': p, 'format': ext[1:] if ext else '?', 'exists': os.path.exists(p),
           'used_in_game': 'yes' if r['used'] else 'no', 'used_by': '; '.join(r['use_notes'])[:400]}
    meta = dict(row)
    if not os.path.exists(p):
        row['notes'] = 'FILE MISSING'; inv_rows.append(row); continue
    shutil.copy2(p, dst)
    for side in glob.glob(os.path.splitext(p)[0] + '_*.jpg') + glob.glob(os.path.splitext(p)[0] + '_*.png'):   # textures Godot pulled out next to the file
        shutil.copy2(side, os.path.join(dst, 'textures_external')) if os.path.isdir(os.path.join(dst, 'textures_external')) else (os.makedirs(os.path.join(dst, 'textures_external')), shutil.copy2(side, os.path.join(dst, 'textures_external')))
    if ext == '.glb':
        info = analyze(p)
        if info:
            imgs = extract_images(info, os.path.join(dst, 'textures'), r['key'])
            size = [round(info['bbox_max'][i] - info['bbox_min'][i], 3) for i in range(3)] if info['bbox_min'] else None
            meta.update({'triangles': info['tris'], 'meshes': info['meshes'], 'materials': len(info['materials']), 'images_embedded': len(imgs),
                         'external_images': info['external_images'], 'skins': info['skins'], 'animations': info['animations'], 'node_names': info['node_names'][:80],
                         'file_bbox_min': info['bbox_min'], 'file_bbox_max': info['bbox_max'], 'file_size_xyz': size, 'generator': info['generator']})
            row.update({'triangles': info['tris'], 'file_size_x': size[0] if size else '', 'file_size_y': size[1] if size else '', 'file_size_z': size[2] if size else ''})
            for m in info['materials']:
                miss = [k for k in ['base_color', 'normal', 'metallic_roughness', 'occlusion', 'emissive'] if not m[k]]
                tex_rows.append({'model': r['key'], 'material': m['material'], 'base_color': m['base_color'], 'normal': m['normal'], 'roughness_metallic (glTF ORM, roughness=G metallic=B)': m['metallic_roughness'],
                                 'ambient_occlusion': m['occlusion'], 'emissive': m['emissive'], 'missing_maps': ', '.join(miss), 'base_color_factor': m['base_color_factor'], 'metallic_factor': m['metallic_factor'], 'roughness_factor': m['roughness_factor']})
            if not info['materials']: tex_rows.append({'model': r['key'], 'material': '(none)', 'missing_maps': 'all: no material'})
    # scale / axes / pivot
    L = r['length']; yaw = r['yaw']
    sz = meta.get('file_size_xyz')
    longest = max(sz) if sz else None
    spec = {'model': r['key'], 'category': r['category'],
            'units': 'metres (glTF 1 unit = 1 m); the game scales each model so its longest side = the length below' if r['category'] != 'station' or L else 'metres; scale set where the station is placed (see code)',
            'game_length_m': L if L is not None else 'unknown (not in the model table)',
            'file_longest_side': longest,
            'game_scale_factor': round(float(L) / longest, 4) if (L and longest) else 'unknown',
            'up_axis': '+Y (glTF)', 'forward_axis_in_game': 'nose at -Z after the yaw below (Godot / game convention)' if r['category'] in ('ship', 'mech') else 'not defined for stations',
            'yaw_correction_deg': yaw if yaw is not None else 'unknown',
            'pivot': ('file origin ' + ('at centre of bounds' if sz and meta.get('file_bbox_min') and all(abs(meta['file_bbox_min'][i] + meta['file_bbox_max'][i]) < 0.02 * max(sz) for i in range(3)) else 'NOT at the bounds centre (game re-centres it)')) if sz else 'unknown'}
    spec_rows.append(spec); meta['spec'] = spec
    json.dump(meta, open(os.path.join(dst, 'meta.json'), 'w'), indent=2)
    inv_rows.append(row)

def wcsv(path, rows):
    if not rows: return
    keys = []
    for r in rows:
        for k in r:
            if k not in keys: keys.append(k)
    with open(path, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=keys); w.writeheader(); [w.writerow(r) for r in rows]
os.makedirs(os.path.join(OUT, '01_inventory'), exist_ok=True)
wcsv(os.path.join(OUT, '01_inventory', 'inventory.csv'), inv_rows)
shutil.copy2(DRIVE, os.path.join(OUT, '01_inventory', 'drive_originals_tripo_exports.csv'))
os.makedirs(os.path.join(OUT, '04_textures'), exist_ok=True)
wcsv(os.path.join(OUT, '04_textures', 'texture_maps_by_material.csv'), tex_rows)
os.makedirs(os.path.join(OUT, '05_scale_axes_pivots_mounts'), exist_ok=True)
wcsv(os.path.join(OUT, '05_scale_axes_pivots_mounts', 'scale_axes_pivots.csv'), spec_rows)
json.dump({'records': len(records), 'inventory': len(inv_rows)}, open(os.path.join(OUT, 'counts.json'), 'w'))
print(len(records), 'models;', sum(1 for r in inv_rows if r['used_in_game'] == 'yes'), 'used in game')
