#!/usr/bin/env python3
"""Include ticket fonts and gallery artwork in the Edge Runtime virtual filesystem."""
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
option = '      staticPatterns: ["/home/deno/functions/_shared/ticket-assets/**/*"],'
anchor = '    const worker = await EdgeRuntime.userWorkers.create({\n'
old_option = '      staticPatterns: ["/home/deno/functions/_shared/ticket-assets/font.ttf"],'
source = source.replace(old_option, option)
source = source.replace('      staticPatterns: ["/home/deno/functions/_shared/ticket-assets/*.ttf"],', option)
if option not in source:
    if source.count(anchor) != 1 or 'staticPatterns' in source:
        raise SystemExit('upstream Function static-files contract changed')
    source = source.replace(anchor, anchor + option + '\n')
path.write_text(source)
