"""Actual editor UI recipe. CAPTURE_LOCALE=cs now; en uses built-in English UI."""
from shoot import *
import sys

LEFT=[(350,388),(495,388),(350,548),(495,548),(495,708)]
RIGHT=[(895,388),(1030,388),(895,548),(1030,548),(895,708)]
def group(points,color):
 point(*points[0])
 for x,y in points[1:]:drag(x,y,x,y,'Shift')
 ui(label('Vlastní vzhled objektu','Custom object appearance'))
 fill('input[aria-label="'+label('Výplň výběru #RRGGBBAA','Selected fill #RRGGBBAA')+'"]',color)
 ui(label('Zrušit výběr','Clear selection'))
def prepare():
 choose('Moderní ples 68 míst k sezení · 0 ke stání','Contemporary ball 68 seats · 0 standing')
 ui(label('Plátno','Canvas'));ui(label('Vzhled podlahy Dlažba','Floor appearance Tiled floor'));ui(label('Bez vzoru','Plain floor'))
 ui(label('Styl plánku','Plan style'));ui(label('Minimalistický','Minimal'));ui(label('Zavřít','Close'))
 group(LEFT+RIGHT,'#80BDF2FF')
 point(350,388);ui(label('Židle','Chairs'),index=1);ui('',role='button')
 fill('input[aria-label="'+label('Barva HEX','RGB hex')+'"]','#253759');ui(label('Použít','Apply'))
 ui(label('Kopírovat styl','Copy style'))
 for x,y in (LEFT+RIGHT)[1:]:drag(x,y,x,y,'Shift')
 ui(label('Vložit styl','Paste style'));ui(label('Zrušit výběr','Clear selection'))
 group(RIGHT,'#FDBA52FF')
 point(700,220);ui('',role='button');fill('input[aria-label="'+label('Barva HEX','RGB hex')+'"]','#80BDF2');ui(label('Použít','Apply'));ui(label('Zrušit výběr','Clear selection'))
def record_build():
 point(495,708);ui(label('Smazat','Delete'));point(895,708);ui(label('Smazat','Delete'))
 point(350,388);ui(label('Kopírovat styl','Copy style'));ui(label('Zrušit výběr','Clear selection'))
 start('layout-build-cs');cue('palette-table');drag(62,560,495,708);end()
 cue('add-chairs');ui(label('Přidat židli','Add one seat'));ui(label('Přidat židli','Add one seat'));ui(label('Vložit styl','Paste style'));end()
 cue('copy-second-table');drag(495,708,895,708,'Control');end()
 cue('complete-hall');ui(label('Zrušit výběr','Clear selection'));ab('mouse','move',1435,955);end();shot('hall-complete');stop()
def record_style():
 assert not js("document.body.innerText.includes('Text ještě není připravený')")
 group(RIGHT,'#80BDF2FF')
 start('layout-style-cs');cue('color-zones');group(RIGHT,'#FDBA52FF');end()
 cue('finished-plan');ab('mouse','move',1435,955);hold(1);end();shot('hall-final');stop()
 (OUT/'vivid-document.json').write_text(js('window.captureLayoutDocument'))
if __name__=='__main__':
 if '--prepare' in sys.argv:prepare()
 record_build();record_style()
