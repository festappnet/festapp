"""Verify the remaining brand after the documented native CMS cache purge."""
import json
import urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
cases = []
for major in [5, 6]:
    html = urllib.request.urlopen(f'http://127.0.0.1:5991{major}/', timeout=20).read().decode()
    assert html.count('data-festapp-embed-host') == 1
    assert 'https://tickets.festapp.net/form/embedded-synthetic?embed=1' in html
    assert 'https://vstupenky.online/embed.js' not in html
    cases.append({'major':major,'remaining_product_renders':True,'cache_purge':'com_content/com_modules/_system after uninstall'})
(ROOT / 'evidence/uninstall-http.json').write_text(json.dumps(cases, indent=2) + '\n')
print('PASS remaining brand renders independently after native cache purge')
