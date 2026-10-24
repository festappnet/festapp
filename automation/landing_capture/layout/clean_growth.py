"""Native clean-stage build: palette drop, held-modifier copies, arc adjustment.
Locale selects genuine UI labels; no geometry is injected during the take.
"""
from growth import *
def path_drag(points, modifier='none'):
 script=Path.home()/'.codex/skills/product-demo-video/scripts/gesture-cdp.mjs'
 subprocess.run(['node',str(script),owned_port(),ab('get','url'),'--path',json.dumps(points),modifier],check=True,stdout=subprocess.DEVNULL);hold(.3)
def clear():ui(label('Zrušit výběr','Clear selection'))
def build_clean():
 start('layout-clean-cs');cue('empty-hall');hold(.5);end();checkpoint('empty-hall')
 cue('first-slow-drag');slow_drag(170,450,420,340);clear();end();checkpoint('first-table')
 rows=[[(x,y) for x in xs] for y,xs in [(340,[420,555,690,825,960]),(465,[960,825,690,555,420]),(590,[420,555,690,825,960])]]
 previous=rows[0][0]
 for index,row in enumerate(rows):
  cue('copy-row-'+str(index+1))
  for target in row:
   if target==previous:continue
   path_drag([previous,target],'Control');clear();previous=target
  end()
 cue('copy-bottom')
 path_drag([previous,(960,750)],'Control');clear()
 path_drag([(420,590),(420,750)],'Control');clear();end();checkpoint('filled-hall')
 cue('arc-insert');path_drag([(62,670),(320,700),(605,735)]);end();checkpoint('arc-inserted')
 cue('arc-adjust');fill('[aria-label="'+label('Zakřivení','Curvature')+'"]','9');hold(.5);end();checkpoint('arc-adjusted')
 cue('arc-move');drag(695,790,695,770);clear();end();checkpoint('arc-moved')
 cue('finished-hall');ab('mouse','move',1435,955);hold(.8);end();checkpoint('hall-complete');stop()
if __name__=='__main__':build_clean()
