#!/usr/bin/env python3
"""Allow bounded multi-ticket PDF preparation in the canonical email worker."""
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
anchor = '    const worker = await EdgeRuntime.userWorkers.create({\n'
option = '''      // PDF attachments share one worker CPU budget across all tickets.
      ...(service_name === "process-email-queue" ? {
        cpuTimeSoftLimitMs: 20_000,
        cpuTimeHardLimitMs: 30_000,
      } : {}), // festapp-email-cpu-budget-v1
'''
if source.count(anchor) != 1:
    raise SystemExit('upstream Function worker contract changed')
if option not in source:
    if 'cpuTimeSoftLimitMs' in source or 'cpuTimeHardLimitMs' in source or 'festapp-email-cpu-budget' in source:
        raise SystemExit('upstream Function CPU budget contract changed')
    source = source.replace(anchor, anchor + option)
path.write_text(source)
