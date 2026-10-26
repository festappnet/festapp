"""Isolated headless installed-module flow against the existing disposable service."""
import json
import re
import subprocess
import time
from pathlib import Path
from cms import Fields, request, session, AUTH

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / '.private/browser.json'
CONFIG.write_text(json.dumps({'executablePath':'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','ignoreHttpsErrors':True,'args':'--host-resolver-rules=MAP vstupenky.online 127.0.0.1:59803'}))
BROWSER = ['agent-browser','--config',str(CONFIG),'--headed','false','--session','festapp-joomla-20261026']


def run(*args):
    r = subprocess.run(BROWSER + list(args), text=True, capture_output=True, timeout=40)
    if r.returncode:
        raise AssertionError(r.stderr or r.stdout)
    return r.stdout


def js(code):
    return json.loads(run('eval','--json',code))['data']['result']


def ref(label):
    for _ in range(30):
        lines = [line for line in run('snapshot','-i').splitlines() if label in line]
        if lines:
            return '@'+re.search(r'ref=(e\d+)', lines[0])[1]
        time.sleep(.2)
    raise AssertionError('Missing control: '+label)


def edit(params):
    admin = session()
    base = 'http://127.0.0.1:59916'
    seed = json.loads((ROOT / '.private/seed-6.json').read_text())
    fields = Fields(request(admin, base+'/administrator/')[1]).fields
    fields.update(username=AUTH['username'],passwd=AUTH['password'])
    request(admin,base+'/administrator/index.php',fields)
    url = base+'/administrator/index.php?option=com_modules&task=module.edit&id='+str(seed['modules']['mod_vstupenky_online'])
    form = Fields(request(admin,url)[1])
    fields = form.fields
    fields.update({'task':'module.save', **{'jform[params]['+key+']':str(value) for key,value in params.items()}})
    request(admin,base+form.action,fields)


cases = []
try:
    run('open','about:blank')
    # Block the untested international remote service before navigating any embed.
    run('network','route','https://tickets.festapp.net/**','--abort')
    run('set','viewport','320','740')
    run('open','http://127.0.0.1:59916/')
    run('wait','--fn','Array.from(document.querySelectorAll(".mod_vstupenky_online iframe")).every(f=>f.clientHeight!==800)')
    ref('textbox "Email *"')
    observed = js('({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,heights:Array.from(document.querySelectorAll(".mod_vstupenky_online iframe"),f=>f.clientHeight),helpers:Array.from(document.scripts).filter(s=>s.src==="https://vstupenky.online/embed.js").length})')
    assert observed['width'] == observed['scrollWidth'] == 320 and observed['helpers'] == 1
    cases.append({'case':'320px, real form, article/position auto height, one helper', **observed})
    run('press','Tab')
    assert js('document.activeElement !== document.body'), 'Keyboard focus'
    edit({'url':'https://vstupenky.online/form/embedded-seats'})
    run('open','http://127.0.0.1:59916/')
    run('click',ref('button "SEAT SELECTION"'))
    ref('button "Zoom in"')
    assert 'button "Zoom in"' in run('snapshot','-i'), 'Seat map controls did not appear'
    run('press','Escape')
    assert 'button "Zoom in"' not in run('snapshot','-i'), 'Seat map controls remain after Escape'
    ref('button "SEAT SELECTION"')
    cases.append({'case':'real seat selector opens and closes with Escape'})
    run('network','route','**/embed.js*','--abort')
    run('open','http://127.0.0.1:59916/')
    assert js('document.querySelector(".mod_vstupenky_online iframe").clientHeight') == 800
    run('focus','.mod_vstupenky_online a')
    assert js('document.activeElement.matches(".mod_vstupenky_online a") && document.activeElement.target==="_blank"')
    expected = js('document.activeElement.href')
    assert expected in ['https://vstupenky.online/form/embedded-synthetic','https://vstupenky.online/form/embedded-seats']
    before_tabs = json.loads(run('tab','--json'))['data']['tabs']
    run('press','Enter')
    for _ in range(30):
        after_tabs = json.loads(run('tab','--json'))['data']['tabs']
        if len(after_tabs) > len(before_tabs) and any(t['url'] == expected for t in after_tabs):
            break
        time.sleep(.2)
    else:
        raise AssertionError('Keyboard fallback did not open the expected URL in a new tab')
    cases.append({'case':'blocked helper preserves 800px iframe and keyboard new-tab fallback'})
    run('network','unroute','**/embed.js*')
    edit({'url':'https://vstupenky.online/form/embedded-synthetic'})
except Exception:
    (ROOT / '.private/browser-snapshot.txt').write_text(run('snapshot','-i'))
    (ROOT / '.private/browser-console.txt').write_text(run('console'))
    (ROOT / '.private/browser-requests.txt').write_text(run('network','requests'))
    raise
finally:
    edit({'url':'https://vstupenky.online/form/embedded-synthetic'})
    run('close')
(ROOT / 'evidence/browser.json').write_text(json.dumps({'boundary':'vstupenky.online DNS routed only in isolated browser to existing disposable HTTPS fixture on 59803 and backend on 59821; international remote requests blocked; no purchase submitted','cases':cases},indent=2)+'\n')
print('PASS mobile/keyboard/auto-height/seat-selector/blocked-helper browser checks')
