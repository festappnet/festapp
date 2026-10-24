"""Film the actual disclosure on a completed local unpaid order receipt."""
import os,json,pathlib,subprocess,time,signal
from encode import encode
wrapper=os.environ['BROWSER_WRAPPER'];out=pathlib.Path(os.environ['CAPTURE_OUT']).resolve();out.mkdir(parents=True,exist_ok=True)
mobile=os.environ.get('CAPTURE_MOBILE')=='1';name='payment-qr'+('-mobile' if mobile else '')
def browser(*args): return subprocess.run([wrapper,*args],capture_output=True,text=True,check=True).stdout.strip()
assert 'HeadlessChrome' in browser('eval','navigator.userAgent')
assert json.loads(browser('session','info','--json'))['data']['runtime']['pageCount']==1
assert json.loads(browser('eval','location.hostname'))=='127.0.0.1'
assert json.loads(browser('eval','Boolean(document.querySelector(".result-payment-more"))'))
browser('set','viewport',*(['390','844'] if mobile else ['1440','900']))
if json.loads(browser('eval','document.querySelector(".result-payment-more").open')): browser('click','.result-payment-more summary')
browser('scroll','up','2000');time.sleep(.8)
take=out/(name+'-take-'+str(int(time.time())))
rec=subprocess.Popen(['node',os.environ['CAPTURE_OBSERVER'],os.environ['CAPTURE_CDP_PORT'],json.loads(browser('eval','location.href')),str(take)],stdout=subprocess.DEVNULL)
for _ in range(100):
 if (take/'ready.json').exists():break
 time.sleep(.1)
else:raise RuntimeError('Recorder failed')
cues=[]
def cue(label): cues.append({'label':label,'time':time.time()})
try:
 cue('actual-unpaid-order');time.sleep(1.5)
 cue('show-payment-options');browser('click','.result-payment-more summary');time.sleep(4)
 browser('screenshot',str(out/(name+'.png')))
 (out/(name+'-result.txt')).write_text(browser('read'))
 cue('end')
finally:rec.send_signal(signal.SIGINT);rec.wait(timeout=10)
(take/'cues.json').write_text(json.dumps({'locale':os.environ.get('CAPTURE_LOCALE','cs'),'mobile':mobile,'cues':cues},indent=2))
duration=encode(take,out/(name+'.mp4'),390 if mobile else 1440,844 if mobile else 900)
subprocess.run(['ffmpeg','-v','error','-y','-i',str(out/(name+'.png')),'-frames:v','1',str(out/(name+'.jpg'))],check=True)
print(f'{name}: {duration:.2f}s actual payment disclosure; no payment initiated')
