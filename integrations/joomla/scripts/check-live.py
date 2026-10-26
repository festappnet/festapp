#!/usr/bin/env python3
"""Check real Czech service/legal resources with an honest release-probe identity."""
import hashlib
import json
import re
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
origin = 'https://vstupenky.online'
agent = 'Festapp-Joomla-Release-Check/1.0 (+https://github.com/festappnet/festapp)'
expected = {'/login':None, '/terms/':'Poskytovatel systému', '/privacy/':'Kdo odpovídá za vaše údaje', '/privacy/choices/':None, '/support/':'info@festapp.net', '/pro-poradatele':None, '/embed.js':'data-festapp-embed'}
cases = []
for path, marker in expected.items():
    request = urllib.request.Request(origin + path, headers={'User-Agent':agent})
    with urllib.request.urlopen(request, timeout=25) as r:
        raw = r.read()
        body = raw.decode()
        assert r.status == 200
        assert marker is None or marker in body, path + ' lacks expected content'
        if path in ['/terms/','/privacy/','/privacy/choices/','/support/']:
            assert '<h1>' in body and 'markFestappAppReady' not in body, 'SPA fallback is not a legal document'
        title = re.search('<title>(.*?)</title>',body,re.S)
        cases.append({'url':origin+path,'final_url':r.url,'status':r.status,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'title':title[1] if title else None,'expected_content':True})
# Isolate the previous 403 cause; same TLS client/URL, only User-Agent differs.
try:
    with urllib.request.urlopen(origin+'/terms/',timeout=20) as r:
        default = {'status':r.status}
except urllib.error.HTTPError as e:
    default = {'status':e.code,'body':e.read(200).decode(errors='replace').strip()}
diagnosis = ('Cloudflare rejects the default Python-urllib User-Agent with error 1010; descriptive release probe and real browser work. No WAF policy changed.' if default.get('status') == 403 and '1010' in default.get('body','') else 'Default-probe result recorded separately; explicit release identity succeeded. No WAF policy changed.')
receipt = {'checked_at':datetime.now(timezone.utc).isoformat(),'user_agent':agent,'checks':cases,'previous_probe_diagnosis':{'default_python_urllib':default,'same_client_explicit_identity_status':200,'conclusion':diagnosis}}
(ROOT / 'evidence/live-links.json').write_text(json.dumps(receipt,indent=2,ensure_ascii=False)+'\n')
print('PASS 7 live Czech service/legal resources; prior Python-urllib 403 isolated to User-Agent')
