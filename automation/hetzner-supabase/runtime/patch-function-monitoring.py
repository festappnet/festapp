#!/usr/bin/env python3
"""Instrument the canonical router without changing worker responses or auth."""
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
marker = "/* festapp-monitoring-v1 */"
if marker not in source:
    anchor = "return await worker.fetch(req)"
    if source.count(anchor) != 1:
        raise SystemExit("upstream Function dispatch contract changed")
    source = source.replace(anchor, "return await monitorEdgeRequest(service_name, req, (request) => worker.fetch(request), envVarsObj, (work) => EdgeRuntime.waitUntil(work)) " + marker)
    source = 'import { monitorEdgeRequest } from "../_shared/monitoring.ts";\n' + source
path.write_text(source)
