"""Reference hall palette edits; only palette and canvas enter the final crop."""
import sys
from shoot import *
def scout():choose('Skautský ples - původní sál 182 míst k sezení · 0 ke stání','Scout ball - original hall 182 seats · 0 standing')
def main():
 scout();start('layout-build-cs')
 cue('first-palette-drag');drag(170,450,540,315);ui(label('Zrušit výběr','Clear selection'));end()
 cue('second-palette-drag');drag(170,450,540,560);ui(label('Zrušit výběr','Clear selection'));end()
 cue('add-chair');drag(62,450,540,357);ui(label('Zrušit výběr','Clear selection'));end()
 assert not js("document.body.innerText.includes('Text ještě není připravený')")
 cue('finished-edit');ab('mouse','move',1435,955);hold(1);end();shot('scout-edited');stop()
 (OUT/'edited-document.cs.json').write_text(js('window.captureLayoutDocument'))
 if '--build-only' in sys.argv:return
 start('layout-style-cs')
 for cs,en,name in [('Skautský ples - původní sál 182 míst k sezení · 0 ke stání','Scout ball - original hall 182 seats · 0 standing','scout'),('Galaktické kino 84 míst k sezení · 0 ke stání','Galaxy cinema 84 seats · 0 standing','cinema'),('Divadlo 188 míst k sezení · 0 ke stání','Theatre 188 seats · 0 standing','theatre'),('Konference a recepce 102 míst k sezení · 40 ke stání','Conference and reception 102 seats · 40 standing','conference')]:
  choose(cs,en);assert not js("document.body.innerText.includes('Text ještě není připravený')")
  cue(name);ab('mouse','move',1435,955);hold(1.4);end();shot(name)
 stop()
if __name__=='__main__':main()
