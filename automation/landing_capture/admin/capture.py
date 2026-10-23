import subprocess,json,time,re,os,signal
from pathlib import Path
OUT=Path(os.environ["CAPTURE_OUTPUT"]).resolve();OUT.mkdir(parents=True,exist_ok=True)
AB=os.environ["CAPTURE_BROWSER_WRAPPER"]
def ab(*args):
 p=subprocess.run([AB,*map(str,args)],text=True,capture_output=True)
 if p.returncode:raise RuntimeError(p.stdout+p.stderr)
 return p.stdout.strip()
def js(s):
 r=ab('eval',s)
 try:return json.loads(r)
 except:return r
def hold(s=.55):time.sleep(s)
def ui(label,role=None,index=0):
 selector='[role='+role+']' if role else '[role=button],[role=tab],[role=checkbox],[role=switch],[role=menuitem]'
 exp=f'Array.from(document.querySelectorAll({json.dumps(selector)})).filter(e=>(e.getAttribute("aria-label")||e.textContent).trim()==={json.dumps(label)}).at({index})'
 pos=js(f'(()=>{{const e={exp};if(!e)throw Error("Missing UI control");const r=e.getBoundingClientRect();return {{id:e.id,x:r.x+r.width/2,y:r.y+r.height/2}}}})()')
 ab('mouse','move',round(pos['x']),round(pos['y']));hold(.15);js(f'document.getElementById({json.dumps(pos["id"])}).click()');hold()
def fill(selector,value):ab('fill',selector,value);ab('press','Tab');hold(.35)
def install_pointer():
 js('''(()=>{if(document.querySelector('#take-cursor'))return;const s=document.createElement('style');s.textContent='#take-cursor{position:fixed;width:18px;height:18px;background:#4465a6;border:3px solid white;border-radius:50%;box-shadow:0 2px 8px #25375966;pointer-events:none;z-index:2147483647;transform:translate(-50%,-50%);left:-30px}';document.head.append(s);const c=document.createElement('div');c.id='take-cursor';document.body.append(c);document.addEventListener('pointermove',e=>{c.style.left=e.clientX+'px';c.style.top=e.clientY+'px'},true)})()''')
def start(name):
 info=json.loads(ab('session','info','--json'))['data'];pid=info['pid'];port=None
 for c in subprocess.check_output(['pgrep','-P',str(pid)],text=True).split():
  cmd=subprocess.check_output(['ps','-p',c,'-o','command='],text=True)
  if '--headless=new' not in cmd:continue
  m=re.search(r'--user-data-dir=(\S+)',cmd)
  if m:port=(Path(m.group(1))/'DevToolsActivePort').read_text().splitlines()[0];break
 assert port,'Owned headless Chrome is required'
 directory=OUT/(name+'-'+str(int(time.time())));directory.mkdir();log=open(directory/'record.log','w')
 proc=subprocess.Popen(['node',str(Path(os.environ["PRODUCT_DEMO_SKILL"])/"scripts/capture-cdp.mjs"),port,ab('get','url'),str(directory)],stdout=log,stderr=log,start_new_session=True)
 for _ in range(50):
  if (directory/'ready.json').exists():break
  hold(.1)
 else:raise RuntimeError('recorder unavailable')
 install_pointer();hold(.5)
 (OUT/'active.json').write_text(json.dumps({'pid':proc.pid,'directory':str(directory),'cues':[]}));return directory
def cue(name):
 p=OUT/'active.json';s=json.loads(p.read_text());s['cues'].append({'name':name,'start':time.time()});p.write_text(json.dumps(s))
def end():
 hold(1.6);p=OUT/'active.json';s=json.loads(p.read_text());s['cues'][-1]['end']=time.time();p.write_text(json.dumps(s))
def stop():
 s=json.loads((OUT/'active.json').read_text());os.kill(s['pid'],signal.SIGINT);hold(.5);Path(s['directory'],'cues.json').write_text(json.dumps(s['cues'],indent=2));return s
