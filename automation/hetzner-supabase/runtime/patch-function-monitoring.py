#!/usr/bin/env python3
"""Instrument the canonical router without changing worker responses or auth."""
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
marker = "/* festapp-monitoring-v1 */"
if marker not in source:
    anchor = "return await worker.fetch(req)"
    modern_anchor = "return handleWorkerResponse(await worker.fetch(userReq))"
    if source.count(anchor) == 1 and modern_anchor not in source:
        source = source.replace(anchor, "return await monitorEdgeRequest(service_name, req, (request) => worker.fetch(request), envVarsObj, (work) => EdgeRuntime.waitUntil(work)) " + marker)
    elif source.count(modern_anchor) == 1 and anchor not in source:
        source = source.replace(modern_anchor, "return handleWorkerResponse(await monitorEdgeRequest(service_name, userReq, (request) => worker.fetch(request), envVarsObj, (work) => EdgeRuntime.waitUntil(work))) " + marker)
    else:
        raise SystemExit("upstream Function dispatch contract changed")
    source = 'import { monitorEdgeRequest } from "../_shared/monitoring.ts";\n' + source
path.write_text(source)
