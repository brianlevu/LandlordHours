import sys
from PIL import Image
out=sys.argv[1]; fs=sys.argv[2:]
ims=[Image.open(f).convert('RGB') for f in fs]
h=900; ims=[im.resize((int(im.width*h/im.height),h)) for im in ims]
s=Image.new('RGB',(sum(i.width+10 for i in ims),h),'white'); x=0
for im in ims: s.paste(im,(x,0)); x+=im.width+10
s.save(out)
