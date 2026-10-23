#!/usr/bin/env python3
"""Allow bounded PDF preparation and editor resource loading in document workers."""
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
anchor = '    const worker = await EdgeRuntime.userWorkers.create({\n'
old_option = '''      // PDF attachments share one worker CPU budget across all tickets.
      ...(service_name === "process-email-queue" ? {
        cpuTimeSoftLimitMs: 20_000,
        cpuTimeHardLimitMs: 30_000,
      } : {}), // festapp-email-cpu-budget-v1
'''
previous_option = old_option.replace(
    '// PDF attachments share one worker CPU budget across all tickets.',
    '// Document workers share a CPU budget across PDFs and font/gallery loading.',
).replace('service_name === "process-email-queue"',
          '["process-email-queue", "preview-ticket-layout"].includes(service_name)')
option = previous_option.replace(
    '["process-email-queue", "preview-ticket-layout"]',
    '["process-email-queue", "preview-ticket-layout", "prepare-ticket-batch-document"]',
)
# Accept only the two exact installed policy stanzas when upgrading the router.
source = source.replace(old_option, option).replace(previous_option, option)
if source.count(anchor) != 1:
    raise SystemExit('upstream Function worker contract changed')
if option not in source:
    if 'cpuTimeSoftLimitMs' in source or 'cpuTimeHardLimitMs' in source or 'festapp-email-cpu-budget' in source:
        raise SystemExit('upstream Function CPU budget contract changed')
    source = source.replace(anchor, anchor + option)
path.write_text(source)
