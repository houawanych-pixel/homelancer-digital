"""split.py DIR [min_tris] : connected pieces of DIR/raw, biggest first -> DIR/tri_lab.npy, DIR/comps.json, DIR/prev/cNN.glb"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import io, json, glob, numpy as np
from glbio import load_raw, write_glb
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from PIL import Image
Image.MAX_IMAGE_PIXELS=None
D=sys.argv[1].rstrip('/')+'/'; MIN=int(sys.argv[2]) if len(sys.argv)>2 else 3000
def _tex(i): return sorted(glob.glob(D+'raw/tex%d.*'%i))[0]
pos,nrm,uv,idx=load_raw(D+'raw/')
# weld by position first: vertices are split at UV seams, so raw indices would shatter every object
q=np.round(pos*20000).astype(np.int64); _,inv=np.unique(q,axis=0,return_inverse=True); inv=inv.ravel()
t=inv[idx]; n=inv.max()+1
a=np.concatenate([t[:,0],t[:,1]]); b=np.concatenate([t[:,1],t[:,2]])
nc,lab=connected_components(coo_matrix((np.ones(len(a),np.int8),(a,b)),shape=(n,n)),directed=False)
tl=lab[t[:,0]]; cnt=np.bincount(tl,minlength=nc); order=np.argsort(-cnt)
remap=np.full(nc,-1); k=0; info=[]
for c in order:
    if cnt[c]<MIN: continue
    remap[c]=k; m=tl==c; v=pos[np.unique(idx[m])]
    info.append({"c":k,"tris":int(cnt[c]),"min":[round(float(x),3) for x in v.min(0)],"max":[round(float(x),3) for x in v.max(0)]}); k+=1
tl2=remap[tl]; np.save(D+'tri_lab.npy',tl2); json.dump(info,open(D+'comps.json','w'))
print(nc,'pieces,',k,'kept; dropped tris',int((tl2<0).sum()))
for i in info: print(i)
im=Image.open(_tex(0)).convert('RGB'); bb=io.BytesIO(); im.resize((2048,2048)).save(bb,'JPEG',quality=85)
mat={"name":"hull","pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0.3,"roughnessFactor":0.7}}
os.makedirs(D+'prev',exist_ok=True)
for c in range(k):
    f=idx[tl2==c]; u,iv=np.unique(f,return_inverse=True)
    write_glb(D+'prev/c%02d.glb'%c,[{"pos":pos[u],"nrm":nrm[u],"uv":uv[u],"idx":iv.reshape(-1,3),"mat":0}],[mat],[(bb.getvalue(),'image/jpeg')],'c%02d'%c)
