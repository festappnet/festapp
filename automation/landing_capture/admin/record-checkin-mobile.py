import subprocess,time,json,pathlib,os
base=pathlib.Path(os.environ['CAPTURE_OUTPUT']);b=os.environ['CAPTURE_BROWSER_WRAPPER']
def js(s): subprocess.run([b,'eval',s],stdout=subprocess.DEVNULL,check=True)
start=time.time();time.sleep(.6);js('window.captureQRVisible=true');time.sleep(1.7)
js("(()=>{const b=document.querySelector('[data-confirm]');const r=b.getBoundingClientRect();movePointer(r.x+r.width/2,r.y+r.height/2)})()")
time.sleep(.55);js("document.querySelector('[data-confirm]').click()");time.sleep(1.65)
js("window.captureQRVisible=false;document.querySelector('[data-next]')?.click()");time.sleep(.7);js('window.captureQRVisible=true');time.sleep(2.2)
(base/'check-in-mobile-cue.json').write_text(json.dumps({'start':start,'end':time.time()}))
