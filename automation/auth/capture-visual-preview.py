#!/usr/bin/env python3
import json,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[2]
out=root/'docs/plans/google-sign-in-reference-2026-10-01/implementation'
base=['agent-browser','--config','/tmp/festapp-google-browser-config.json','--session','festapp-google-ui-20261002']
def run(*args):
 p=subprocess.run(base+list(args),capture_output=True,text=True)
 if p.returncode: raise RuntimeError(p.stderr or p.stdout)
 return p.stdout
checks=[]
for width,height in [(360,800),(390,844),(768,1024),(1440,1000)]:
 run('set','viewport',str(width),str(height))
 for locale in ['cs','en']:
  for dark in [False,True]:
   for view in ['login','register','unlink','proof','profile','mailbox','mfa','loading','error','cancelled']:
    run('eval',f'window.preview({json.dumps(view)},{json.dumps(locale)},{str(dark).lower()})')
    # Let modal transition and actual font rasterization settle.
    run('eval','new Promise(resolve=>setTimeout(resolve,350))')
    name=f'web-{view}-{locale}-{"dark" if dark else "light"}-{width}.png'
    run('screenshot',str(out/name))
    measure=run('eval','JSON.stringify({overflow:document.documentElement.scrollWidth>innerWidth,buttons:[...document.querySelectorAll(".auth-container button")].filter(e=>e.getBoundingClientRect().width>0).map(e=>({label:e.textContent.trim(),height:e.getBoundingClientRect().height})),dialog:!!document.querySelector("[role=dialog]"),focus:document.activeElement?.tagName})')
    checks.append({'screenshot':name,'measurement':measure})
 print(f'Captured web width {width}',flush=True)
(out/'web-visual-checks.json').write_text(json.dumps(checks,indent=2)+'\n')
