"""Real cross-site checkout scroll regression checks in an isolated browser.

Requires both local storefronts and the existing disposable WordPress/backend.
Does not submit orders or select/reserve seats.
"""
import json
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BROWSER = [
    'agent-browser', '--config', str(ROOT / '.private/stable-browser.json'),
    '--headed', 'false', '--session', 'festapp-scroll-regression',
]


def run(*args):
    result = subprocess.run(BROWSER + list(args), text=True, capture_output=True, timeout=35)
    if result.returncode:
        raise AssertionError(result.stderr or result.stdout)
    return result.stdout


def evaluate(script):
    return json.loads(run('eval', '--json', script))['data']['result']


def ref(label):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        matches = [line for line in run('snapshot', '-i').splitlines() if label in line]
        if matches:
            return '@' + re.search(r'ref=(e\d+)', matches[0])[1]
        time.sleep(0.1)
    raise AssertionError('Missing control: ' + label)


def observe():
    evaluate('''window.scrollEvents=[];
        addEventListener('message',e=>{
            if(e.data?.namespace==='festapp-embed' && e.data.type.startsWith('scroll-'))
                scrollEvents.push({type:e.data.type,block:e.data.block,y:scrollY,at:performance.now()});
        }); true''')


def settle():
    run('wait', '--fn', 'scrollEvents.some(e=>e.type==="scroll-request") && performance.now()-scrollEvents.at(-1).at>1000')


def visible(control):
    box = json.loads(run('get', 'box', control, '--json'))['data']
    host = evaluate('({frameTop:document.querySelector("iframe").getBoundingClientRect().top,height:innerHeight,events:scrollEvents})')
    top = host['frameTop'] + box['y']
    assert -2 <= top <= host['height'] - box['height'], f'Target is offscreen at {top:.1f}px'
    return host


def summary(viewport):
    run('set', 'viewport', *map(str, viewport))
    run('open', 'http://localhost:59811/vyzkouset-nakup/')
    run('wait', '--load', 'networkidle')
    observe()
    run('fill', ref('textbox "Email *"'), 'scroll-audit@example.com')
    run('fill', ref('textbox "Name *"'), 'Scroll')
    run('fill', ref('textbox "Surname *"'), 'Audit')
    for _ in range(4):
        height = evaluate('document.querySelector("iframe").clientHeight')
        run('click', ref('button "+ ADD TICKET"'))
        run('wait', '--fn', f'document.querySelector("iframe").clientHeight>{height}')
    run('click', ref('button "CONTINUE"'))
    submit = ref('button "SUBMIT ORDER"')
    settle()
    host = visible(submit)
    requests = [e for e in host['events'] if e['type'] == 'scroll-request']
    assert len(requests) == 1 and requests[0]['block'] == 'end', requests
    saved = next(e['y'] for e in host['events'] if e['type'] == 'scroll-save')
    run('click', ref('button "Close"'))
    run('wait', '--fn', 'scrollEvents.some(e=>e.type==="scroll-restore") && performance.now()-scrollEvents.at(-1).at>400')
    actual = evaluate('scrollY')
    assert abs(actual-saved) <= 2, f'Closing moved the page from {saved} to {actual}'
    print(f'PASS summary reveals Submit and close restores position ({viewport[0]}px)', flush=True)


def validation_and_price():
    run('open', 'http://localhost:59811/vo-block/')
    run('wait', '--load', 'networkidle')
    observe()
    run('click', ref('radio "Synthetic admission'))
    run('click', ref('button "CONTINUE"'))
    settle()
    visible(ref('textbox "Email *"'))
    requests = evaluate('scrollEvents.filter(e=>e.type==="scroll-request")')
    assert len(requests) == 1 and requests[0]['block'] == 'nearest', requests
    # The floating host projection activates the child's existing price widget.
    evaluate('scrollEvents=[]; true')
    run('click', ref('button "1x '))
    settle()
    visible(ref('button "CONTINUE"'))
    before = evaluate('scrollY')
    run('click', ref('button "1x '))
    settle()
    assert abs(evaluate('scrollY')-before) <= 2, 'Already visible action caused another jump'
    print('PASS one validation request and price shortcut scrolls only when needed', flush=True)


