"""Record both phone compositions in an already verified owned headless browser."""
import argparse,os
from pathlib import Path
from capture import ab,js,start,cue,hold,end,stop
p=argparse.ArgumentParser();p.add_argument('composition',type=Path);p.add_argument('--duration',type=float,default=6.5);a=p.parse_args()
for name,w,h in [('desktop',1200,800),('mobile',480,1000)]:
 ab('open',a.composition.resolve().as_uri());ab('set','viewport',w,h)
 ab('wait','--fn','document.querySelector("video").readyState >= 2')
 start('iphone-scanner-'+name+'-'+os.environ.get('CAPTURE_LOCALE','cs'));cue('qr-confirm-success');js('window.playTake()');hold(a.duration);end();print(stop()['directory'])
