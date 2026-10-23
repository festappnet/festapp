"""Select several tables, align them, add chairs and edit curved rows in English."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'admin'))
from capture import *
from continuous_form import port,last_fill
from english_ticket import drag

def click(x,y,shift=False):
    if shift:
        subprocess.run(['node',str(Path(os.environ['PRODUCT_DEMO_SKILL'])/'scripts/gesture-cdp.mjs'),port(),ab('get','url'),'--path',json.dumps([[x,y],[x,y]]),'Shift'],check=True,stdout=subprocess.DEVNULL)
    else:
        ab('mouse','move',x,y);ab('mouse','down');ab('mouse','up')
    hold(.5)

def record():
    ui('Fit plan');hold(.5)
    # Initial offset is authored with a real gesture before recording.
    drag([[487,371],[487,356],[487,341]])
    ui('Clear selection');install_pointer();ab('mouse','move',950,850);hold(.6)
    start('layout-refine-en');cue('multi-select-chairs-and-curved-rows')
    try:
        click(363,371);click(487,341,True)
        ui('Align and distribute');ui('Align bottom');hold(.7);ui('Clear selection')
        click(363,521);ui('Add one seat');hold(.5);ui('Add one seat');hold(.5);ui('Clear selection')
        drag([[62,790],[300,740],[500,700],[700,650]])
        ui('Remove row');hold(.6)
        ui('Clear selection');ab('mouse','move',950,850);hold(1.2)
        end()
    finally: result=stop()
    print(json.dumps({'take':result['directory'],'duration':result['cues'][0].get('end',0)-result['cues'][0]['start']}))
if __name__=='__main__':record()
