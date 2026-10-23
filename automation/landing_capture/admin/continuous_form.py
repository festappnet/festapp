"""Record three paid dinners and a note question in one uninterrupted take.

Use a fresh disposable form with one ticket/product group and no demo fields.
CAPTURE_OUTPUT, CAPTURE_BROWSER_WRAPPER and PRODUCT_DEMO_SKILL select owned
runtime paths. Open its editor at 1000x1000 and select the ticket before running.
The selected ticket's Add product type button must be visible before start.
"""
import sys
import capture as capture_runtime
from capture import *
LOCALE = os.environ.get('CAPTURE_LOCALE', 'cs')
if LOCALE not in ('cs','en'): raise ValueError('Unsupported capture locale')
LABELS = {'Přidat typ produktu':'Add Product Type','Vytvořit nový typ produktu':'Create New Product Type','Název typu produktu':'Product Type Title','Přidat produkt':'Add Product','Název':'Title','Cena':'Price','Přidat pole':'Add Field','Poznámka':'Note'}
def label(value): return LABELS.get(value,value) if LOCALE == 'en' else value
_original_ui = ui
def ui(value, *args, **kwargs): return _original_ui(label(value), *args, **kwargs)


_raw_ab = ab


def ab(*args):
    if len(args) == 4 and args[:2] == ('mouse', 'move'):
        destination = [float(args[2]), float(args[3])]
        origin = json.loads(_raw_ab('eval', "(()=>{const e=document.querySelector('#take-cursor');return e?[parseFloat(e.style.left)||0,parseFloat(e.style.top)||0]:null})()"))
        if origin and origin[0] >= 0:
            script = """
const [port,url,points]=process.argv.slice(1), [a,b]=JSON.parse(points);
const pages=await(await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const page=pages.find(p=>p.type==='page'&&p.url===url);
if(!page)throw Error('Owned capture page missing');
const ws=new WebSocket(page.webSocketDebuggerUrl);
await new Promise(r=>ws.addEventListener('open',r,{once:true}));
for(let i=1;i<=18;i++){
 ws.send(JSON.stringify({id:i,method:'Input.dispatchMouseEvent',params:{type:'mouseMoved',x:a[0]+(b[0]-a[0])*i/18,y:a[1]+(b[1]-a[1])*i/18}}));
 await new Promise(r=>setTimeout(r,20));
}
await new Promise(r=>setTimeout(r,80));ws.close();
"""
            subprocess.run(['node', '--input-type=module', '-e', script, port(),
                            _raw_ab('get', 'url'), json.dumps([origin, destination])], check=True)
            return ''
    return _raw_ab(*args)


# Common UI helpers use the same continuous pointer path.
capture_runtime.ab = ab


def port():
    info = json.loads(ab('session', 'info', '--json'))['data']
    assert info['runtime']['pageCount'] == 1
    for child in subprocess.check_output(['pgrep', '-P', str(info['pid'])], text=True).split():
        command = subprocess.check_output(['ps', '-p', child, '-o', 'command='], text=True)
        if '--headless=new' not in command:
            continue
        profile = re.search(r'--user-data-dir=(\S+)', command)
        if profile:
            return (Path(profile.group(1)) / 'DevToolsActivePort').read_text().splitlines()[0]
    raise RuntimeError('Owned headless browser required')


def wheel(delta):
    script = """
const [port,url,delta]=process.argv.slice(1);
const pages=await(await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const page=pages.find(p=>p.type==='page'&&p.url===url);
if(!page)throw Error('Owned capture page missing');
const ws=new WebSocket(page.webSocketDebuggerUrl);
await new Promise(r=>ws.addEventListener('open',r,{once:true}));
for(let i=0;i<24;i++){
 ws.send(JSON.stringify({id:i+1,method:'Input.dispatchMouseEvent',params:{type:'mouseWheel',x:600,y:700,deltaX:0,deltaY:Number(delta)/24}}));
 await new Promise(r=>setTimeout(r,22));
}
await new Promise(r=>setTimeout(r,250));ws.close();
"""
    subprocess.run(['node', '--input-type=module', '-e', script, port(), ab('get', 'url'), str(delta)], check=True)
    hold(.25)


def last_fill(selector, value):
    position = js(f'''(()=>{{
document.querySelectorAll('[data-take-input]').forEach(e=>e.removeAttribute('data-take-input'));
const e=Array.from(document.querySelectorAll({json.dumps(selector)})).at(-1);
if(!e)throw Error('Missing recorded input');
e.setAttribute('data-take-input','active');
const r=e.getBoundingClientRect();return {{x:r.x+r.width/2,y:r.y+r.height/2}};
}})()''')
    if position['y'] > 865:
        wheel(position['y'] - 760)
        position = js("(()=>{const r=document.querySelector('[data-take-input]').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()")
    ab('mouse', 'move', round(position['x']), round(position['y']))
    fill('input[data-take-input="active"]', value)
    hold(.5)
    # Reacquire after Flutter paints the new row's semantics. Some builds
    # replace its first input during focus, losing the first editing event.
    js(f'''(()=>{{
document.querySelectorAll('[data-take-input]').forEach(e=>e.removeAttribute('data-take-input'));
Array.from(document.querySelectorAll({json.dumps(selector)})).at(-1).setAttribute('data-take-input','active');
}})()''')
    fill('input[data-take-input="active"]', value)
    hold(.5)


def record():
    # Retain accessible inspection while routing native scroll to Flutter.
    js("(()=>{const s=document.createElement('style');s.textContent='flt-semantics-host,flt-semantics-host *{pointer-events:none!important}';document.head.append(s)})()")
    install_pointer()
    ab('mouse', 'move', 600, 700)
    hold(1)
    start('form-unbroken-' + LOCALE)
    cue('continuous-dinners-and-note')
    try:
        story_beat('show-ticket');story_beat('add-dinner-group')
        ui('Přidat typ produktu')
        if js("Array.from(document.querySelectorAll('[role=button]')).some(e=>(e.getAttribute('aria-label')||e.textContent).trim()===" + json.dumps(label('Vytvořit nový typ produktu')) + ")"):
            ui('Vytvořit nový typ produktu')
        last_fill('input[aria-label=' + json.dumps(label('Název typu produktu')) + ']', scenario.text(LOCALE)['dinnerGroup'])
        for step,title,price in zip(('add-chicken','add-vegetarian','add-vegan'),scenario.text(LOCALE)['dinners'],scenario.contract('form-build')['data']['dinnerPrices']):
            story_beat(step)
            ui('Přidat produkt', index=-1)
            last_fill('input[aria-label=' + json.dumps(label('Název')) + ']', title)
            last_fill('input[aria-label=' + json.dumps(label('Cena')) + ']', str(price))
            hold(.7)
        story_beat('scroll-to-add-field');wheel(350)
        story_beat('show-three-options')
        ab('mouse', 'move', 885, 850)
        ab('screenshot', str(OUT / 'three-dinners.png'))
        hold(2)
        story_beat('add-note');ui('Přidat pole')
        hold(.5)
        ui('Poznámka')
        ab('mouse', 'move', 885, 850)
        hold(2)
        story_beat('hold-question');end()
    finally:
        result = stop()
    ab('screenshot', str(OUT / 'finished-question.png'))
    print(json.dumps(dict(take=result['directory'], duration=result['cues'][0]['end']-result['cues'][0]['start'])))


if __name__ == '__main__':
    record()
