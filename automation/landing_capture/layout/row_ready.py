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
    install_pointer()
    ab('mouse', 'move', 170, 450)
    hold(1)
    start('layout-unbroken-cs')
    cue('continuous-placement-and-chairs')
    drag([[170+(500-170)*i/8, 450+(465-450)*i/8] for i in range(9)])
    hold(.5)
    drag([(500, 465), (480, 465), (460, 465), (440, 465), (420, 465)])
    hold(.5)
    ui('Přidat židli'); hold(.4)
    ui('Přidat židli'); hold(.4)
    ui('Zrušit výběr')
    ab('mouse', 'move', 1100, 850)
    hold(1)
    end()
    stop()
    proof('finished-six-tables')


if __name__ == '__main__':
    record()
