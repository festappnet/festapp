#!/usr/bin/env python3
"""Bundle the canonical text engine for the standalone Venue Layout demo."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT / 'automation/blueprint/browser_text_host.ts'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--package-root', type=Path, required=True)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
package = args.package_root.resolve()
if 'vendor' in package.parts or not (package/'example/web/index.html').is_file() or not (package/'pubspec.yaml').read_text().startswith('name: venue_seat_picker\n'):
    raise SystemExit('A canonical Venue Layout source checkout is required')
shared = ROOT/'supabase/functions/_shared'
sources = {ENTRY, ROOT/'supabase/functions/deno.lock', shared/'layout-text-policy.json', shared/'ticket-assets/font-catalog.json'}
sources.update(p for p in shared.glob('layoutText*.ts') if not p.name.endswith('_test.ts'))
sources.update(shared/name for name in ['ticketFonts.ts','ticketPreparedFont.ts','ticketText.ts'])
sources.update(p for folder in ['harfbuzzjs','unicode-properties'] for p in (shared/'vendor'/folder).rglob('*') if p.is_file())
with tempfile.TemporaryDirectory(prefix='venue-text-bundle-') as temporary:
    bundled = Path(temporary)/'layout_text_host.js'
    subprocess.run(['deno','bundle','--platform','browser','--minify','--frozen','--lock='+str(ROOT/'supabase/functions/deno.lock'),str(ENTRY),'--output',str(bundled)],cwd=ROOT,check=True)
    graph = json.loads(subprocess.check_output(['deno','info','--json','--lock='+str(ROOT/'supabase/functions/deno.lock'),str(ENTRY)],cwd=ROOT,text=True))
    pending = [m['npmPackage'] for m in graph['modules'] if m['kind']=='npm']
    packages = set()
    while pending:
        key = pending.pop()
        if key in packages:
            continue
        packages.add(key)
        pending.extend(graph['npmPackages'][key]['dependencies'])
    notices = ['Canonical Festapp whole-text engine browser adapter.\nThird-party licenses follow.\n']
    for key in sorted(packages):
        folder = Path(graph['npmPackages'][key]['localPath'])
        licenses = sorted(p for p in folder.iterdir() if p.is_file() and p.name.lower().startswith(('license','licence','copying','notice')))
        notices.append('\n===== '+key+' =====\n')
        if licenses:
            notices.extend(p.read_text(errors='replace') for p in licenses)
        else:
            notices.append('License: '+str(json.loads((folder/'package.json').read_text()).get('license','See upstream package'))+'\n')
    for folder in ['harfbuzzjs','unicode-properties']:
        for license in sorted((shared/'vendor'/folder).glob('LICENSE*')):
            notices.append('\n===== '+folder+' =====\n'+license.read_text())
    notice_bytes = '\n'.join(notices).encode()
    metadata = {'entry':str(ENTRY.relative_to(ROOT)), 'engineOwner':'Festapp canonical whole-text engine',
                'sources':{str(p.relative_to(ROOT)):sha(p) for p in sorted(sources)}, 'bundleSha256':sha(bundled), 'thirdPartyNoticesSha256':hashlib.sha256(notice_bytes).hexdigest()}
    target = package/'example/web/layout_text_host.js'
    receipt = package/'example/web/layout_text_host.manifest.json'
    notice = package/'example/web/layout_text_host.LICENSE.txt'
    if args.check:
        if not target.exists() or target.read_bytes()!=bundled.read_bytes() or json.loads(receipt.read_text())!=metadata or notice.read_bytes()!=notice_bytes:
            raise SystemExit('Standalone text host bundle differs from canonical sources')
    else:
        target.write_bytes(bundled.read_bytes())
        notice.write_bytes(notice_bytes)
        receipt.write_text(json.dumps(metadata,indent=2)+'\n')
print('Standalone text engine bundle verified' if args.check else 'Standalone text engine bundle generated')
