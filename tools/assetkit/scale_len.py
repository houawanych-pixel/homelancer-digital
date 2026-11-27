"""scale_len.py IN OUT LEN : uniform scale so the length along Z is LEN metres (POSITION accessor only)"""
import json, struct, sys, numpy as np
src, dst, L = sys.argv[1], sys.argv[2], float(sys.argv[3])
d = bytearray(open(src, 'rb').read()); n = struct.unpack('<I', d[12:16])[0]; j = json.loads(d[20:20 + n]); b0 = 20 + n + 8
for m in j['meshes']:
    for pr in m['primitives']:
        a = j['accessors'][pr['attributes']['POSITION']]; bv = j['bufferViews'][a['bufferView']]
        off = b0 + bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        p = np.frombuffer(bytes(d[off:off + a['count'] * 12]), np.float32).reshape(-1, 3)
        k = L / (p[:, 2].max() - p[:, 2].min()); p = (p * k).astype(np.float32)
        d[off:off + a['count'] * 12] = p.tobytes(); a['min'] = [float(x) for x in p.min(0)]; a['max'] = [float(x) for x in p.max(0)]
js = json.dumps(j, separators=(',', ':')).encode()
while len(js) % 4: js += b' '
binc = bytes(d[20 + n:])
out = b'glTF' + struct.pack('<II', 2, 12 + 8 + len(js) + len(binc)) + struct.pack('<I', len(js)) + b'JSON' + js + binc
open(dst, 'wb').write(out); print(dst, '%.0f m' % L)
