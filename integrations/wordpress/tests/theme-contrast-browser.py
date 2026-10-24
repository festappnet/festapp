"""Check real rendered host-theme foregrounds independently of button fills."""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
B = ['agent-browser', '--config', str(ROOT / '.private/stable-browser.json'),
     '--headed', 'false', '--session', 'festapp-theme-contrast']


def run(*args):
    result = subprocess.run(B + list(args), capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise AssertionError(result.stderr or result.stdout)
    return result.stdout


def js(source):
    return json.loads(run('eval', '--json', source))['data']['result']


def luminance(color):
    values = [float(v) / 255 for v in re.findall(r'[\d.]+', color)[:3]]
    values = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in values]
    return sum(v * weight for v, weight in zip(values, [.2126, .7152, .0722]))


try:
    run('open', 'http://127.0.0.1:59801/form/wordpress-nakup?embed=1')
    run('wait', '--load', 'networkidle')
    for dark in [False, True]:
        theme = dict(fontFamily='Arial', text='rgb(238, 238, 238)' if dark else 'rgb(17, 17, 17)',
                     background='rgb(17, 17, 17)' if dark else 'rgb(255, 255, 255)',
                     primary='rgb(34, 34, 34)' if dark else 'rgb(238, 238, 238)',
                     buttonText='rgb(238, 238, 238)' if dark else 'rgb(17, 17, 17)')
        # Deliberately combine opposite service/host modes. The host owns colors.
        js('(async()=>{const {EmbedTheme}=await import("/src/services/embed_theme.js");'
           f'document.body.classList.toggle("dark-mode",{json.dumps(not dark)});'
           f'new EmbedTheme(window).apply({json.dumps(theme)});return true}})()')
        for width in [1280, 390]:
            run('set', 'viewport', str(width), '844')
            colors = js('Array.from(document.querySelectorAll(".option-price,.btn-clear-selection,.ticket-header,.form-field-hint"),e=>({selector:e.className,color:getComputedStyle(e).color}))')
            assert any(c['selector'] == 'option-price' for c in colors)
            assert any(c['selector'] == 'btn-clear-selection' for c in colors)
            for item in colors:
                a, b = sorted([luminance(item['color']), luminance(theme['background'])])
                ratio = (b + .05) / (a + .05)
                assert ratio >= 4.5, f'{item["selector"]}: {ratio:.2f}:1 in {theme}'
            run('hover', '.btn-clear-selection')
            assert js('getComputedStyle(document.querySelector(".btn-clear-selection")).color') == theme['text']
            print(f'PASS {"dark" if dark else "light"} host at {width}px: prices, labels, clear action and hover >= 4.5:1', flush=True)
finally:
    run('close')
