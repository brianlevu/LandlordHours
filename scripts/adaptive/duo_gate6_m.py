from PIL import Image
import numpy as np, sys, glob, os
D='/Users/brian/AgentScratch/landlordhours/2026-10-24/duo-concept-v6/frames/'
def lin(c):
    c=c/255.0
    return np.where(c<=0.04045,c/12.92,((c+0.055)/1.055)**2.4)
def L(rgb):
    r,g,b=[lin(np.array(x,dtype=float)) for x in rgb]
    return 0.2126*r+0.7152*g+0.0722*b
def cr(a,b):
    l1,l2=L(a),L(b)
    hi,lo=max(l1,l2),min(l1,l2)
    return (hi+0.05)/(lo+0.05)
def hx(p): return '#%02X%02X%02X'%tuple(int(v) for v in p[:3])
def lab(rgb):
    # sRGB -> Lab D65
    r,g,b=lin(np.array(rgb,dtype=float))
    X=r*0.4124+g*0.3576+b*0.1805; Y=r*0.2126+g*0.7152+b*0.0722; Z=r*0.0193+g*0.1192+b*0.9505
    xn,yn,zn=0.95047,1.0,1.08883
    def f(t): return np.cbrt(t) if t>0.008856 else (7.787*t+16/116)
    fx,fy,fz=f(X/xn),f(Y/yn),f(Z/zn)
    return np.array([116*fy-16,500*(fx-fy),200*(fy-fz)])
