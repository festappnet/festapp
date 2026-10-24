"""Recreate saved gesture recipe natively before recording matching backdrop ending."""
from grid_take import *
hold(1);js('document.querySelector("flt-semantics-placeholder")?.click()');hold(1);ui('Zavřít šablony');ui('Malovat stůl');path_drag([(470,320),(760,320),(760,470),(640,470)])
for _ in range(12):ui('Přidat židli')
ui('Zrušit výběr');drag(570,320,570,640,'Control');ui('Zrušit výběr');point(570,320);ui('Dřevěný');ui('Kopírovat styl');ui('Zrušit výběr');path_drag([(400,260),(840,850)]);ui('Vložit styl');ui('Zrušit výběr');point(570,320);drag(619,332,619,382);drag(619,382,619,357);ui('Zrušit výběr')
fill('[aria-label="Hledat objekt"]','Obdélník');start('grid-seating-backdrop');cue('backdrop-insert');drag(60,450,420,250);end()
p=js('Array.from(document.querySelectorAll("[role=button]")).filter(e=>(e.getAttribute("aria-label")||e.textContent).includes("Táhlo velikosti")).map(e=>{let r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})[0]')
cue('backdrop-resize');drag(round(p['x']),round(p['y']),850,850);end();ui('Vrstvy');cue('send-back');ui('Přenést dozadu');end();ui('Zrušit výběr');fill('[aria-label="Hledat objekt"]','');cue('finished');ab('mouse','move',1435,955);end();proof('seating-backdrop-final');print(stop())
