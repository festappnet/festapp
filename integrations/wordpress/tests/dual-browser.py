"""Real-browser coexistence, independent origins, resize and fallback checks."""
from pathlib import Path
import subprocess,json
R=Path(__file__).resolve().parents[1]
B=['agent-browser','--config',str(R/'.private/stable-browser.json'),'--session','vo-dual-qa']
def run(*a):return subprocess.check_output(B+list(a),text=True)
def js(s):return json.loads(run('eval','--json',s))['data']['result']
cases=[]
run('set','viewport','1280','900');run('open','http://localhost:59811/vo-dual/')
run('wait','--fn','document.querySelectorAll("iframe").length===2 && Array.from(document.querySelectorAll("iframe")).every(f=>f.clientHeight!==800)')
x=js('({helpers:Array.from(document.scripts).filter(s=>new URL(s.src||location.href).pathname==="/embed.js").length,frames:Array.from(document.querySelectorAll("iframe"),f=>({height:f.clientHeight,title:f.title,origin:new URL(f.src).origin})),links:document.querySelectorAll(".vstupenky-online a,.festapp-tickets a").length})');assert x['helpers']==2 and x['links']==2 and len({f['origin'] for f in x['frames']})==2;cases.append({'case':'two products, distinct child origins and independent auto resize','status':'PASS',**x})
run('set','viewport','320','740');run('open','http://localhost:59811/vo-global/');run('wait','--fn','document.querySelector("iframe").clientHeight!==800');x=js('({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,title:document.querySelector("iframe").title})');assert x['width']==x['scrollWidth']==320 and x['title'];cases.append({'case':'global mobile 320 px without horizontal overflow','status':'PASS',**x})
run('screenshot',str(R/'evidence/global-mobile.png'))
run('network','route','**/embed.js*','--abort');run('open','http://localhost:59811/vo-global/');run('focus','.festapp-tickets a');x=js('({height:document.querySelector("iframe").clientHeight,focused:document.activeElement.matches(".festapp-tickets a"),outline:getComputedStyle(document.activeElement).outlineStyle})');assert x['height']==800 and x['focused'] and x['outline']=='solid';cases.append({'case':'blocked helper retains iframe and keyboard fallback','status':'PASS',**x});run('network','unroute','**/embed.js*')
run('open','http://localhost:59811/vo-global-fixed/');x=js('({height:document.querySelector("iframe").height,helpers:Array.from(document.scripts).filter(s=>new URL(s.src||location.href).pathname==="/embed.js").length})');assert x=={'height':'800','helpers':0};cases.append({'case':'global fixed shortcode avoids helper','status':'PASS'})
run('open','http://localhost:59811/vo-global-invalid/');x=js('({frames:document.querySelectorAll("iframe").length,errors:document.querySelectorAll(".festapp-tickets-error").length,leak:document.body.innerText.includes("capability")})');assert x=={'frames':0,'errors':1,'leak':False};cases.append({'case':'opposite brand and personal fragment rejected without leaking input','status':'PASS'})
(R/'evidence/dual-browser-receipt.json').write_text(json.dumps({'browser':'isolated Chrome','theme_body_classes':js('document.body.className'),'cases':cases},indent=2)+'\n');print(f'PASS: {len(cases)} dual-product browser cases')
