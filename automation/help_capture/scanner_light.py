#!/usr/bin/env python3
"""Recapture real CS/EN scanner help states against an owned loopback fixture."""
import argparse, datetime, hashlib, json, os, pathlib, subprocess, tempfile
from urllib.parse import urlparse

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--origin',required=True)
p.add_argument('--scan-code',required=True)
p.add_argument('--occasion',required=True,type=int)
p.add_argument('--ticket',required=True)
a=p.parse_args()
if urlparse(a.origin).hostname not in ('127.0.0.1','localhost'):
    p.error('Only a disposable loopback fixture is permitted')
root=pathlib.Path(__file__).resolve().parents[2]
email=os.environ['HELP_CAPTURE_EMAIL']; password=os.environ['HELP_CAPTURE_PASSWORD']
config=pathlib.Path(tempfile.mkdtemp(prefix='help-light-'))/'browser.json'
config.write_text('{}')
browser=['agent-browser','--config',str(config),'--headed','false','--session','festapp-help-light-recapture']
def run(*args):
    r=subprocess.run(browser+list(args),capture_output=True,text=True)
    if r.returncode: raise RuntimeError('Browser command failed: '+args[0]+'; '+r.stderr[:400])
    return r.stdout

def js(code): return run('eval',code)
def wait(selector): run('wait',selector)
def click(selector): wait(selector); run('click',selector)
def open_page(path): run('open',a.origin.rstrip('/')+path); wait('.scan-shell'); run('wait','--fn',"!document.querySelector('#web-client-startup') || getComputedStyle(document.querySelector('#web-client-startup')).display === 'none'")
def shot(locale,state):
    js("if(document.body.classList.contains('dark-mode')||localStorage.getItem('theme')!=='light')throw Error('Light theme required');if(document.documentElement.scrollWidth>innerWidth)throw Error('Horizontal overflow');'Light capture checked'")
    run('snapshot','-i')
    dest=root/'automation/release/help/media'/locale/'scanner-advanced'/f'{state}.png'
    run('screenshot',str(dest))
    entries.append((f'{locale}/scanner-advanced/{state}',dest))
entries=[]
try:
    open_page('/scan/DEMO-WRONG')
    run('set','viewport','390','844')
    js("(async()=>{const {ThemeService}=await import('/src/services/theme_service.js');ThemeService.setMode('light');return 'Light preference saved'})()")
    for locale in ('cs','en'):
        js("(async()=>{const {LocalizationService}=await import('/src/services/localization_service.js');await LocalizationService.setLocale("+json.dumps(locale)+");return 'Locale selected'})()")
        open_page('/scan/DEMO-WRONG'); wait('.scan-warning'); shot(locale,'invalid-access')
        open_page('/scan/'+a.scan_code); click('[data-mode="manual"]')
        run('fill','[data-code] [name=symbol]','DEMO-NOT-A-TICKET'); click('[data-code] button')
        wait('[data-result-title]'); shot(locale,'not-found')
        # Authenticate the disposable administrator through the actual Auth service.
        js("(async()=>{const {AuthService}=await import('/src/services/auth_service.js');await AuthService.login("+json.dumps(email)+','+json.dumps(password)+");return 'Local fixture authenticated'})()")
        open_page('/scan?occasion='+str(a.occasion))
        wait('.scan-menu'); open_page('/scan/settings'); wait('[data-settings]')
        js("window.scrollTo({top:0,behavior:'instant'});'Top'"); shot(locale,'settings')
        # Display settings are a draft. This capture does not persist a settings change.
        click('[data-mode][value=selected]')
        if js("!!document.querySelector('.scan-answer')").strip()!='true':
            click('.scan-answer-picker summary'); click('[data-add-field]')
        js("document.querySelector('.scan-answer details').open=true;document.querySelector('.scan-answer').scrollIntoView({block:'start',behavior:'instant'});'Field options'")
        shot(locale,'field-options')
        js("document.querySelector('.scan-settings-advanced').open=true;document.querySelector('.scan-settings-advanced').scrollIntoView({block:'start',behavior:'instant'});'Behavior'")
        shot(locale,'advanced')
        run('fill','[data-preview] [name=symbol]',a.ticket); click('[data-preview] button')
        wait('[data-preview-result] [data-result-title]')
        js("document.querySelector('.scan-settings-preview').scrollIntoView({block:'start',behavior:'instant'});'Preview'")
        shot(locale,'preview')
    # Update both canonical provenance registries only after the complete capture succeeds.
    manifest=root/'automation/release/help/media.json'
    walkthrough=root/'docs/development/public-help-walkthrough-2026-10-25.json'
    media=json.loads(manifest.read_text()); doc=json.loads(walkthrough.read_text())
    now=datetime.datetime.now(datetime.timezone.utc).isoformat()
    for ident,dest in entries:
        digest=hashlib.sha256(dest.read_bytes()).hexdigest()
        for entry in media+doc['screenshots']:
            if entry.get('id',entry.get('mediaId'))==ident:
                entry.update(sha256=digest,capturedAt=now,theme='light')
    doc['environment']['captureTheme']='light, explicitly persisted through ThemeService before screenshots'
    doc['replay']={'scanner':'automation/help_capture/scanner_light.py','instructions':'automation/help_capture/README.md'}
    manifest.write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
    walkthrough.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n')
    print('Captured 12 real light-mode screenshots; both provenance registries updated.')
finally:
    run('close')
    config.unlink(missing_ok=True); config.parent.rmdir()
