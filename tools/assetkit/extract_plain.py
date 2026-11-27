"""extract_plain.py IN.glb OUTDIR : a plain (non-meshopt) one-primitive GLB -> pos/nrm/uv/idx .bin + tex0..2 (the decode.js layout)"""
import json, struct, sys, os, numpy as np
src, out = sys.argv[1], sys.argv[2].rstrip('/') + '/'
os.makedirs(out, exist_ok=True)
d = open(src, 'rb').read(); n = struct.unpack('<I', d[12:16])[0]; j = json.loads(d[20:20 + n]); b = d[20 + n + 8:]
def acc(i):
    a = j['accessors'][i]; bv = j['bufferViews'][a['bufferView']]; off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    comp = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]; dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a['componentType']]
    return np.frombuffer(b, dt, a['count'] * comp, off).reshape(-1, comp)
pr = j['meshes'][0]['primitives'][0]
acc(pr['attributes']['POSITION']).astype(np.float32).tofile(out + 'pos.bin')
nn = acc(pr['attributes']['NORMAL']).astype(np.float32)
q = np.zeros((len(nn), 4), np.int8); q[:, :3] = np.clip(np.round(nn * 127), -127, 127); q.tofile(out + 'nrm.bin')
acc(pr['attributes']['TEXCOORD_0']).astype(np.float32).tofile(out + 'uv.bin')
acc(pr['indices']).astype(np.uint32).tofile(out + 'idx.bin')
for k, im in enumerate(j['images']):
    bv = j['bufferViews'][im['bufferView']]; o = bv.get('byteOffset', 0)
    open(out + 'tex%d%s' % (k, '.png' if im['mimeType'] == 'image/png' else '.jpg'), 'wb').write(b[o:o + bv['byteLength']])
print(src, 'ok')
