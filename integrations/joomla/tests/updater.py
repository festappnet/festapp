"""Exercise Joomla's actual updater through a local HTTP mirror of the final feed."""
import json
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
release = json.loads((ROOT / 'dist/CANDIDATE.json').read_text())
for major in [5, 6]:
    container = f'festapp-joomla-20261026-{major}'
    base = f'http://{container}/__joomla_release_fixture'
    feed = ET.parse(ROOT / 'updates/vstupenky-online.xml')
    feed.find('./update/downloads/downloadurl').text = base + '/vstupenky.online.zip'
    with tempfile.TemporaryDirectory(prefix='festapp-joomla-update-') as directory:
        fixture = Path(directory)
        fixture.chmod(0o755)
        feed.write(fixture / 'updates.xml', encoding='utf-8', xml_declaration=True)
        (fixture / 'vstupenky.online.zip').write_bytes((ROOT / release['zip']).read_bytes())
        subprocess.run(['docker','cp',str(fixture)+ '/.',container+':/var/www/html/__joomla_release_fixture'],check=True,capture_output=True)
        try:
            result = subprocess.run(['docker','exec',container,'php','/tests/updater.php',release['version'],release['sha256'],base],check=False,capture_output=True,text=True)
            (ROOT / f'.private/updater-{major}.log').write_text(result.stdout + result.stderr)
            assert result.returncode == 0, f'Native updater failed; see .private/updater-{major}.log'
            receipt = json.loads(result.stdout)
            (ROOT / f'evidence/updater-{major}.json').write_text(json.dumps(receipt,indent=2)+'\n')
        finally:
            subprocess.run(['docker','exec',container,'rm','-rf','/var/www/html/__joomla_release_fixture'],check=True,capture_output=True)
print('PASS actual Joomla update discovery/download/SHA-256/install preserves settings on both CMS versions')
