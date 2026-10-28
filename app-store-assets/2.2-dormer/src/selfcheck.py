import glob
from PIL import Image
def lum(c):
    def ch(v):
        v/=255; return v/12.92 if v<=0.03928 else ((v+0.055)/1.055)**2.4
    r,g,b=c[:3]; return 0.2126*ch(r)+0.7152*ch(g)+0.0722*ch(b)
def cr(a,b):
    la,lb=sorted([lum(a),lum(b)],reverse=True); return (la+0.05)/(lb+0.05)
for size in ('phone69','phone65'):
  for f in sorted(glob.glob(f'out/{size}/*.png')):
    im=Image.open(f).convert('RGB'); w,h=im.size
    # background samples in the headline band, left margin
    bgs=[im.getpixel((int(w*0.03),int(h*y))) for y in (0.05,0.10,0.15,0.20)]
    darkest_bg=max(bgs,key=lum)  # worst case = lightest bg
    white=(255,255,255); acc=(0x8F,0xD3,0xFF); sub=(0xC9,0xD6,0xF5)
    # device top edge: first row at x=w/2 below 15% that is near-white
    top=None
    for y in range(int(h*0.15),int(h*0.5)):
        p=im.getpixel((w//2,y))
        if sum(p)>700: top=y;break
    # left edge of device at 40% height
    left=None
    for x in range(0,w//4):
        p=im.getpixel((x,int(h*0.45)))
        if sum(p)>600: left=x;break
    print(f"{size} {f.split('/')[-1]:14s} bg_lightest={darkest_bg} white={cr(white,darkest_bg):.2f} accent={cr(acc,darkest_bg):.2f} sub={cr(sub,darkest_bg):.2f} device_top={top} device_left={left}")
