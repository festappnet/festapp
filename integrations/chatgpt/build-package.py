#!/usr/bin/env python3
"""Build the public draft ZIP from an exact, credential-free allowlist."""
import argparse
import hashlib
import json
from pathlib import Path
from urllib.parse import urlparse
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
args = parser.parse_args()
root = Path(__file__).parent
plugin = json.loads((root/'plugin.json').read_text())
mcp = json.loads((root/'mcp.json').read_text())
interface = plugin['extensions']['com.openai']['interface']
review = plugin['extensions']['com.openai']['review']
assert plugin['name'] == 'vstupenky-online'
assert interface['displayName'] == 'vstupenky.online'
assert len(interface['displayName']) <= 30 and len(interface['shortDescription']) <= 30
assert len(interface['longDescription']) <= 4000
for key in ['websiteURL','supportURL','privacyPolicyURL','termsOfServiceURL']:
    u = urlparse(interface[key]); assert u.scheme == 'https' and u.hostname == 'vstupenky.online' and not u.username
assert len(review['test_cases']['positive']) == 5
assert len(review['test_cases']['negative']) == 3
assert set(mcp['mcpServers']) == {'festapp'}
server = mcp['mcpServers']['festapp']
assert server['type'] == 'streamable-http' and server['url'] == 'https://mcp.vstupenky.online/mcp'
assert 'headers' not in server
auth = server['extensions']['com.openai']['auth']
assert auth['client'] == {'mode':'provided','clientId':'festapp-chatgpt','tokenEndpointAuthMethod':'none'}
assert auth['baseScopes'] == ['festapp:ticket-layouts:read','festapp:orders:read']
assert not any(key in plugin for key in ['apps','hooks','skills'])
files = ['plugin.json','mcp.json','assets/logo.png']
args.output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(args.output,'w',compression=zipfile.ZIP_DEFLATED) as package:
    for name in files:
        path = root/name
        assert path.is_file() and not path.is_symlink()
        entry = zipfile.ZipInfo(name, (2026,10,27,0,0,0))
        entry.compress_type = zipfile.ZIP_DEFLATED
        entry.external_attr = 0o100644 << 16
        package.writestr(entry,path.read_bytes())
with zipfile.ZipFile(args.output) as package:
    assert package.namelist() == files
print(json.dumps({'file':str(args.output),'files':files,'sha256':hashlib.sha256(args.output.read_bytes()).hexdigest(),
                  'status':'draft; see review/readiness.md for submission gates'}))
