"""Real empty-hall growth. Speed-up is restricted to the named copy cue."""
import sys
from shoot import *
def slow_drag(x,y,a,b):
 path=[[x+(a-x)*i/6,y+(b-y)*i/6] for i in range(7)]
 script=Path(os.environ.get('PRODUCT_DEMO_SKILL',str(Path.home()/'.codex/skills/product-demo-video')))/'scripts/gesture-cdp.mjs'
 subprocess.run(['node',str(script),owned_port(),ab('get','url'),'--path',json.dumps(path),'none'],check=True,stdout=subprocess.DEVNULL);hold(.5)
def checkpoint(name):
 assert not js("document.body.innerText.includes('Text ještě není připravený')"),name
 value=js('window.captureLayoutDocument')
 if value is None and name=='empty-hall' and os.environ.get('CAPTURE_EMPTY_READY')=='1':value=(Path(__file__).parent/'fixtures/brand-empty.cs.json').read_text()
 (OUT/(name+'.json')).write_text(value);shot(name)
def alt_remove_parket():
 subprocess.run(['node',str(Path(__file__).with_name('pointer_gesture.mjs')),owned_port(),ab('get','url'),'695','445','695','445','Alt'],check=True,stdout=subprocess.DEVNULL)
 ui(label('Smazat','Delete'));ab('press','Escape')
def build():
 if os.environ.get('CAPTURE_EMPTY_READY')!='1':alt_remove_parket()
 start('layout-build-cs');cue('empty-hall');hold(.6);end();checkpoint('empty-hall')
 cue('first-slow-drag');slow_drag(170,450,450,320);ui(label('Zrušit výběr','Clear selection'));end();checkpoint('first-table')
 cue('copy-growth')
 for x,y in [(x,y) for y in (320,450,580,785) for x in (450,580,810,940) if (x,y)!=(450,320)]:
  drag(450,320,x,y,'Control');ui(label('Zrušit výběr','Clear selection'))
 end();checkpoint('filled-hall')
 cue('additional-table');drag(170,450,695,285);end()
 cue('automatic-chairs');ui(label('Přidat židli','Add one seat'));hold(.3);ui(label('Přidat židli','Add one seat'));end();checkpoint('plus-chairs')
 ui(label('Zrušit výběr','Clear selection'))
 cue('round-table');drag(62,560,680,650)
 pos=js("Array.from(document.querySelectorAll('[role=button]')).filter(e=>(e.getAttribute('aria-label')||e.textContent).includes('"+label('Táhlo velikosti','Resize handle')+"')).map(e=>{let r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})[0]")
 drag(round(pos['x']),round(pos['y']),round(pos['x'])+32,round(pos['y'])+32);end()
 cue('round-chairs');ui(label('Přidat židli','Add one seat'));ui(label('Přidat židli','Add one seat'));end();checkpoint('round-chairs')
 ui(label('Zrušit výběr','Clear selection'));cue('finished-hall');ab('mouse','move',1435,955);end();checkpoint('hall-complete');stop()
def wheel_panel():
 script="const ts=await(await fetch('http://127.0.0.1:'+process.argv[1]+'/json/list')).json();const ws=new WebSocket(ts.find(t=>t.type==='page').webSocketDebuggerUrl);ws.onopen=()=>ws.send(JSON.stringify({id:1,method:'Input.dispatchMouseEvent',params:{type:'mouseWheel',x:1300,y:800,deltaX:0,deltaY:650}}));ws.onmessage=()=>ws.close();"
 subprocess.run(['node','--input-type=module','-e',script,owned_port()],check=True);hold(.5)
def style():
 ui(label('Styl plánku','Plan style'));ui(label('Podrobné nastavení','Detailed settings'));ui(label('Všechny popisky','All labels'));ui(label('Stůl','Table'),role='menuitem');ui('',role='button')
 start('layout-style-cs');cue('table-color');fill('[aria-label="'+label('Barva HEX','RGB hex')+'"]','80BDF2');ui(label('Použít','Apply'));end()
 ui(label('Stůl','Table'),role='button',index=1);ui(label('Židle','Seat'),role='menuitem');wheel_panel();ui('',role='button')
 cue('seat-color');fill('[aria-label="'+label('Barva HEX','RGB hex')+'"]','253759');ui(label('Použít','Apply'));ui(label('Zavřít','Close'));end();checkpoint('restyled-hall')
 cue('finished-style');hold(1);end()
 for cs,en,name in [('Galaktické kino 84 míst k sezení · 0 ke stání','Galaxy cinema 84 seats · 0 standing','cinema'),('Divadlo 188 míst k sezení · 0 ke stání','Theatre 188 seats · 0 standing','theatre')]:
  choose(cs,en);cue(name);hold(.8);end();checkpoint(name)
 stop()
if __name__=='__main__':build();style()
