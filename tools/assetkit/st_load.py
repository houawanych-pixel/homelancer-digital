"""Load an original station GLB: welded positions, triangles, per-corner UV, the colour texture, connected pieces."""
import sys, json, struct, io
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import numpy as np
from rsg import read_simple_glb
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from PIL import Image
Image.MAX_IMAGE_PIXELS = None

def texture(path):
    d = open(path, 'rb').read(); n = struct.unpack('<I', d[12:16])[0]; js = json.loads(d[20:20 + n]); b = d[20 + n + 8:]
    im = js['images'][0]; bv = js['bufferViews'][im['bufferView']]; o = bv.get('byteOffset', 0)
    return Image.open(io.BytesIO(b[o:o + bv['byteLength']])).convert('RGB')

def load(path):
    P, N, U, I = read_simple_glb(path)
    q = np.round(P.astype(np.float64) * 200000).astype(np.int64)
    _, first, inv = np.unique(q, axis=0, return_index=True, return_inverse=True); inv = inv.ravel()
    W = P[first].astype(np.float64)            # welded positions
    T = inv[I]                                  # triangles on welded verts
    CU = U[I]                                   # per-corner UV (n, 3, 2)
    CN = N[I]
    a = np.concatenate([T[:, 0], T[:, 1]]); b = np.concatenate([T[:, 1], T[:, 2]])
    nc, lab = connected_components(coo_matrix((np.ones(len(a), np.int8), (a, b)), shape=(len(W), len(W))), directed=False)
    tl = lab[T[:, 0]]
    return W, T, CU, CN, tl, nc