def seats():
    run('open', 'http://localhost:59811/vo-global-seats/')
    run('wait', '--load', 'networkidle')
    observe()
    run('click', ref('button "SEAT SELECTION"'))
    ref('button "Zoom in"')
    settle()
    visible(ref('button "CONTINUE"'))
    events = evaluate('scrollEvents')
    saved = next(e['y'] for e in events if e['type'] == 'scroll-save')
    # A real click on the non-focusable map drops focus from Continue. Escape
    # must still work; testing only the initially focused button misses this.
    frame = evaluate('document.querySelector("iframe").getBoundingClientRect().toJSON()')
    run('mouse', 'move', str(round(frame['left'] + 5)), str(round(max(0, frame['top']) + 50)))
    run('mouse', 'down')
    run('mouse', 'up')
    run('press', 'Escape')
    run('wait', '--fn', 'scrollEvents.some(e=>e.type==="scroll-restore") && performance.now()-scrollEvents.at(-1).at>400')
    assert abs(evaluate('scrollY')-saved) <= 2, 'Seat picker did not restore the host position'
    assert len(evaluate('scrollEvents.filter(e=>e.type==="scroll-request")')) == 1
    print('PASS seat picker opens once and Escape restores the original position', flush=True)


def fixed_summary(helper):
    run('set', 'viewport', '390', '844')
    style = '&style=inherit' if helper else ''
    run('open', 'http://localhost:59801/tests/fixtures/embedded-checkout/host.html?mode=fixed&form=wordpress-nakup' + style)
    run('wait', '--load', 'networkidle')
    observe()
    run('fill', ref('textbox "Email *"'), 'scroll-audit@example.com')
    run('fill', ref('textbox "Name *"'), 'Scroll')
    run('fill', ref('textbox "Surname *"'), 'Audit')
    for _ in range(4):
        run('click', ref('button "+ ADD TICKET"'))
    evaluate('window.openedAt=performance.now(); true')
    run('click', ref('button "CONTINUE"'))
    submit = ref('button "SUBMIT ORDER"')
    if helper:
        settle()
    else:
        run('wait', '--fn', 'performance.now()-openedAt>1000')
    host = visible(submit)
    assert evaluate('document.querySelector("iframe").clientHeight') == 800
    requests = [e for e in host['events'] if e['type'] == 'scroll-request']
    assert len(requests) == (1 if helper else 0), requests
    if helper:
        assert requests[0]['block'] == 'nearest'
        saved = next(e['y'] for e in host['events'] if e['type'] == 'scroll-save')
        run('click', ref('button "Close"'))
        run('wait', '--fn', 'scrollEvents.some(e=>e.type==="scroll-restore") && performance.now()-scrollEvents.at(-1).at>400')
        assert abs(evaluate('scrollY')-saved) <= 2
    print('PASS fixed 800px summary ' + ('with helper and exact return' if helper else 'without helper'), flush=True)


def result_transition(viewport, delay):
    run('set', 'viewport', *map(str, viewport))
    run('open', f'http://localhost:59801/tests/fixtures/embedded-checkout/host.html?result=1&delay={delay}')
    run('wait', '--load', 'networkidle')
    observe()
    run('click', ref('button "Review test order"'))
    run('click', ref('button "SUBMIT ORDER"'))
    heading = ref('heading "Your order was accepted!"')
    settle()
    visible(heading)
    top = evaluate('document.querySelector("iframe").getBoundingClientRect().top')
    assert top >= -2, f'Confirmation icon clipped above viewport: iframe top={top}'
    events = evaluate('scrollEvents')
    assert not any(event['type'] == 'scroll-restore' for event in events), events
    assert sum(event['type'] == 'scroll-discard' for event in events) == 1, events
    print(f'PASS confirmation begins at icon, no stale preview restoration ({viewport[0]}px, {delay}ms transport)', flush=True)


try:
    summary((1280, 900))
    summary((390, 844))
    validation_and_price()
    seats()
    fixed_summary(True)
    fixed_summary(False)
    for size in [(1280, 900), (390, 844)]:
        for delay in [0, 700]:
            result_transition(size, delay)
finally:
    run('close')
