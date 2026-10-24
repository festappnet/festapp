"""Real stage drawing and native multi-object/round-table/arc refinement."""
from clean_growth import *
def intro():
 fill('[aria-label="'+label('Hledat objekt','Find object')+'"]',label('Obdélník','Rectangle'));ui(label('Obdélník','Rectangle'))
 start('stage-intro-'+LOCALE);cue('blank-room');hold(.5);end()
 cue('draw-stage');slow_drag(423,129,946,205);end()
 # Actual native styling, omitted from the introductory editorial cues.
 fill('[aria-label="'+label('Velikost písma','Font size')+'"]','100');ui('',role='button',index=0);fill('[aria-label="'+label('Barva HEX','RGB hex')+'"]','80BDF2');ui(label('Použít','Apply'))
 cue('name-stage');fill('[aria-label="'+label('Název','Name')+'"]',label('Pódium','Stage'));clear();hold(.7);end();checkpoint('stage-named')
 ab('click','[aria-label="'+label('Hledat objekt','Find object')+'"]');fill('[aria-label="'+label('Hledat objekt','Find object')+'"]',label('Čára','Line'));ui(label('Čára','Line'))
 cue('surrounding-lines')
 for a,b in [((350,220),(350,890)),((350,890),(1030,890)),((1030,890),(1030,220)),((1030,220),(350,220))]:
  drag(*a,*b);ab('press','Escape');ui(label('Čára','Line'))
 ab('press','Escape');end();checkpoint('stage-outline');stop()
 ab('click','[aria-label="'+label('Hledat objekt','Find object')+'"]');fill('[aria-label="'+label('Hledat objekt','Find object')+'"]','')
def refine():
 start('layout-refine-'+LOCALE);cue('select-middle');point(555,465);drag(690,465,690,465,'Shift');drag(825,465,825,465,'Shift');end();checkpoint('middle-selected')
 cue('delete-middle');ui(label('Smazat','Delete'));end();checkpoint('middle-deleted')
 refine_tail(start_new=False)
def refine_tail(start_new=True):
 if start_new:start('layout-refine-tail-'+LOCALE)
 cue('round-table');drag(62,560,690,465)
 pos=js("Array.from(document.querySelectorAll('[role=button]')).filter(e=>(e.getAttribute('aria-label')||e.textContent).includes('"+label('Táhlo velikosti','Resize handle')+"')).map(e=>{let r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})[0]")
 drag(round(pos['x']),round(pos['y']),round(pos['x'])+12,round(pos['y'])+12);end();checkpoint('round-resized')
 cue('round-chairs');ui(label('Přidat židli','Add one seat'));ui(label('Přidat židli','Add one seat'));clear();end();checkpoint('round-chairs')
 point(695,770)
 cue('arc-reverse');fill('[aria-label="'+label('Zakřivení','Curvature')+'"]','-9');end();checkpoint('arc-negative')
 cue('arc-forward');fill('[aria-label="'+label('Zakřivení','Curvature')+'"]','9');clear();end();checkpoint('arc-positive')
 cue('refined-hall');ab('mouse','move',1435,955);hold(.5);end();checkpoint('refined-hall');stop()
if __name__=='__main__':intro();build_clean();refine()
