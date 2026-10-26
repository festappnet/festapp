"""Bind real installed files to the exact candidate ZIP on both pinned CMS versions."""
import json
import subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'evidence/packages.json').read_text())
cases = []
for major in [5, 6]:
    for filename, info in manifest['packages'].items():
        element = filename.rsplit('-', 1)[0]
        paths = ['modules/' + element + '/' + name for name in info['files']]
        output = subprocess.check_output(['docker','exec',f'festapp-joomla-20261026-{major}','sha256sum',*paths], text=True)
        for line in output.splitlines():
            sha, path = line.split(maxsplit=1)
            relative = path.removeprefix('modules/' + element + '/')
            assert sha == info['files'][relative], (major, filename, relative)
        cases.append({'major':major,'package':filename,'sha256':info['sha256'],'installed_files_match':len(paths)})
(ROOT / 'evidence/installed-files.json').write_text(json.dumps({'cases':cases}, indent=2) + '\n')
print('PASS all installed files match the exact ZIPs on both CMS versions')
