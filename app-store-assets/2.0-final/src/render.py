import json, urllib.parse, os, sys
from playwright.sync_api import sync_playwright
B='/Users/brian/AgentScratch/landlordhours/2026-10-22/appstore'
H='<span class="hl">%s</span>'
phone=[
 ("01-onpace","Know if you're on track <span class=hl>for your hours</span>","raw/td_0520.png",{}),
 ("02-str","Short-term rental? <span class=hl>Track material participation</span>","raw/str_conf.png",{}),
 ("03-inbox","Your calendar <span class=hl>finds your hours</span>","raw/inbox_two.png",{}),
 ("04-log","Type what you did. <span class=hl>It's logged and dated.</span>","raw/log.png",{}),
 ("05-rentals","Each rental, <span class=hl>its own count</span>","raw/props.png",{}),
 ("06-records","Records your <span class=hl>CPA can use</span>","raw/records.png",{}),
 ("07-private","Stays on your iPhone <span class=hl>and in your iCloud.</span>","raw/priv.png",{}),
]
HOLD=set()
PADMAP={'01-onpace':'today.png','02-str':'str_conf.png','03-inbox':'inbox_two.png','04-log':'log.png','05-rentals':'props12.png','06-records':'records.png','07-private':'priv.png'}
ONLY=os.environ.get('ONLY')
sizes={"phone69":(1320,2868,"phone"),"phone65":(1284,2778,"phone"),"ipad13":(2064,2752,"ipad")}
os.makedirs(B+'/out',exist_ok=True)
with sync_playwright() as pw:
    b=pw.chromium.launch(executable_path='/Users/brian/Library/Caches/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-mac-arm64/chrome-headless-shell')
    for key,(w,h,mode) in sizes.items():
        if ONLY and key not in ONLY.split(','): continue
        os.makedirs(f'{B}/out/{key}',exist_ok=True)
        pg=b.new_page(viewport={'width':w,'height':h},device_scale_factor=1)
        items=[x for x in phone if x[0] not in HOLD]
        for n,hd,img,extra in items:
            if img.startswith('raw/'): img=('../rawpad/'+PADMAP.get(n,img[4:]) if mode=='ipad' else '../raw/'+img[4:])
            else: img='../'+img if img.startswith('src/') is False else img[4:]
            extra=dict(extra)
            if mode=='ipad': extra.setdefault('dwPad',80); extra.setdefault('dtPad',17)
            d=dict(h=hd,img=img,**extra)
            pg.goto('file://'+B+'/src/index.html?m='+mode+'&d='+urllib.parse.quote(json.dumps(d)))
            pg.wait_for_timeout(400); pg.screenshot(path=f'{B}/out/{key}/{n}.png')
    b.close()
