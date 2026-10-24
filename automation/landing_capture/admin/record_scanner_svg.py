"""Record direct dark SVG composition in a verified isolated headless browser."""
import argparse
from capture import *
p=argparse.ArgumentParser();p.add_argument('composition',type=Path);a=p.parse_args()
for name,w,h in [('desktop',1200,800),('mobile',500,1000)]:
 ab('open',a.composition.resolve().as_uri());ab('set','viewport',w,h)
 ab('wait','--fn','document.querySelector("video").readyState >= 2')
 js('document.fonts.ready.then(()=>true)');assert js('document.fonts.check("500 44px Futura")')
 start('iphone-svg-'+name);cue('actual-scan-accept-reject');js('window.playTake()');hold(8.5);end();print(stop()['directory'])
