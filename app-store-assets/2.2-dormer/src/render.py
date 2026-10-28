import json, urllib.parse, os, sys
from playwright.sync_api import sync_playwright
B='/Users/brian/AgentScratch/landlordhours/2026-10-27/screenshots'
RAW=B+'/raw/final3'; RAWPAD=B+'/raw/ipad'; ART=B+'/src/art'
H=lambda a,b: f'{a}<span class="hl">{b}</span>'
W,HH=1320,2868
panels=[
 ("01-counted", dict(poster=True, h=H("Every rental hour, ","counted."), laurel="For landlords and STR hosts<br>Track 100, 500 or 750 hours",
                     icon=ART+'/icon.png', house=ART+'/craft_complete_light.png')),
 ("02-onpace", dict(h=H("Know if you’re ","on pace"), img='02-today.png')),
 ("03-log",    dict(h=H("Log by voice ","or a quick note"), img='03-log.png', crop=[188/2868,2520/2868])),
 ("04-inbox",  dict(h=H("Your calendar ","finds rental work"), img='04-inbox.png')),
 ("05-rentals",dict(h=H("One record ","per rental"), img='05-rentals.png')),
 ("06-cpa",    dict(h=H("A PDF your ","CPA can use"), img='06-export.png', raw='final4', crop=[188/2868,2500/2868])),
 ("07-icloud", dict(h=H("Your iCloud. ","No sign-in."), img='07-icloud.png', crop=[0,640/2868], note='Your records live on this iPhone and in your own iCloud. We never see them.', house=ART+'/craft_complete_dark.png',
                    nt='45.5%', hw='84vw', htop='54%', gt='70%')),
]
ONLY=os.environ.get('ONLY'); SIZES=os.environ.get('SIZES','phone69,phone65').split(',')
sizes={"phone69":(1320,2868,"phone"),"phone65":(1284,2778,"phone"),"ipad13":(2064,2752,"ipad")}
with sync_playwright() as pw:
    b=pw.chromium.launch(executable_path='/Users/brian/Library/Caches/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-mac-arm64/chrome-headless-shell')
    for key in SIZES:
        w,h,mode=sizes[key]; os.makedirs(f'{B}/out/{key}',exist_ok=True)
        pg=b.new_page(viewport={'width':w,'height':h},device_scale_factor=1)
        for n,d in panels:
            if ONLY and n not in ONLY.split(','): continue
            d=dict(d)
            if 'img' in d:
                d['img']=(RAWPAD if mode=='ipad' else (B+'/raw/'+d.pop('raw') if 'raw' in d else RAW))+'/'+d['img']
                from PIL import Image
                iw,ih=Image.open(d['img']).size; d['ar']=iw; d['arh']=ih
            pg.goto('file://'+B+'/src/index.html?m='+mode+'&d='+urllib.parse.quote(json.dumps(d)))
            pg.wait_for_timeout(500); pg.screenshot(path=f'{B}/out/{key}/{n}.png')
            print(key,n)
    b.close()
