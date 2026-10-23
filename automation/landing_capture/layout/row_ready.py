"""Record a prepared five-table row, native table drop, then a second row.

Open the genuine editor at1440x960 with its archived outline/stage and exactly
five tables at screen centers (420,340)..(960,340). Prepare this before capture.
Use CAPTURE_OUTPUT and CAPTURE_BROWSER_WRAPPER as for admin/capture.py.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'admin'))
from capture import *
from continuous_form import port


def drag(points, modifier='none'):
    script = Path(os.environ['PRODUCT_DEMO_SKILL']) / 'scripts/gesture-cdp.mjs'
    subprocess.run(['node', str(script), port(), ab('get', 'url'), '--path',
                    json.dumps(points), modifier], check=True, stdout=subprocess.DEVNULL)
    hold(.3)


def proof(name):
    data = js('window.captureLayoutDocument')
    (OUT / f'{name}.json').write_text(data)
    ab('screenshot', str(OUT / f'{name}.png'))


def record():
    initial = json.loads(js('window.captureLayoutDocument'))
    assert sum(n['kind'] == 'table' for n in initial['nodes']) == 5
    assert sum(n['kind'] == 'seat' for n in initial['nodes']) == 30
    proof('prepared-row')
    start('layout-row-ready-cs')
    cue('ready-row'); hold(.5); end()
    cue('add-table')
    drag([[170+(420-170)*i/6, 450+(465-450)*i/6] for i in range(7)])
    hold(.5); end(); proof('new-table')
    ui('Zrušit výběr')
    cue('complete-second-row')
    for a, b in [(420, 555), (555, 690), (690, 825), (825, 960)]:
        drag([(a, 465), (b, 465)], 'Control')
        ui('Zrušit výběr')
    end(); proof('two-rows')
    cue('finished'); ab('mouse', 'move', 1435, 955); hold(1.4); end()
    stop()


if __name__ == '__main__':
    record()
