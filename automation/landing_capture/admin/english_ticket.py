"""Retake the existing text/name/admission-QR drag scenario in real English UI.

Prepare the actual ticket editor at 1440x1000 with the silk invitation preset,
English event and sample data. Native gestures are recorded; no state injection.
"""
import sys
from capture import *
from continuous_form import port

def drag(points):
    subprocess.run(['node', str(Path(os.environ['PRODUCT_DEMO_SKILL'])/'scripts/gesture-cdp.mjs'),
                    port(), ab('get','url'), '--path', json.dumps(points)],
                   check=True, stdout=subprocess.DEVNULL)
    hold(.9)

def record():
    js("(()=>{if(document.documentElement.lang!=='en')throw Error('English UI required');const s=document.createElement('style');s.textContent='flt-semantics-host,flt-semantics-host *{pointer-events:none!important}';document.head.append(s)})()")
    install_pointer()
    ab('mouse','move',610,460); hold(.8)
    start('ticket-design-en'); cue('native-title-name-and-qr-drags')
    hold(.8)
    drag([[610,460],[607,450],[604,440],[600,420]])
    drag([[400,710],[420,703],[440,696],[460,690]])
    drag([[1000,710],[1000,700],[1000,685],[1000,670]])
    ab('mouse','move',1100,860); ab('mouse','down'); ab('mouse','up')
    hold(1.5); end(); result=stop()
    ab('screenshot',str(OUT/'ticket-design-finished.png'))
    print(json.dumps({'take':result['directory'],'duration':result['cues'][0]['end']-result['cues'][0]['start']}))

if __name__ == '__main__': record()
