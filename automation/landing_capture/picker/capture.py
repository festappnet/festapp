"""Record actual Festapp picker. Environment and prerequisites: README.md."""
import json, os, pathlib, signal, subprocess, time
out=pathlib.Path(os.environ['CAPTURE_OUT']).resolve(); out.mkdir(parents=True,exist_ok=True)
wrapper=os.environ['BROWSER_WRAPPER']; locale=os.environ.get('CAPTURE_LOCALE','cs')
seats=[int(value) for value in os.environ.get('CAPTURE_SEAT_IDS','423,424').split(',')]
assert len(seats)==2 and seats[0]!=seats[1]
mobile=os.environ.get('CAPTURE_MOBILE')=='1'; name='seat-select'+('-mobile' if mobile else '')
def browser(*args):
    p=subprocess.run([wrapper,*args],capture_output=True,text=True,check=True)
    return p.stdout.strip()
assert 'HeadlessChrome' in browser('eval','navigator.userAgent')
assert json.loads(browser('session','info','--json'))['data']['runtime']['pageCount']==1
browser('set','viewport',*(['390','844'] if mobile else ['1440','900']))
browser('open',os.environ['CAPTURE_URL'])
browser('eval',f'localStorage.setItem("locale",{json.dumps(locale)});localStorage.setItem("theme","light");location.reload()')
time.sleep(2)
browser('snapshot','-i')
browser('click','.btn-blueprint-select'); time.sleep(1.5)
# The selector and spot IDs come from the real rendered fixture, not an overlay.
browser('snapshot','-i')
url=json.loads(browser('eval','location.href'))
take=out/(name+'-take-'+str(int(time.time())))
rec=subprocess.Popen(['node',os.environ['CAPTURE_OBSERVER'],os.environ['CAPTURE_CDP_PORT'],url,str(take)],stdout=subprocess.DEVNULL)
for _ in range(100):
    if (take/'ready.json').exists(): break
    time.sleep(.1)
else: raise RuntimeError('Recorder did not start')
cues=[]
def cue(label): cues.append({'label':label,'time':time.time()})
try:
    cue('whole-plan'); time.sleep(1.3)
    cue('zoom-and-pan')
    zoom='Přiblížit' if locale=='cs' else 'Zoom in'
    for _ in range(4 if mobile else 2):
        browser('click',f'button[aria-label="{zoom}"]'); time.sleep(.25)
    box=json.loads(json.loads(browser('eval',f"JSON.stringify(document.querySelector('[data-seat-id=\"{seats[0]}\"]').getBoundingClientRect().toJSON())")))
    width,height=(390,844) if mobile else (1440,900)
    dx=(140 if mobile else 500)-(box['x']+box['width']/2)
    dy=(260 if mobile else 250)-(box['y']+box['height']/2)
    sx=max(20,min(width-20,width/2-dx/2)); sy=max(100,min(height-150,height/2-dy/2))
    browser('mouse','move',str(round(sx)),str(round(sy))); browser('mouse','down')
    for i in range(1,9):
        browser('mouse','move',str(round(sx+dx*i/8)),str(round(sy+dy*i/8))); time.sleep(.04)
    browser('mouse','up'); time.sleep(.6)
    cue('select-first-seat'); browser('click',f'[data-seat-id="{seats[0]}"]'); time.sleep(1.3)
    cue('select-adjacent-seat'); browser('click',f'[data-seat-id="{seats[1]}"]'); browser('mouse','move','20','450'); time.sleep(1.5)
    browser('screenshot',str(out/(name+'.png')))
    cue('continue-to-real-form'); browser('click','.blueprint-btn-confirm'); time.sleep(3)
    (out/(name+'-result.txt')).write_text(browser('snapshot','-i'))
    browser('screenshot',str(out/(name+'-result.png')))
    cue('end')
finally:
    rec.send_signal(signal.SIGINT); rec.wait(timeout=10)
(take/'cues.json').write_text(json.dumps({'locale':locale,'mobile':mobile,'cues':cues},indent=2))
from encode import encode
duration=encode(take,out/(name+'.mp4'),390 if mobile else 1440,844 if mobile else 900)
subprocess.run(['ffmpeg','-v','error','-y','-i',str(out/(name+'.png')),'-frames:v','1',str(out/(name+'.jpg'))],check=True)
print(name+': captured and encoded '+str(round(duration,2))+' seconds')
