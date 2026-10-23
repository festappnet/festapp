"""Existing custom table outline, capacity and table style scenario in English."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'admin'))
from capture import *
from english_ticket import drag

def record():
    ui('Undo');hold(.6)
    install_pointer();ab('mouse','move',1050,370)
    start('layout-grid-en');cue('table-outline-capacity-and-style')
    try:
        ui('Table shape\nRectangle');ui('Custom outline','menuitem');hold(.8)
        drag([[378,394],[378,410],[378,430]])
        ui('Add one seat');ui('Add one seat');hold(.7)
        ui('Timber');hold(1)
        ui('Clear selection');ab('mouse','move',950,850);hold(1)
        end()
    finally:result=stop()
    print(json.dumps({'take':result['directory'],'duration':result['cues'][0]['end']-result['cues'][0]['start']}))
if __name__=='__main__':record()
