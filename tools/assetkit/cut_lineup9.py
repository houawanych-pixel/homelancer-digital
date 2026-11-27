"""cut9.py DIR : the 9 top-down ships of a Tripo fleet-lineup relief -> DIR/ships/tri_lab.npy (labels 0..8 in ROLES order)
Side views (the flat wide rows), the banner (thin, floating in front) and plaques are left out (label -1)."""
import sys, os, json, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glbio import load_raw
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
ROLES=["Capital","Cruiser","Destroyer","Resupply","TroopTransport","Frigate","Escort","Scout","Bomber"]
D=sys.argv[1].rstrip('/')+'/'
pos,nrm,uv,idx=load_raw(D+'raw/')
q=np.round(pos*20000).astype(np.int64); _,inv=np.unique(q,axis=0,return_inverse=True); inv=inv.ravel(); t=inv[idx]; nv=inv.max()+1
c=pos[idx].mean(1)
def comps(mask):
    ii=np.where(mask)[0]; tt=t[ii]
    a=np.concatenate([tt[:,0],tt[:,1]]); b=np.concatenate([tt[:,1],tt[:,2]])
    n,lab=connected_components(coo_matrix((np.ones(len(a),np.int8),(a,b)),shape=(nv,nv)),directed=False)
    return ii, lab[tt[:,0]]
# side-view rows: whole pieces that are wide and short
ii,lab=comps(np.ones(len(t),bool))
sv=[]
for k in np.unique(lab):
    m=ii[lab==k]; p=pos[idx[m]].reshape(-1,3); mn,mx=p.min(0),p.max(0); ext=mx-mn
    if ext[1]<0.075 and ext[0]>0.12 and ext[2]>0.03: sv.append((mn[1],mx[1]))
lo_row=[s for s in sv if s[0]<0.1]; hi_row=[s for s in sv if s[0]>0.2]
top2=max(s[1] for s in lo_row); top1=max(s[1] for s in hi_row); bot1=min(s[0] for s in hi_row)
print('side rows: row2 top %.3f, row1 %.3f..%.3f'%(top2,bot1,top1))
out=np.full(len(t),-1,np.int32)
def info(m):
    p=pos[idx[m]].reshape(-1,3); return p.min(0),p.max(0)
cands=[]   # (m) top-down ship pieces
for k in np.unique(lab):
    m=ii[lab==k]; mn,mx=info(m); ext=mx-mn
    if len(m)<3000: continue
    if ext[1]<0.075 and ext[0]>0.12: continue          # a side view (or a row of them)
    if mn[2]>0.0 and ext[2]<0.04: continue              # the banner: thin, floating in front
    if ext[0]<0.25: cands.append(m); continue           # one whole ship
    # a ship fused to the side-view row: cut it off along the row's top edge
    rtop=top1 if mn[1]>0.2 else top2
    jj,l2=comps(np.isin(np.arange(len(t)),m)&(c[:,1]>rtop))
    for k2 in np.unique(l2):
        m2=jj[l2==k2]; a2,b2=info(m2)
        if len(m2)>3000 and (b2-a2)[0]<0.25 and (b2-a2)[1]>0.1: cands.append(m2); print('  cut from a fused piece at y %.3f'%rtop)
r1=sorted([m for m in cands if info(m)[0][1]>0.2],key=lambda m:info(m)[0][0])
r2=sorted([m for m in cands if info(m)[0][1]<=0.2],key=lambda m:info(m)[0][0])
assert len(r1)==5 and len(r2)==4,(len(r1),len(r2))
for k,m in enumerate(r1+r2): out[m]=k
os.makedirs(D+'ships',exist_ok=True)
np.save(D+'ships/tri_lab.npy',out)
for k,r in enumerate(ROLES):
    m=out==k; p=pos[idx[m]].reshape(-1,3); mn,mx=p.min(0),p.max(0)
    print(r,m.sum(),'x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f'%(mn[0],mx[0],mn[1],mx[1],mn[2],mx[2]))
print('left out',(out<0).sum())
