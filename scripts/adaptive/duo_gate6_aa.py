exec(open('/Users/brian/AgentScratch/landlordhours/2026-10-24/duo-gate6/m.py').read())
import numpy as np, sys
REG={
 'R:To confirm':(1559,317,1812,359),'R:count 3':(2696,364,2760,449),
 'R:chip Pine Cabin':(1598,417,1819,464),'R:row1 title':(1659,559,2325,606),
 'R:row1 15m':(2610,563,2696,599),'R:meta Reminder':(1730,628,1911,670),
 'R:tag Bookkeeping':(1954,628,2183,668),'R:tag Leasing':(2140,824,2268,863),
 'R:tag Needs hours':(1975,1016,2161,1056),'R:link 4 more':(1911,1144,2404,1187),
 'R:On the record':(1559,1341,2033,1387),'R:2h':(2710,1341,2767,1384),
 'R:meta Repairs':(1559,1529,1854,1566),
 'L:262':(521,906,884,1034),'L:of 500 hours':(409,1134,984,1181),
 'L:Behind by 143h':(235,1210,563,1255),'L:25h a week':(571,1210,1167,1255),
 'L:shelf All rentals':(114,1626,302,1669),'L:shelf sub 3of3':(103,1686,317,1719),
 'L:chip Pine Cabin':(1080,1626,1279,1669),'L:chip sub 262of500h':(1073,1683,1288,1719),
 'T:tab Inbox':(1869,1883,1954,1918),'T:tab Log time':(2545,1883,2720,1918),
}
def meas(path,dark_ink):
    a=np.array(Image.open(path).convert('RGB'),dtype=float)
    out=[]
    for k,(x0,y0,x1,y1) in REG.items():
        sub=a[y0:y1,x0:x1].reshape(-1,3)
        l=np.apply_along_axis(L,1,sub)
        o=np.argsort(l)
        ink = sub[o[0]] if dark_ink else sub[o[-1]]
        bg  = sub[o[-1]] if dark_ink else sub[o[0]]
        # bg = robust: 90th/10th percentile to avoid stray
        bg  = sub[o[int(len(o)*0.93)]] if dark_ink else sub[o[int(len(o)*0.07)]]
        out.append((k,hx(ink),hx(bg),cr(ink,bg)))
    return out
