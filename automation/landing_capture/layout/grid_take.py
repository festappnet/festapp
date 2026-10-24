"""Real grid table authoring at1440x960; preserve native paint times and UI.
Use CAPTURE_DIR with isolated ab wrapper, own headless session and loaded host.
"""
from capture import *
def path_drag(points):
 script=Path.home()/'.codex/skills/product-demo-video/scripts/gesture-cdp.mjs'
 subprocess.run(['node',str(script),owned_port(),ab('get','url'),'--path',json.dumps(points),'none'],check=True,stdout=subprocess.DEVNULL);hold(.4)
def proof(name):
 value=js('window.captureLayoutDocument')
 (OUT/(name+'.json')).write_text(value if isinstance(value,str) else json.dumps(value))
 ab('screenshot',str(OUT/(name+'.png')))
if __name__=='__main__':
 # Delete the initial stage through real marquee selection and Delete.
 path_drag([(370,120),(1000,240)]);ab('press','Delete');hold(.5)
 start('grid-native');cue('empty');hold(.6);end()
 cue('draw-table');ui('Malovat stůl');path_drag([(500,400),(850,400),(850,650),(700,650)]);end();proof('final-grid-drawn')
 cue('extend-edge');drag(674,412,674,512);end();proof('final-grid-extended')
 cue('shrink-edge');drag(674,512,674,462);end();proof('final-grid-shrunk')

# Continuation used for the recorded take, driven through real Czech controls:
def wood_and_fill():
 fill('[aria-label="Název"]','Stůl 1')
 cue('wood-style');ui('Dřevěný');end();proof('final-grid-wood')
 ui('',role='button',index=0)
 cue('warm-fill');ui('#F59E0B Nastavit barvu #F59E0B');ui('Použít');end();proof('final-grid-warm')
 ui('Zrušit výběr');cue('finished-grid');ab('mouse','move',1435,955);end();proof('final-grid-finished');stop()
def backdrop():
 fill('[aria-label="Hledat objekt"]','Obdélník')
 start('grid-backdrop');cue('backdrop-insert');drag(60,450,465,350);end();proof('backdrop-inserted')
 p=js('Array.from(document.querySelectorAll("[role=button]")).filter(e=>(e.getAttribute("aria-label")||e.textContent).includes("Táhlo velikosti")).map(e=>{let r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})[0]')
 cue('backdrop-resize');drag(round(p['x']),round(p['y']),920,720);end();proof('backdrop-resized')
 ui('Vrstvy');cue('send-back');ui('Přenést dozadu');end();proof('backdrop-behind');ui('Zrušit výběr');fill('[aria-label="Hledat objekt"]','')
 cue('backdrop-finished');ab('mouse','move',1435,955);end();proof('final-backdrop');stop()
