"""Read-only production service smoke from the actually installed Czech Joomla ZIP.

Only the disposable Joomla article/settings are changed. No purchase is submitted
and no seat is selected. Browser has no DNS mapping, cookies or test responses.
"""
import importlib.util
import json
import re
import subprocess
from pathlib import Path
from cms import ROOT, AUTH, Fields, request, session

spec = importlib.util.spec_from_file_location('native_publication', ROOT / 'tests/native-publication.py')
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
config = ROOT / '.private/live-browser.json'
config.write_text(json.dumps({'executablePath':'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','contentBoundaries':True}))
BROWSER = ['agent-browser','--config',str(config),'--headed','false','--session','festapp-joomla-live-20261026']


def run(*args):
    result = subprocess.run(BROWSER + list(args),capture_output=True,text=True,timeout=40)
    assert result.returncode == 0, result.stderr or result.stdout
    return result.stdout


def js(code):
    return json.loads(run('eval','--json',code))['data']['result']


def ref(label):
    snapshot = run('snapshot','-i')
    lines = [line for line in snapshot.splitlines() if label in line]
    assert lines, 'Missing expected visible control: '+label
    return '@'+re.search(r'ref=(e\d+)',lines[0])[1]


base = 'http://127.0.0.1:59916'
seed = json.loads((ROOT / '.private/seed-6.json').read_text())
admin = session()
fields = Fields(request(admin,base+'/administrator/')[1]).fields
fields.update(username=AUTH['username'],passwd=AUTH['password'])
assert 'task=logout' in request(admin,base+'/administrator/index.php',fields)[1]
module_id = seed['modules']['mod_vstupenky_online']
form = native.module_form(admin,base,module_id)
original_params = {key:value for key,value in form.fields.items() if key.startswith('jform[params]')}
native.save_form(admin,base,form,'module.cancel',{})
article = native.article_form(admin,base,seed['article'])
original_article = article.fields['jform[articletext]'].strip()
native.save_form(admin,base,article,'article.cancel',{})
checks = []
try:
    for path, heading in [('/terms/','Poskytovatel systému'),('/privacy/','Kdo odpovídá za vaše údaje'),('/support/','Kontakt')]:
        run('open','https://vstupenky.online'+path)
        run('wait','--load','networkidle')
        assert heading in run('snapshot','-i'), 'Public legal/support content missing'
        checks.append({'path':path,'rendered':True})
    native.set_module(admin,base,module_id,{'jform[params][url]':'https://vstupenky.online/form/country_bal_vetrkovice','jform[params][mode]':'auto','jform[params][inherit_style]':'1'})
    native.set_article(admin,base,seed['article'],'<p>Live embed smoke</p>{loadmoduleid '+str(module_id)+'}')
    native.clear_cache(6)
    run('set','viewport','320','740')
    run('open',base+'/index.php?option=com_content&view=article&id='+str(seed['article'])+'&tmpl=component')
    run('wait','--fn','document.querySelector("iframe")?.clientHeight !== 800 && document.querySelector("iframe")?.clientHeight > 240')
    run('wait','--load','networkidle')
    assert 'textbox' in run('snapshot','-i'), 'Live public form did not load'
    observed = js('({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,frameCount:document.querySelectorAll("iframe").length,height:document.querySelector("iframe").clientHeight,src:document.querySelector("iframe").src,helperCount:Array.from(document.scripts).filter(s=>s.src==="https://vstupenky.online/embed.js").length})')
    assert observed['width'] == observed['scrollWidth'] == 320 and observed['frameCount'] == observed['helperCount'] == 1
    run('click',ref('button "SEAT SELECTION"'))
    run('wait','--load','networkidle')
    assert 'button "Zoom in"' in run('snapshot','-i'), 'Live seat map did not appear'
    run('press','Escape')
    assert 'button "Zoom in"' not in run('snapshot','-i'), 'Live seat map did not close'
    checks.append({'installed_module_real_production_form':True,'auto_height_mobile':observed,'seat_map_open_and_escape':True,'orders_submitted':0,'seats_selected':0})
finally:
    native.set_article(admin,base,seed['article'],original_article)
    native.set_module(admin,base,module_id,original_params)
    native.clear_cache(6)
    run('close')
(ROOT / 'evidence/live-browser.json').write_text(json.dumps({'boundary':'actual installed Joomla module -> actual https://vstupenky.online helper/form; no DNS override, mocks, purchase or seat selection','checks':checks},indent=2,ensure_ascii=False)+'\n')
print('PASS actual production legal/support pages and installed Joomla -> live form/mobile/height/seat map (read-only)')
