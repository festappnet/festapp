from capture import *
LOCALE=os.environ.get('CAPTURE_LOCALE','cs')
def label(cs,en):return cs if LOCALE=='cs' else en
def choose(cs,en):
 ui(label('Šablony sálů','Choose template'));ui(label(cs,en));ui(label('Použít šablonu','Replace plan'));hold(1)
def shot(name):ab('mouse','move',1435,955);hold(.4);ab('screenshot',str(OUT/(name+'.png')))
def build():
 choose('Moderní ples 68 míst k sezení · 0 ke stání','Contemporary ball 68 seats · 0 standing')
 point(495,708);ui(label('Smazat','Delete'));point(895,708);ui(label('Smazat','Delete'));point(700,820)
 start('layout-build-cs');cue('palette-table');drag(62,560,495,708);end();cue('add-chairs');ui(label('Přidat židli','Add one seat'));ui(label('Přidat židli','Add one seat'));end()
 cue('copy-second-table');drag(495,708,895,708,'Control');ui(label('Přidat židli','Add one seat'));ui(label('Přidat židli','Add one seat'));end()
 assert not js("document.body.innerText.includes('Text ještě není připravený')")
 cue('complete-hall');ui(label('Zrušit výběr','Clear selection'));ui(label('Celý plánek','Fit plan'));ab('mouse','move',1435,955);hold(2);end();shot('hall-complete');stop()
if __name__=='__main__':build()
def style():
 point(700,820)
 start('layout-style-cs');cue('group-style');point(495,708);drag(895,708,895,708,'Shift');ui(label('Vlastní vzhled objektu','Custom object appearance'));ui(label('Teplý','Warm'));ui(label('Zrušit výběr','Clear selection'));hold(1);end();shot('group-style')
 for cs,en,name in [('Kinosál 198 míst k sezení · 0 ke stání','Cinema 198 seats · 0 standing','cinema'),('Divadlo 188 míst k sezení · 0 ke stání','Theatre 188 seats · 0 standing','theatre'),('Konference a recepce 102 míst k sezení · 40 ke stání','Conference and reception 102 seats · 40 standing','conference')]:
  cue(name);choose(cs,en);shot(name);end()
 stop()
