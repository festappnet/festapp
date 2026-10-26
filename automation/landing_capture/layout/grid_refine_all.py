"""Actual saved mixed baseline, two edge protrusions, maximum seats, all-table wood."""
from grid_take import *
start('grid-refine-all');cue('inner-protrusion');drag(519,312,519,387);end();proof('mixed-inner-protrusion')
cue('outer-protrusion');drag(618,288,618,238);end();proof('mixed-outer-protrusion')
cue('refill-capacity')
for i in range(100):
 state=js('(()=>{const e=[...document.querySelectorAll("[role=button]")].find(e=>(e.getAttribute("aria-label")||e.textContent).trim()==="Přidat židli");return e?{disabled:e.getAttribute("aria-disabled"),id:e.id}:null})()')
 if not state:raise RuntimeError('Missing actual add-seat button')
 if state['disabled']=='true':break
 js('document.getElementById('+json.dumps(state['id'])+').click()');hold(.15)
else:raise RuntimeError('Capacity did not stop')
end();proof('mixed-refilled');(OUT/'refilled-ui-proof.json').write_text(json.dumps({'increments':i,'disabled':state['disabled']}))
cue('copy-wood');ui('Dřevěný');ui('Kopírovat styl');end();ui('Zrušit výběr')
cue('all-five-wood');path_drag([(345,175),(1050,850)]);ui('Vložit styl');end();proof('all-five-wood')
ui('Zrušit výběr');cue('finished');ab('mouse','move',1435,955);end();proof('all-five-final');print(stop())

# Startup: prepare_brand_host.py PACKAGE --clean-stage --transparent-canvas
# --hide-canvas-controls --resume-document SAVED_VERIFIED_MIXED_JSON; build sole
# Flutter task, retain canonical fixtures, open?fixture=resume at1440x960/light/cs.
# Enable Flutter semantics; select grid570,300 before this recipe.
# All5 tables+chairs selected via native marquee then real Paste style.
# Final canonical readback:1grid64/64,2circle+2rect each6;88seats,0collisions.
# All table.style.material and childStyles.seat.material=wood.
# Locale retake: translate semantic label lookup to en; geometry remains native.
# encode_grid_all_wood.py MAIN CLEAR REFINE OUTPUT keeps both chair cues2x,
# native edge gestures1x; source takes remain outside Git for long-form edits.
