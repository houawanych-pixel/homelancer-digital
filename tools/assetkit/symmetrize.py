"""symmetrize.py score FILE...        -> mirror error (percent of width, noise floor 1 to 3) and the plane's turn for each model
   symmetrize.py fix IN.glb OUT.glb   -> NEW file: straightened along Z, cut at the centre plane, better half mirrored. IN is never changed."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import json, struct, numpy as np
from glbio import write_glb
from scipy.spatial import cKDTree

def read(path):
    d=open(path,'rb').read(); n=struct.unpack('<I',d[12:16])[0]; js=json.loads(d[20:20+n]); b=d[20+n+8:]
    def acc(i):
        a=js['accessors'][i]; bv=js['bufferViews'][a['bufferView']]; off=bv.get('byteOffset',0)+a.get('byteOffset',0)
        comp={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]; dt={5126:np.float32,5125:np.uint32,5123:np.uint16,5121:np.uint8}[a['componentType']]
        return np.frombuffer(b,dt,a['count']*comp,off).reshape(-1,comp).copy()
    P=[];N=[];U=[];I=[];base=0
    for m in js['meshes']:
        for pr in m['primitives']:
            p=acc(pr['attributes']['POSITION']); P.append(p); N.append(acc(pr['attributes']['NORMAL'])); U.append(acc(pr['attributes']['TEXCOORD_0']))
            I.append(acc(pr['indices']).reshape(-1,3).astype(np.int64)+base); base+=len(p)
    imgs=[]
    for im in js.get('images',[]):
        bv=js['bufferViews'][im['bufferView']]; o=bv.get('byteOffset',0); imgs.append((bytes(b[o:o+bv['byteLength']]),im['mimeType']))
    return np.concatenate(P).astype(np.float64),np.concatenate(N).astype(np.float64),np.concatenate(U).astype(np.float64),np.concatenate(I),js,imgs

def surf_points(P,I,n=20000,seed=1):
    rng=np.random.default_rng(seed); a=P[I[:,0]];b=P[I[:,1]];c=P[I[:,2]]
    ar=np.linalg.norm(np.cross(b-a,c-a),axis=1); t=rng.choice(len(I),n,p=ar/ar.sum())
    u=rng.random(n);v=rng.random(n); f=u+v>1; u[f]=1-u[f]; v[f]=1-v[f]
    return a[t]+(b[t]-a[t])*u[:,None]+(c[t]-a[t])*v[:,None]

def _mirror_err(S,tree,n,c):
    d=S[:,0]*n[0]+S[:,2]*n[1]-c; M=S.copy(); M[:,0]-=2*d*n[0]; M[:,2]-=2*d*n[1]
    return tree.query(M)[0].mean()

def best_plane(P,I,nS=7000):
    """Mirror plane: normal horizontal, roughly ACROSS the long axis (so a ship that looks the same fore and aft is not
    mirrored front to back). Returns (error % of width, turn of the plane normal in radians, offset, width)."""
    S=surf_points(P,I,nS); tree=cKDTree(S); xz=S[:,[0,2]]-S[:,[0,2]].mean(0)
    w_,v_=np.linalg.eigh(np.cov(xz.T)); major=v_[:,1]; phi=np.arctan2(major[1],major[0])+np.pi/2
    best=(1e9,phi,0.0)
    for th in phi+np.radians(np.arange(-24,24.1,3)):
        n=(np.cos(th),np.sin(th)); pr=S[:,0]*n[0]+S[:,2]*n[1]; w=np.ptp(pr); mid=(pr.min()+pr.max())/2
        for c in np.linspace(mid-0.06*w,mid+0.06*w,7):
            e=_mirror_err(S,tree,n,c)
            if e<best[0]: best=(e,th,c)
    th0,c0=best[1],best[2]
    for th in th0+np.radians(np.arange(-2.5,2.6,0.5)):
        n=(np.cos(th),np.sin(th)); w=np.ptp(S[:,0]*n[0]+S[:,2]*n[1])
        for c in np.linspace(c0-0.012*w,c0+0.012*w,7):
            e=_mirror_err(S,tree,n,c)
            if e<best[0]: best=(e,th,c)
    n=(np.cos(best[1]),np.sin(best[1])); w=np.ptp(S[:,0]*n[0]+S[:,2]*n[1])
    return best[0]/w*100,best[1],best[2],w

def align(P,N,th,c):
    """Turn about Y so the mirror plane becomes x = 0 (ship nose-to-tail along Z), by the SMALLEST turn so a ship that
    already lies along Z keeps its heading. A ship lying along X can come out facing either way: check with topview."""
    th_in=th; th=(th+np.pi/2)%np.pi-np.pi/2
    c=c if abs(th-th_in)<1e-9 else -c
    cs,sn=np.cos(th),np.sin(th); R=np.array([[cs,0,sn],[0,1,0],[-sn,0,cs]])
    P2=P@R.T; P2[:,0]-=c; return P2,N@R.T

def clip_half(P,N,U,I,c,sign):
    """triangles on the side sign*(x-c) >= 0; crossing ones are cut at the plane so the seam is watertight"""
    s=sign*(P[:,0]-c); eps=1e-7*max(1.0,np.ptp(P[:,0]))
    inside=s>=-eps; cnt=inside[I].sum(1)
    P2=[P];N2=[N];U2=[U]; out=[I[cnt==3]]; nxt=len(P); newp=[];newn=[];newu=[];newt=[]
    for tri in I[(cnt>0)&(cnt<3)]:
        poly=[]
        for k in range(3):
            a=tri[k]; b=tri[(k+1)%3]
            if inside[a]: poly.append(a)
            if inside[a]!=inside[b]:
                t=s[a]/(s[a]-s[b]); p=P[a]+(P[b]-P[a])*t; p[0]=c
                nn=N[a]+(N[b]-N[a])*t; nn/=max(np.linalg.norm(nn),1e-9)
                newp.append(p);newn.append(nn);newu.append(U[a]+(U[b]-U[a])*t); poly.append(nxt); nxt+=1
        for k in range(1,len(poly)-1): newt.append([poly[0],poly[k],poly[k+1]])
    if newp: P2.append(np.array(newp));N2.append(np.array(newn));U2.append(np.array(newu)); out.append(np.array(newt,dtype=np.int64))
    P3=np.concatenate(P2);N3=np.concatenate(N2);U3=np.concatenate(U2);I3=np.concatenate(out)
    used,inv=np.unique(I3,return_inverse=True)
    return P3[used],N3[used],U3[used],inv.reshape(-1,3)

def fix(src,dst):
    P,N,U,I,js,imgs=read(src); sc,th,c,w=best_plane(P,I)
    P,N=align(P,N,th,c)
    halves=[]
    for sign in (1,-1):
        h=clip_half(P,N,U,I,0.0,sign); a=h[0][h[3]]
        halves.append((np.linalg.norm(np.cross(a[:,1]-a[:,0],a[:,2]-a[:,0]),axis=1).sum(),h))
    Ph,Nh,Uh,Ih=max(halves,key=lambda x:x[0])[1]
    Pm=Ph.copy(); Pm[:,0]=-Pm[:,0]; Nm=Nh.copy(); Nm[:,0]=-Nm[:,0]
    P2=np.concatenate([Ph,Pm]); I2=np.concatenate([Ih,Ih[:,::-1]+len(Ph)])   # mirrored half: winding flipped
    P2[:,1]-=(P2[:,1].min()+P2[:,1].max())/2; P2[:,2]-=(P2[:,2].min()+P2[:,2].max())/2
    write_glb(dst,[{"pos":P2,"nrm":np.concatenate([Nh,Nm]),"uv":np.concatenate([Uh,Uh]),"idx":I2,"mat":0}],js['materials'][:1],imgs,js['nodes'][0].get('name','ship'))
    return sc,np.degrees(th)%180,len(I),len(I2)

if __name__=='__main__':
    if sys.argv[1]=='score':
        for f in sys.argv[2:]:
            P,N,U,I,js,imgs=read(f); sc,th,c,w=best_plane(P,I); print('%6.2f%%  turn %6.1f  %s'%(sc,np.degrees(th)%180,f.split('/')[-1]))
    else:
        print('error before %.2f%% (plane normal at %.1f deg), tris %d -> %d'%fix(sys.argv[2],sys.argv[3]))
