# iPad 13" (2064x2752) render of the Dormer 2.2 store set. Same story and copy as the iPhone set.
# Sheets (Log time, Export) are cropped to the sheet and shown at native pixel size (narrower frame), never upscaled.
import json, urllib.parse, os, sys
from PIL import Image
from playwright.sync_api import sync_playwright
B=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW=os.environ.get('RAW', B+'/raw'); ART=B+'/src/art'; CROPS=B+'/crops'; OUT=B+'/out/ipad13'
os.makedirs(CROPS,exist_ok=True); os.makedirs(OUT,exist_ok=True)
W,H=2064,2752
H_=lambda a,b: f'{a.strip()}<br><span class="hl">{b}</span>'

def sheet_bbox(path):
    """Bounding box of the centred form sheet: the bright card over the dimmed screen."""
    im=Image.open(path).convert('RGB'); w,h=im.size; cx=w//2
    col=[sum(im.getpixel((cx,y))) for y in range(h)]
    bright=[y for y in range(h) if col[y]>735]
    top,bot=bright[0],bright[-1]
    mid=(top+bot)//2
    row=[sum(im.getpixel((x,mid))) for x in range(w)]
    xs=[x for x in range(w) if row[x]>735]
    return xs[0],top,xs[-1]+1,bot+1

def prep(name, mode, top_frac=None):
    src=f'{RAW}/{name}'; im=Image.open(src).convert('RGB')
    if mode=='full':
        # Crop off the empty tail under the last content row (+120 px), so the frame ends with the content.
        w,h=im.size; px=im.load(); last=0
        for y in range(h-90,0,-1):
            if sum(1 for x in range(0,1980,3) if sum(px[x,y])<450)>3: last=y; break
        c=im.crop((0,0,w,min(h,last+120)))
        p=f'{CROPS}/{name}'; c.save(p); return p, c.size[0], c.size[1]
    if mode=='sheet':
        l,t,r,b=sheet_bbox(src)
        if top_frac: b=t+int((b-t)*top_frac)
        c=im.crop((l,t,r,b))
    elif mode=='top':
        c=im.crop((0,0,im.size[0],top_frac))
    p=f'{CROPS}/{name}'; c.save(p); return p, c.size[0], c.size[1]

panels=[
 ("01-counted", dict(poster=True, h=H_("Every rental hour, ","counted."), laurel="For landlords and STR hosts<br>Track 100, 500 or 750 hours",
                     icon=ART+'/icon.png', house=ART+'/craft_complete_light.png'), None),
 ("02-onpace", dict(h=H_("Know if you’re ","on pace")), ('02-today.png','full',None)),
 ("03-log",    dict(h=H_("Log by voice ","or a quick note")), ('03-log.png','sheet',None)),
 ("04-inbox",  dict(h=H_("Your calendar ","finds rental work")), ('04-inbox.png','full',None)),
 ("05-rentals",dict(h=H_("One record ","per rental")), ('05-rentals.png','full',None)),
 ("06-cpa",    dict(h=H_("A PDF your ","CPA can use")), ('06-export.png','sheet',None)),
 ("07-icloud", dict(h=H_("Your iCloud. ","No sign-in."), note='Your records live on this iPad and in your own iCloud. We never see them.',
                    house=ART+'/craft_complete_dark.png'), ('07-icloud.png','top',int(os.environ.get('ICLOUD_CUT','360')))),
]
ONLY=os.environ.get('ONLY')
with sync_playwright() as pw:
    b=pw.chromium.launch(executable_path='/Users/brian/Library/Caches/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-mac-arm64/chrome-headless-shell')
    pg=b.new_page(viewport={'width':W,'height':H},device_scale_factor=1)
    for n,d,cap in panels:
        if ONLY and n not in ONLY.split(','): continue
        d=dict(d)
        if cap:
            img,iw,ih=prep(*cap); d.update(img=img, ar=iw, arh=ih)
            if cap[1]=='sheet':
                d['dwPad']=round(iw*1.15/W*100,3)   # 1.15x of native: still smaller than the full screens
                d['drPad']=4.36*1.15
            else:
                d['dwPad']=90; d['drPad']=3.6*90/78; d['drbPad']=3.6*90/78  # tail cropped, so the resize grip is gone too
            if cap[1]!='top':
                # Centre each frame in the space under the headline (never above the 531 px anchor).
                fh=W*d['dwPad']/100*ih/iw; top=531+max(0,(H-531-80-fh)/2); d['dtPad']=round(top/H*100,3)
            if cap[1]=='top':
                d['drbPad']=3.6; d['go']=0.22
                d.update(nt='34.5%', hw='54vw', htop='45%', gt='62%')
        pg.goto('file://'+B+'/src/index.html?m=ipad&d='+urllib.parse.quote(json.dumps(d)))
        pg.wait_for_timeout(500); pg.screenshot(path=f'{OUT}/{n}.png'); print(n, d.get('dwPad'))
    b.close()
