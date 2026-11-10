"""Package an explicit canonical asset list into a reproducible public media kit."""
import json
from pathlib import Path
import sys
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

source, output = map(Path, sys.argv[1:3])
manifest = json.loads(sys.stdin.read())
output.mkdir(parents=True, exist_ok=True)
entries = {}
for name in manifest['files']:
    entries[name] = (source / name).read_bytes()
for name, text in manifest['texts'].items():
    entries[name] = text.encode('utf-8')
for name, data in entries.items():
    (output / name).write_bytes(data)
with ZipFile(output / 'vstupenky-online-loga.zip', 'w', compression=ZIP_DEFLATED) as archive:
    for name, data in sorted(entries.items()):
        info = ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = ZIP_DEFLATED
        info.external_attr = 0o100644 << 16
        archive.writestr(info, data)
