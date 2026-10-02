#!/usr/bin/env python3
"""Include the existing ticket font in the Edge Runtime virtual filesystem."""
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
option = '      staticPatterns: ["/home/deno/functions/_shared/ticket-assets/font.ttf"],'
anchor = '    const worker = await EdgeRuntime.userWorkers.create({\n'
if option not in source:
    if source.count(anchor) != 1 or 'staticPatterns' in source:
        raise SystemExit('upstream Function static-files contract changed')
    source = source.replace(anchor, anchor + option + '\n')
    path.write_text(source)
