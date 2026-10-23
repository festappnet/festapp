"""Record one native table drop, alignment and two added chairs continuously.

Open the genuine editor at1440x960 with its archived outline/stage and exactly
five tables at screen centers (420,340)..(960,340). Prepare this before capture.
Use CAPTURE_OUTPUT and CAPTURE_BROWSER_WRAPPER as for admin/capture.py.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'admin'))
from capture import *
from continuous_form import port
LOCALE=os.environ.get('CAPTURE_LOCALE','cs')
if LOCALE not in ('cs','en'):raise ValueError('Unsupported capture locale')
def label(cs,en):return en if LOCALE=='en' else cs


def drag(points, modifier='none'):
    script = Path(os.environ['PRODUCT_DEMO_SKILL']) / 'scripts/gesture-cdp.mjs'
    subprocess.run(['node', str(script), port(), ab('get', 'url'), '--path',
                    json.dumps(points), modifier], check=True, stdout=subprocess.DEVNULL)
    hold(.3)


def proof(name):
    data = js('window.captureLayoutDocument')
    (OUT / f'{name}.json').write_text(data)
    ab('screenshot', str(OUT / f'{name}.png'))
    return json.loads(data) if isinstance(data,str) else data


def record():
    shot=scenario.contract('layout-build')
    gestures={g['id']:g for g in shot['gestures']}
    initial = json.loads(js('window.captureLayoutDocument'))
    assert sum(n['kind'] == 'table' for n in initial['nodes']) == 5
    assert sum(n['kind'] == 'seat' for n in initial['nodes']) == 30
    proof('prepared-row')
    install_pointer()
    ab('mouse','move',*shot['pointerStart'])
    hold(shot['holds']['before'])
    start('layout-unbroken-'+LOCALE)
    cue('continuous-placement-and-chairs')
    try:
        story_beat('show-prepared-row')
        story_beat('drag-table-from-palette')
        drag(gestures['drag-table-from-palette']['points'])
        hold(shot['holds']['afterDrop'])
        story_beat('align-below-first-table')
        drag(gestures['align-below-first-table']['points'])
        hold(shot['holds']['afterAlignment'])
        story_beat('add-seat-one');ui(label('Přidat židli','Add one seat'));hold(shot['holds']['afterSeat'])
        story_beat('add-seat-two');ui(label('Přidat židli','Add one seat'));hold(shot['holds']['afterSeat'])
        story_beat('clear-and-hold');ui(label('Zrušit výběr','Clear selection'))
        ab('mouse','move',*shot['pointerPark'])
        hold(shot['holds']['result'])
        end()
    finally:
        result=stop()
    finished=proof('finished-six-tables')
    actual={'tables':sum(n['kind']=='table' for n in finished['nodes']),'seats':sum(n['kind']=='seat' for n in finished['nodes'])}
    assert actual=={'tables':6,'seats':38},actual
    if result.get('scenarioReceipt'):
        receipt=result['scenarioReceipt'];receipt['after']=actual;receipt['checks']={'actualReadback':True}
        scenario.write(Path(result['directory'])/'scenario-receipt.json',receipt)


if __name__ == '__main__':
    record()
