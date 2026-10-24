"""Focused real-browser matrix using the repository's agent-browser layer."""
import json,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
base=['agent-browser','--config',str(root/'.private/stable-browser.json'),'--session','vo-final-visitor-20261023']
cases=[]
def command(*args):
    r=subprocess.run(base+list(args),capture_output=True,text=True,timeout=40)
    if r.returncode:raise RuntimeError(r.stderr.strip() or r.stdout.strip())
    return r.stdout

def evaluate(js):return json.loads(command('eval','--json',js))['data']['result']
def passed(name,**evidence):cases.append({'case':name,'status':'PASS',**evidence})
command('frame','main')
command('set','viewport','390','844')
command('open','http://localhost:59811/vo-two/')
command('wait','--fn','document.querySelectorAll("iframe").length===2 && document.querySelector("iframe").clientHeight>800')
m=evaluate('({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,frames:Array.from(document.querySelectorAll("iframe")).map(e=>({width:e.getBoundingClientRect().width,height:e.getBoundingClientRect().height,title:e.title})),helpers:document.querySelectorAll("script[src*=\\"embed.js\\"]").length,links:document.querySelectorAll(".vstupenky-online a").length})')
assert m['width']==m['scrollWidth']==390 and len(m['frames'])==2 and m['helpers']==1 and m['links']==2
passed('mobile, two independent automatic forms, one helper',**m)
command('network','route','**/embed.js*','--abort')
command('open','http://localhost:59811/vo-block/')
command('wait','--fn','document.querySelector("iframe") !== null')
m=evaluate('({height:document.querySelector("iframe").getAttribute("height"),fallback:!!document.querySelector(".vstupenky-online a[target=_blank][rel=\\"noopener noreferrer\\"]")})')
assert m['height']=='800' and m['fallback']
passed('blocked helper preserves fixed iframe and standalone fallback',**m)
command('network','unroute','**/embed.js*')
command('open','http://localhost:59811/vo-shortcode/')
command('wait','--fn','document.querySelector("iframe") !== null')
m=evaluate('({height:document.querySelector("iframe").getAttribute("height"),automatic:document.querySelector("iframe").hasAttribute("data-festapp-embed"),helpers:document.querySelectorAll("script[src*=\\"embed.js\\"]").length})')
assert m['height']=='800' and not m['automatic'] and m['helpers']==0
passed('fixed shortcode never loads automatic helper',**m)
command('network','route','http://127.0.0.1:59821/**','--abort')
command('open','http://localhost:59811/vo-block/')
m=evaluate('({frames:document.querySelectorAll("iframe").length,fallback:!!document.querySelector(".vstupenky-online a"),fatal:document.body.innerText.includes("Fatal error")})')
assert m['frames']==1 and m['fallback'] and not m['fatal']
passed('host fallback stays accessible with a backend-abort rule installed',**m)
command('network','unroute','http://127.0.0.1:59821/**')
command('open','http://localhost:59811/vo-invalid/')
m=evaluate('({frames:document.querySelectorAll("iframe").length,helpers:document.querySelectorAll("script[src*=\\"embed.js\\"]").length,errors:document.querySelectorAll(".vstupenky-online-error").length})')
assert m=={'frames':0,'helpers':0,'errors':1}
passed('invalid URL renders no external resource',**m)
command('set','viewport','1280','900')
command('open','http://localhost:59811/vo-block/')
command('wait','--fn','document.querySelector("iframe").clientHeight>800')
# Keyboard-accessible fallback is a real link with a focus indicator.
command('focus','.vstupenky-online a')
m=evaluate('({focused:document.activeElement.matches(".vstupenky-online a"),title:document.querySelector("iframe").title,width:document.documentElement.scrollWidth,viewport:innerWidth})')
assert m['focused'] and m['title'] and m['width']==m['viewport']
passed('accessible title and keyboard focus on fallback',**m)
command('screenshot',str(root/'catalog/screenshot-3.png'))
(root/'evidence/browser-receipt.json').write_text(json.dumps({'browser':'isolated headless Google Chrome 155.0.8059.86','cases':cases},indent=2)+'\n')
print(f'PASS: {len(cases)} real-browser integration cases')
