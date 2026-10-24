"""One native grid table filled to supported capacity, plus mixed ordinary tables."""
from grid_take import *
hold(.8);js('document.querySelector("flt-semantics-placeholder")?.click()');hold(.8);ui('Zavřít šablony')
start('grid-mixed');cue('draw-grid');ui('Malovat stůl');path_drag([(420,300),(720,300),(720,520),(540,520)]);end();proof('mixed-drawn')
cue('fill-native-capacity')
for i in range(150):
 state=js('(()=>{const e=[...document.querySelectorAll("[role=button]")].find(e=>(e.getAttribute("aria-label")||e.textContent).trim()==="Přidat židli");return e?{disabled:e.getAttribute("aria-disabled"),id:e.id}:null})()')
 if not state:raise RuntimeError('Missing actual add-seat button')
 if state['disabled']=='true':break
 js('document.getElementById('+json.dumps(state['id'])+').click()');hold(.12)
else:raise RuntimeError('Capacity did not stop')
end();proof('mixed-capacity');(OUT/'mixed-capacity-ui.json').write_text(json.dumps({'increments':i,'disabled':state['disabled']}))
cue('wood-grid');ui('Dřevěný');end();ui('Zrušit výběr')
cue('round-tables');drag(60,555,960,310);ui('Zrušit výběr');drag(60,555,960,590);ui('Zrušit výběr');end();proof('mixed-round')
cue('rectangle-tables');drag(170,450,440,760);ui('Zrušit výběr');drag(170,450,710,760);ui('Zrušit výběr');end();proof('mixed-all')
cue('finished');ab('mouse','move',1435,955);end();proof('mixed-final');print(stop())

# Final continuation recorded separately: select grid at570,300; fill native
# Název with 'Hlavní stůl', Tab, clear selection (Enter opens next shape selector).
# Search Obdélník; drop60,450->345,215. Drag its actual resize handle to1050,850.
# Vrstvy -> Přenést dozadu; clear/search reset. Preserve transparent canvas.
# Verify saved doc using grid_capacity.dart: exactly onegrid capacity58=actual58,
# two circle+two rect tables,82seats total, layoutCollisions=[]; addbuttondisabled.
# encode_grid_mixed.py takes MAIN BACKDROP CLEAR OUTPUT, all output outside Git.
# CS semantic labels can be translated for en retake; never translate savedraw.
# Final verified edition deliberately excludes the rejected backdrop take:
# its assumed palette coordinate picked a seat; canonical layoutCollisions
# exposed the error. Use mixed-final.json and mixed-verified-proof.json only.
# encode_grid_mixed.py final arguments MAIN CLEAR OUTPUT; no backdrop argument.
