"""Record a real accepted admission followed by duplicate rejection on same QR."""
import json,os
from capture import ab,js,start,cue,hold,end,stop,OUT
start('scanner-accept-reject-'+os.environ.get('CAPTURE_LOCALE','cs'));cue('camera');hold(.65)
js('window.captureQRVisible=true');ab('wait','--fn','Boolean(document.querySelector("[data-confirm]"))');cue('valid');hold(1)
js("(()=>{const b=document.querySelector('[data-confirm]');const r=b.getBoundingClientRect();movePointer(r.x+r.width/2,r.y+r.height/2)})()");hold(.3);js("document.querySelector('[data-confirm]').click()");ab('wait','--fn','document.body.innerText.includes("Vstup potvrzen")');cue('accepted');(OUT/'scanner-accepted-state.txt').write_text(js('document.body.innerText'));hold(1.5)
js("window.captureQRVisible=false;document.querySelector('[data-next]')?.click()");cue('next-camera');hold(.65);js('window.captureQRVisible=true');ab('wait','--fn','document.body.innerText.includes("Vstupenka už byla použita")');cue('rejected');hold(1.8);end();take=stop();(OUT/'scanner-final-state.txt').write_text(js('document.body.innerText'));print(take['directory'])
