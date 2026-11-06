import numpy as np
from PIL import Image
from scipy import ndimage as ndi
src='/Users/brian/AgentScratch/landlordhours/2026-10-27/dormer-v3-glass/gen/embossed-1.png'
im=np.asarray(Image.open(src).convert('RGB')).astype(np.float64)
H,W,_=im.shape
mn=im.min(2)
# D silhouette: whitish pixels (blue bg has min channel < ~200 -> check)
core=mn>150
lab,n=ndi.label(core)
sizes=ndi.sum(core,lab,range(1,n+1)); k=1+int(np.argmax(sizes))
D=lab==k
D=ndi.binary_fill_holes(D)  # no-op for D (hole open to bg? it's enclosed) -> we must NOT fill the counter
D=lab==k
print('D px',D.sum(),'components',n)
# soft alpha: smooth ramp between bg-ish and white using min channel across edge, then feather
dist_in=ndi.distance_transform_edt(D); dist_out=ndi.distance_transform_edt(~D)
sd=dist_in-dist_out  # signed
alpha=np.clip(0.5+sd/2.0,0,1)  # ~2px feather centred on edge
band=np.abs(sd)<4
ie=ndi.distance_transform_edt(~(dist_out>=4),return_indices=True)[1]
E=im[ie[0],ie[1]]
im2=ndi.distance_transform_edt(~(dist_in>=4),return_indices=True)[1]
Mi=im[im2[0],im2[1]]
dv=Mi-E
proj=((im-E)*dv).sum(2)/np.maximum((dv*dv).sum(2),1e-6)
alpha=np.where(band,np.clip(proj,0,1),np.where(D,1.0,0.0))
# shadow/influence zone
zone=ndi.distance_transform_edt(~D)<70
# background fit on pixels far from mark (>90px)
far=ndi.distance_transform_edt(~D)>90
yy,xx=np.mgrid[0:H,0:W]/ (H-1.0)
def basis(x,y,deg=4):
    return np.stack([x**i*y**j for i in range(deg+1) for j in range(deg+1-i)],-1)
B=basis(xx,yy)
bg=np.zeros_like(im)
for c in range(3):
    A=B[far]; b=im[...,c][far]
    # subsample for speed
    idx=np.random.RandomState(0).choice(len(b),200000,replace=False)
    coef=np.linalg.lstsq(A[idx],b[idx],rcond=None)[0]
    bg[...,c]=np.einsum('ijk,k->ij',B,coef)
res=(im-bg)[far]
print('bg fit rms per ch',np.sqrt((res**2).mean(0)))
bg_img=np.clip(bg+0.5,0,255).astype(np.uint8)
Image.fromarray(bg_img).save('ground-light.png')
# two-layer solve: shadow (under) + mark (over)
dout=ndi.distance_transform_edt(~D)
E_all=np.where((dist_out>=4)[...,None],im,E)
vd=np.array([0.09652035,0.28715457,1.0]); vb=np.array([0.96968059,1.0,0.67195543])
Sd=bg-bg[...,2:3]*vd                      # dark shadow colour (zero blue)
Sb=np.minimum(bg+(255-bg[...,1:2])*vb,255) # bright halo colour
wd=bg-Sd; wb=Sb-bg
dif=E_all-bg
Ad=np.clip(-(dif*wd).sum(2)/np.maximum((wd*wd).sum(2),1e-6),0,1)
Ab=np.clip((dif*wb).sum(2)/np.maximum((wb*wb).sum(2),1e-6),0,1)
neg=dif.mean(2)<0
As=np.where(neg,Ad,Ab); Cs=np.where(neg[...,None],Sd,Sb)
As[(dout>=90)|(dist_in>=6)]=0; As[As<0.01]=0
sh=np.dstack([np.clip(Cs+0.5,0,255),As*255+0.5]).astype(np.uint8)
sh[As==0,:3]=0
Image.fromarray(sh).save('shadow.png')
Aq=sh[...,3:]/255.0; Cq=sh[...,:3].astype(float)
under=bg_img*(1-Aq)+Cq*Aq
# mark colour: unpremultiply against `under`
al=alpha
Cm=(im-under*(1-al[...,None]))/np.maximum(al[...,None],1e-3)
Cm=np.clip(Cm,0,255); Cm[al<0.01]=0
mk=np.dstack([np.clip(Cm+0.5,0,255),al*255+0.5]).astype(np.uint8)
Image.fromarray(mk).save('mark.png')
a=mk[...,3:]/255.0
rc=under*(1-a)+mk[...,:3]*a
print('recomposite max abs',np.abs(rc-im).max(),'mean',np.abs(rc-im).mean(), (np.abs(rc-im).max(2)>10).sum())
Image.fromarray(np.clip(rc+0.5,0,255).astype(np.uint8)).save('recomposite.png')
