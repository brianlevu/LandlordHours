# Round-6 measurements, run on v5 (before) and v6 (after) raw frames. Points x3 = px.
import sys, numpy as np
from PIL import Image
def lin(c):
    c=c/255; return np.where(c<=0.03928, c/12.92, ((c+0.055)/1.055)**2.4)
def lum(rgb): r,g,b=lin(np.array(rgb,float)); return 0.2126*r+0.7152*g+0.0722*b
def cr(a,b): x,y=sorted([lum(a),lum(b)],reverse=True); return (x+0.05)/(y+0.05)
def lab(rgb):
    r,g,b=lin(np.array(rgb,float)); X=(0.4124*r+0.3576*g+0.1805*b)/0.95047; Y=0.2126*r+0.7152*g+0.0722*b; Z=(0.0193*r+0.1192*g+0.9505*b)/1.08883
    f=lambda t: t**(1/3) if t>0.008856 else 7.787*t+16/116
    return np.array([116*f(Y)-16, 500*(f(X)-f(Y)), 200*(f(Y)-f(Z))])
def hexs(c): return '#%02X%02X%02X'%tuple(int(v) for v in c)
def px(im,x,y): return im[int(y*3),int(x*3)][:3]
def med(im,x0,y0,x1,y1): return np.median(im[int(y0*3):int(y1*3),int(x0*3):int(x1*3)].reshape(-1,im.shape[2])[:,:3],axis=0)
root=sys.argv[1]
def load(n): return np.asarray(Image.open(f'{root}/raw/{n}.png').convert('RGB')).astype(int)
out=[]
# 1. selected tab label: label box under the Today glyph, ink = darkest pixel, pill = median of the box's light pixels
for n in ['open-3rentals-dusk','open-allrentals-dusk','open-detail-dusk','open-logtime-dusk','open-8rentals-dusk','open-3rentals-XXL-dusk']:
    im=load(n); box=im[1780+95:1780+132, 1462+160:1462+262].reshape(-1,3)
    L=np.array([lum(p) for p in box]); ink=box[L.argmin()]; pill=np.median(box[L>=np.percentile(L,60)],axis=0)
    out.append(f"1 tab label {n}: ink {hexs(ink)} on pill {hexs(pill)} = {cr(ink,pill):.2f}:1")
# 2. seam and light: wall either side of the fold, room chroma, brightest wall pixel on the right
for th in ['dusk','night']:
    im=load(f'open-3rentals-{th}')
    dEs=[np.linalg.norm(lab(med(im,457,y,462,y+4))-lab(med(im,489,y,494,y+4))) for y in range(30,600,40)]
    far=med(im,935,300,948,320); farlab=lab(far); C=np.hypot(farlab[1],farlab[2])
    row=im[int(60*3), int(488*3):int(950*3)]; Ls=[lum(p) for p in row]; xb=488+np.argmax(Ls)/3
    out.append(f"2 {th}: wall dE across the fold mean {np.mean(dEs):.1f} max {np.max(dEs):.1f}; far right wall {hexs(far)} chroma C* {C:.1f}; brightest wall pixel at y=60pt is {xb-475.5:.0f}pt from the fold")
# 3. fill: empty wall between the last card and the tab bar (column x=720pt), filtered state
for n in ['open-3rentals-dusk','open-allrentals-dusk']:
    im=load(n); col=im[:, int(720*3)]
    surf=np.array([244,239,230]); card=[y for y in range(len(col)) if np.abs(col[y]-surf).max()<10]
    last=max(card)/3 if card else 0
    barTop=618  # the floating tab bar's top edge (measured on the frames)
    out.append(f"3 {n}: last card pixel at {last:.0f}pt, bar top {barTop}pt, empty wall {max(0,barTop-last):.0f}pt = {max(0,barTop-last)/669*100:.0f}% of the pane")
# 6. night card against the room, and its edge
for n in ['open-3rentals-night','open-allrentals-night']:
  for y in (240, 470):
    im=load(n); card=med(im,512,y,520,y+10); room=med(im,490,y,496,y+10)
    edge=None; best=0
    for x in np.arange(500,507,1/3):
        c=px(im,x,y+5); d=cr(c,room)
        if d>best and abs(lum(c)-lum(card))>0.001: best=d; edge=c
    out.append(f"6 {n} y={y}pt: card {hexs(card)} on room {hexs(room)} = {cr(card,room):.2f}:1; edge hairline {hexs(edge)} on room = {best:.2f}:1")
print("\n".join(out))

# ---- v7 additions ----
print("---- v7 ----")
# A. shelf labels: label band y 800-870pt (name row 812-834, status 836-858); clusters of ink columns; min per-cluster contrast
def shelf(n, y0, y1, x0=0, x1=464):
    im=load(n); band=im[int(y0*3):int(y1*3), int(x0*3):int(x1*3)]
    bg=np.median(band.reshape(-1,3),axis=0)
    # per-column best contrast to local bg (median of the column's rows above ink share is noisy; use band median)
    Lb=lum(bg); colc=[]
    for x in range(band.shape[1]):
        col=band[:,x]; L=np.array([lum(p) for p in col]); i=np.abs(L-Lb).argmax(); colc.append(cr(col[i],bg))
    colc=np.array(colc); ink=colc>1.12
    # clusters
    res=[]; i=0
    while i<len(ink):
        if ink[i]:
            j=i
            while j<len(ink) and (ink[j] or (j+1<len(ink) and ink[j+1]) or (j+2<len(ink) and ink[j+2])): j+=1
            res.append((x0+i/3, x0+j/3, colc[i:j].max())); i=j
        else: i+=1
    return res
for n in ['open-8rentals-dusk','open-8rentals-night','open-zerologged-dusk','open-zerologged-night']:
    r=shelf(n,535,585)
    lo=[c for c in r if c[2]<4.5]
    print(f"A {n}: {len(r)} ink clusters, min per-cluster contrast {min(c[2] for c in r):.2f}:1; first cluster x={r[0][0]:.1f}-{r[0][1]:.1f}pt ({r[0][2]:.2f}); last x={r[-1][0]:.1f}-{r[-1][1]:.1f}pt ({r[-1][2]:.2f}); below 4.5: {[(round(a,1),round(b,1),round(c,2)) for a,b,c in lo]}")
