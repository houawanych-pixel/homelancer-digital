import sys, os, numpy as np
from PIL import Image
E=560; X=300
SEAM = os.environ.get("STITCH_SEAM", "") != ""   # v6.7: cut along the best-matching path (no ghosted people) instead of a wide crossfade
F = 10                                           # feather either side of the cut (px)
def blend(a, b):
  """a and b cover the same X columns; returns the mix: a on the left, b on the right."""
  if not SEAM:
    r=np.linspace(0,1,a.shape[1])[None,:,None]
    return a*(1-r)+b*r
  d=np.abs(a-b).mean(2)                          # H x X
  H,Wd=d.shape
  cost=d.copy(); back=np.zeros((H,Wd),int)
  for y in range(1,H):
    left=np.r_[np.inf,cost[y-1,:-1]]; right=np.r_[cost[y-1,1:],np.inf]; mid=cost[y-1]
    st=np.vstack([left,mid,right]); k=st.argmin(0); back[y]=k-1
    cost[y]+=st[k,np.arange(Wd)]
  cut=np.zeros(H,int); cut[-1]=int(cost[-1, F:Wd-F].argmin())+F
  for y in range(H-1,0,-1): cut[y-1]=np.clip(cut[y]+back[y,cut[y]],F,Wd-F-1)
  xs=np.arange(Wd)[None,:]
  r=np.clip((xs-(cut[:,None]-F))/(2.0*F),0,1)[:,:,None]
  return a*(1-r)+b*r
def halves(im):
  W,H=im.size; m=H//2
  t=im.crop((0,0,W,m-6)); b=im.crop((0,m+6,W,H)); h=min(t.height,b.height)
  return np.array(t.crop((0,0,W,h))).astype(float), np.array(b.crop((0,0,W,h))).astype(float)
def shift_of(ref, mov):
  # best (dx,dy) so mov shifted matches ref (grey, small search)
  a=ref.mean(2); b=mov.mean(2); best=(1e18,0,0)
  for dy in range(-12,13,2):
    for dx in range(-40,41,2):
      ya,yb=max(0,dy),max(0,-dy); xa,xb=max(0,dx),max(0,-dx)
      h=a.shape[0]-abs(dy); w=a.shape[1]-abs(dx)
      d=np.abs(a[ya:ya+h,xa:xa+w]-b[yb:yb+h,xb:xb+w]).mean()
      if d<best[0]: best=(d,dx,dy)
  return best
def roll(img,dx,dy):
  return np.roll(np.roll(img,dy,0),dx,1)
def join(a,b):   # a's last E cols == b's first E cols
  W=a.shape[1]; s=(E-X)//2
  mid=blend(a[:,W-E+s:W-E+s+X], b[:,s:s+X])
  return np.concatenate([a[:,:W-E+s],mid,b[:,s+X:]],1)
orig,filled,out=sys.argv[1:4]
fr,bk=halves(Image.open(orig).convert('RGB'))
fi=Image.open(filled).convert('RGB').resize(Image.open(orig).size)
r1,r2=halves(fi)
W=fr.shape[1]
# align each filled row to the originals it overlaps (left piece)
d1=shift_of(fr[:,W-E:], r1[:,:E]); r1=roll(r1,d1[1],d1[2])
d2=shift_of(bk[:,W-E:], r2[:,:E]); r2=roll(r2,d2[1],d2[2])
s=join(join(join(fr,r1),bk),r2)
L=s.shape[1]-E
f=s[:,:L].copy(); tail=s[:,L:]          # tail redraws front[0:E]
st=(E-X)//2
f[:,:st]=tail[:,:st]
f[:,st:st+X]=blend(tail[:,st:st+X], f[:,st:st+X])
Image.fromarray(f.clip(0,255).astype(np.uint8)).save(out,quality=88)
print(out, f.shape[1], 'shifts', d1[1:], d2[1:], 'err', round(d1[0],1), round(d2[0],1))
