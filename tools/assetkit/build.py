import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import io, json, glob, subprocess, numpy as np
from glbio import load_raw, write_glb
from rsg import read_simple_glb
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from PIL import Image
Image.MAX_IMAGE_PIXELS=None
D=sys.argv[1].rstrip('/')+'/'; os.makedirs(D+'out',exist_ok=True); os.makedirs(D+'tmp',exist_ok=True)
def _tex(i): return sorted(glob.glob(D+'raw/tex%d.*'%i))[0]
G=os.environ.get('GODOT','godot'); REPO=os.environ.get('HL_REPO','.')
N={int(k):tuple(v) for k,v in json.load(open(sys.argv[2])).items()}
pos,nrm,uv,idx=load_raw(D+'raw/'); tl=np.load(D+'tri_lab.npy')
col=Image.open(_tex(0)).convert('RGB'); orm=Image.open(_tex(1)).convert('RGB'); T=col.size[0]
for c,v in N.items():
    name,tris,tex=v[:3]; R=np.array(v[3],np.float64) if len(v)>3 else np.eye(3)   # optional turn (from orient.py) for pitched / rolled pieces
    f=idx[tl==c]; u,inv=np.unique(f,return_inverse=True)
    p=(pos[u].astype(np.float64)@R.T).astype(np.float32); p-=(p.min(0)+p.max(0))/2
    write_glb(D+'tmp/%s_hi.glb'%name,[{"pos":p,"nrm":(nrm[u].astype(np.float64)@R.T).astype(np.float32),"uv":uv[u],"idx":inv.reshape(-1,3),"mat":0}],[{"name":"m"}],[],name)
    r=subprocess.run([G,'--headless','--path',REPO,'--script','tools/shipkit/decimate.gd','--',os.path.abspath(D+'tmp/%s_hi.glb'%name),os.path.abspath(D+'tmp/%s_lo.glb'%name),str(tris)],capture_output=True,text=True)
    line=[l for l in r.stdout.splitlines() if 'DECIMATE' in l]
    P_,N_,U_,I_=read_simple_glb(D+'tmp/%s_lo.glb'%name); U=U_.copy(); nv=len(U)
    # UV charts of this piece (connected through shared vertices), shelf-packed into a new small atlas at native texel size
    ea=np.concatenate([I_[:,0],I_[:,1]]); eb=np.concatenate([I_[:,1],I_[:,2]])
    nc,lab=connected_components(coo_matrix((np.ones(len(ea),np.int8),(ea,eb)),shape=(nv,nv)),directed=False)
    PAD=3; px=U*T
    lo=np.full((nc,2),1e9); hi=np.full((nc,2),-1e9)
    np.minimum.at(lo,lab,px); np.maximum.at(hi,lab,px)
    lo=(np.floor(lo)-PAD).clip(0,T); hi=(np.ceil(hi)+PAD).clip(0,T)
    wh=(hi-lo).astype(int); order=np.argsort(-wh[:,1])
    W=int(max(wh[:,0].max(), np.sqrt((wh[:,0]*wh[:,1]).sum())*1.08))
    dst=np.zeros((nc,2),int); x=y=rowh=0
    for k in order:
        w,h=wh[k]
        if x+w>W: x=0; y+=rowh; rowh=0
        dst[k]=(x,y); x+=w; rowh=max(rowh,h)
    side=max(W,y+rowh)
    def repack(im):
        o=Image.new('RGB',(side,side))
        for k in range(nc):
            if wh[k,0]<=0 or wh[k,1]<=0: continue
            o.paste(im.crop((int(lo[k,0]),int(lo[k,1]),int(hi[k,0]),int(hi[k,1]))),(int(dst[k,0]),int(dst[k,1])))
        return o
    sc=min(1.0,tex/side); sz=(max(4,int(side*sc)),)*2
    def enc(im,q):
        b=io.BytesIO(); repack(im).resize(sz,Image.LANCZOS).save(b,'JPEG',quality=q); return b.getvalue()
    surf={'pos':P_,'nrm':N_,'uv':((px-lo[lab]+dst[lab])/side).astype(np.float32),'idx':I_,'mat':0}
    mat={"name":"hull","pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicRoughnessTexture":{"index":1}}}
    out=D+'out/%s_game.glb'%name
    write_glb(out,[surf],[mat],[(enc(col,86),'image/jpeg'),(enc(orm,80),'image/jpeg')],name)
    print(name,line,'atlas',side,'->',sz,os.path.getsize(out)//1024,'KB',flush=True)
