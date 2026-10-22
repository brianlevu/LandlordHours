from PIL import Image
import glob
A='/Users/brian/AgentScratch/landlordhours/2026-10-22/appstore/'
for k,s in (("phone69",.22),("ipad13",.2)):
    fs=sorted(glob.glob(A+f'out/{k}/*.png'));ims=[Image.open(f).convert('RGB') for f in fs]
    w,h=ims[0].size;w2,h2=int(w*s),int(h*s)
    sh=Image.new('RGB',(w2*len(ims)+20*(len(ims)+1),h2+40),'#d9dde8')
    for i,im in enumerate(ims): sh.paste(im.resize((w2,h2)),(20+i*(w2+20),20))
    sh.save(A+f'contact-sheet-{k}.png')
