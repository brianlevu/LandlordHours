import glob, hashlib, math
from PIL import Image
def lum(c):
    f=lambda v:(v/255/12.92) if v/255<=0.03928 else ((v/255+0.055)/1.055)**2.4
    return 0.2126*f(c[0])+0.7152*f(c[1])+0.0722*f(c[2])
def cr(a,b):
    x,y=sorted([lum(a),lum(b)],reverse=True); return (x+0.05)/(y+0.05)
fs=sorted(glob.glob('out/ipad13/*.png')); hs={}
for f in fs:
    im=Image.open(f).convert('RGB'); W,H=im.size
    # caption band: lightest background pixel in the headline band margins (worst case)
    bg=max((im.getpixel((int(W*0.03),int(H*y))) for y in (0.03,0.08,0.13,0.17)), key=lum)
    # caption ink sampled: brightest white and the cyan accent token
    print(f"{f.split('/')[-1]:14s} {W}x{H} bg={bg} white={cr((255,255,255),bg):.2f} accent={cr((0x8F,0xD3,0xFF),bg):.2f} sub={cr((0xC9,0xD6,0xF5),bg):.2f}", end=' ')
    # clipping: caption text must not touch the left/right 2% margins in the headline band
    band=[(x,y) for y in range(0,int(H*0.19),3) for x in list(range(0,int(W*0.04)))+list(range(int(W*0.96),W)) if sum(im.getpixel((x,y)))>600]
    # bottom edge: any light ink on the last 4 rows outside the device frame
    print(f"edge_text_px={len(band)}", end=' ')
    h=hashlib.sha256(open(f,'rb').read()).hexdigest(); hs.setdefault(h,[]).append(f)
    print()
print('byte-identical pairs:', [v for v in hs.values() if len(v)>1])
# centred column: horizontal centre of the white content cards in the raw full-screen captures
for n in ('02-today','04-inbox','05-rentals','07-icloud'):
    im=Image.open(f'raw/{n}.png').convert('RGB'); W,H=im.size; y0=int(H*0.12)
    xs=[x for y in range(y0,int(H*0.6),12) for x in range(0,W,4) if im.getpixel((x,y))==(255,255,255)]
    if xs: l,r=min(xs),max(xs); print(f'raw {n}: white content spans x {l}-{r} ({(r-l)/2:.0f}pt wide @2x), centre {(l+r)/2:.0f} vs screen centre {W/2:.0f}')
