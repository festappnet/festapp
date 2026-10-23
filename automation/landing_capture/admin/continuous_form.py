"""Record four paid dinners and a text question in one uninterrupted take.

Use a fresh disposable form with one ticket/product group and no demo fields.
CAPTURE_OUTPUT, CAPTURE_BROWSER_WRAPPER and PRODUCT_DEMO_SKILL select owned
runtime paths. Open its editor at 1000x1000 and select the ticket before running.
The selected ticket's Add product type button must be visible before start.
"""
import sys
from capture import *


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
    start('form-continuous-cs')
    cue('continuous-dinners-and-text')
    hold(1.5)
    ui('Přidat typ produktu')
    if js("Array.from(document.querySelectorAll('[role=button]')).some(e=>(e.getAttribute('aria-label')||e.textContent).trim()==='Vytvořit nový typ produktu')"):
        ui('Vytvořit nový typ produktu')
    last_fill('input[aria-label="Název typu produktu"]', 'Večeře')
    for title, price in [('Kuřecí večeře', '180'), ('Vegetariánská večeře', '160'),
                         ('Veganská večeře', '160'), ('Bezlepková večeře', '180')]:
        ui('Přidat produkt', index=-1)
        last_fill('input[aria-label="Název"]', title)
        last_fill('input[aria-label="Cena"]', price)
        hold(.7)
    wheel(350)
    ab('mouse', 'move', 885, 850)
    ab('screenshot', str(OUT / 'four-dinners.png'))
    hold(3)
    ui('Přidat pole')
    hold(.7)
    ui('Text')
    hold(.8)
    # New card sits at the end of the real editor scroll content.
    ab('mouse', 'move', 500, 790)
    ab('mouse', 'down')
    ab('mouse', 'up')
    hold(.5)
    # Flutter merges the card's title/answer semantics into one oversized input.
    # Focus the actual painted title, then send native keyboard events.
    top = js("document.querySelector('input[aria-label^=\"Text\"]').getBoundingClientRect().y")
    ab('mouse', 'move', 400, round(top + 65))
    ab('mouse', 'down')
    ab('mouse', 'up')
    hold(.2)
    ab('press', 'Meta+a' if sys.platform == 'darwin' else 'Control+a')
    hold(.1)
    ab('keyboard', 'type', 'Poznámka pro pořadatele')
    ab('press', 'Tab')
    ab('mouse', 'move', 885, 850)
    hold(3)
    end()
    result = stop()
    ab('screenshot', str(OUT / 'finished-question.png'))
    print(json.dumps(dict(take=result['directory'], duration=result['cues'][0]['end']-result['cues'][0]['start'])))


if __name__ == '__main__':
    record()
