"""Actual stock template controls with Futura, and red cinema seat appearance."""
from growth import *
def prepare_template(cs,en,red=False):
 choose(cs,en);ui(label('Styl plánku','Plan style'));ui(label('Podrobné nastavení','Detailed settings'));ui('Roboto');ui('Futura PT',role='menuitem')
 if red:
  ui(label('Všechny popisky','All labels'));ui(label('Židle','Seat'),role='menuitem');wheel_panel();ui('',role='button');fill('[aria-label="'+label('Barva HEX','RGB hex')+'"]','B42332');ui(label('Použít','Apply'))
 ui(label('Zavřít','Close'))
if __name__=='__main__':
 prepare_template('Kinosál 198 míst k sezení · 0 ke stání','Cinema 198 seats · 0 standing',True);checkpoint('cinema-red')
 start('layout-style-templates-cs');cue('cinema');hold(1);end()
 prepare_template('Divadlo 188 míst k sezení · 0 ke stání','Theatre 188 seats · 0 standing');checkpoint('theatre');cue('theatre');hold(1);end();stop()
