"""Experimental evidence gate, historical fits and their automatic combinations."""
import json,time
from pathlib import Path
import numpy as np

def fit(beats,strengths,flexible=True):
    t=np.array(beats[-9:]);w=np.array(strengths[-9:])
    use=w>=(.2 if flexible else .4);t=t[use];w=w[use]
    if len(t)<(4 if flexible else 5):return None
    if not flexible:
        t=t[-5:];w=w[-5:];steps=np.arange(5)
        p=float(np.polyfit(steps,t,1)[0]);res=np.abs(t-(t.mean()+(steps-2)*p))
        if not 60/215<=p<=60/55 or res.max()>max(.03,p*.08) or w.mean()<.55:return None
        return dict(period=p,beat=float(t[-1]),quality=float(w.mean()),support=1.,start=float(t[0]))
    best=None
    for divisor in (1,2,3):
        for p0 in np.diff(t)/divisor:
            if not 60/215<=p0<=60/55:continue
            steps=np.rint((t-t[-1])/p0)
            good=np.abs(t-(t[-1]+steps*p0))<=max(.045,p0*.12)
            if good.sum()<4 or w[good].sum()/w.sum()<.7:continue
            k=steps[good];v=t[good];ww=w[good]
            if len(np.unique(k))<4:continue
            p,intercept=np.polyfit(k,v,1,w=ww)
            if not 60/215<=p<=60/55:continue
            occupied=len(np.unique(k))/max(1,k.max()-k.min()+1)
            q=float(ww.mean());score=q*float(w[good].sum()/w.sum())-.15*(1-occupied)
            if q>=.45 and (best is None or score>best[0]):
                best=(score,dict(period=float(p),beat=float(intercept),quality=q,support=float(good.mean()),start=float(v.min())))
    return None if best is None else best[1]
