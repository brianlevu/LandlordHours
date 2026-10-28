from PIL import Image
import glob
B='/Users/brian/AgentScratch/landlordhours/2026-10-27/screenshots/'
for k,s in (("phone69",.25),):
    fs=sorted(glob.glob(B+f'out/{k}/*.png')); ims=[Image.open(f).convert('RGB') for f in fs]
    w,h=ims[0].size; w2,h2=int(w*s),int(h*s)
    sh=Image.new('RGB',(w2*len(ims)+24*(len(ims)+1),h2+48),'#E6E9F0')
    for i,im in enumerate(ims): sh.paste(im.resize((w2,h2),Image.LANCZOS),(24+i*(w2+24),24))
    sh.save(B+f'contact-sheet-{k}.png')
    # App Store search-result thumbnail scale (~1/6)
    t=[im.resize((220,478),Image.LANCZOS) for im in ims]
    th=Image.new('RGB',(220*len(t)+12*(len(t)+1),478+24),'white')
    for i,im in enumerate(t): th.paste(im,(12+i*232,12))
    th.save(B+f'thumb-check-{k}.png')
