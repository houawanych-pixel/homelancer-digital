import sys,json;sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)));import shipkit as sk, numpy as np
from PIL import Image, ImageDraw
src=sys.argv[1]; out=sys.argv[2]; SC=float(sys.argv[3]) if len(sys.argv)>3 else 1.0
js,b=sk.read_glb(src); pr=js['meshes'][0]['primitives'][0]
P=sk.accessor(js,b,pr['attributes']['POSITION']); I=sk.accessor(js,b,pr['indices']).reshape(-1,3).astype(int)
J=sk.accessor(js,b,pr['attributes']['JOINTS_0']).astype(int); W=sk.accessor(js,b,pr['attributes']['WEIGHTS_0'])
names=[js['nodes'][j]['name'] for j in js['skins'][0]['joints']]
def grp(n):
    for k,c in [('RightHand',(255,60,60)),('R_Index',(255,60,60)),('R_Mid',(255,60,60)),('R_Ring',(255,60,60)),('R_Pinky',(255,60,60)),('R_Thumb',(255,60,60)),
                ('RightLowerArm',(255,150,60)),('R_Elbow',(255,150,60)),('RightUpperArm',(255,220,60)),('RightShoulder',(200,200,60)),
                ('LeftHand',(60,120,255)),('L_Index',(60,120,255)),('L_Mid',(60,120,255)),('L_Ring',(60,120,255)),('L_Pinky',(60,120,255)),('L_Thumb',(60,120,255)),
                ('LeftLowerArm',(60,200,255)),('L_Elbow',(60,200,255)),('LeftUpperArm',(120,255,255)),('LeftShoulder',(150,150,255)),
                ('Head',(255,255,255)),('Neck',(220,220,220)),('Eye',(255,255,255)),('Facial',(255,255,255)),('UpperChest',(60,220,60)),('Chest',(40,160,40)),('Spine',(20,110,20)),
                ('Hips',(140,90,40)),('Pelvis',(140,90,40)),('RightUpperLeg',(200,80,200)),('RightLowerLeg',(160,60,160)),('R_Knee',(160,60,160)),('RightFoot',(120,40,120)),('RightToes',(120,40,120)),
                ('LeftUpperLeg',(80,200,160)),('LeftLowerLeg',(60,160,130)),('L_Knee',(60,160,130)),('LeftFoot',(40,120,100)),('LeftToes',(40,120,100))]:
        if k in n: return c
    return (90,90,90)
col=np.array([grp(n) for n in names])
dom=J[np.arange(len(P)),np.argmax(W,1)]; vc=col[dom].astype(float)
tc=vc[I].mean(1)
Wd=700
def view(ha,va,sh,sv,dep):
    img=Image.new('RGB',(Wd,Wd),(10,12,20)); d=ImageDraw.Draw(img)
    X=(sh*P[:,ha]/SC+0.55)/1.1*Wd; Y=(1.05-P[:,va]/SC)/1.1*Wd
    depth=dep(P)[I].mean(1)
    for k in np.argsort(depth):
        d.polygon([(X[i],Y[i]) for i in I[k]], fill=tuple(int(v) for v in tc[k]))
    for v in np.arange(0,1.01,0.1):
        yy=(1.05-v)/1.1*Wd; d.line([(0,yy),(Wd,yy)],fill=(70,70,70)); d.text((2,yy),'y%.1f'%v,fill=(200,200,200))
    for v in np.arange(-0.5,0.51,0.1):
        xx=(v+0.55)/1.1*Wd; d.line([(xx,0),(xx,Wd)],fill=(70,70,70)); d.text((xx+2,2),'%.1f'%(v*sh),fill=(200,200,200))
    return img
tri_sub=np.random.default_rng(0).choice(len(I),min(len(I),160000),replace=False); I=I[tri_sub]; tc=tc[tri_sub]
a=view(0,1,1,1,lambda p:p[:,2]); b2=view(2,1,-1,1,lambda p:p[:,0]); c=view(0,1,-1,1,lambda p:-p[:,2])
S=Image.new('RGB',(Wd*3,Wd+30),(0,0,0)); S.paste(a,(0,0)); S.paste(b2,(Wd,0)); S.paste(c,(2*Wd,0))
d=ImageDraw.Draw(S); d.text((10,Wd+8),'FRONT (x)   |  SIDE (horizontal = -z, front is left)  |  BACK.   red=R hand  orange=R forearm  yellow=R upperarm  blue=L hand  cyan=L forearm  lightcyan=L upperarm  green=spine  brown=hip  purple=R leg  teal=L leg  white=head',fill=(255,255,255))
S.save(out)
