#!/usr/bin/env python3
"""Collect native numeric counters inside the existing main worker only."""
from pathlib import Path
import sys

def patch(source):
 marker='/* festapp-runtime-resource-metrics-v1 */'
 import_line='import { startRuntimeResourceMetrics } from "../_shared/runtime_resource_metrics.ts";\n'
 addition='startRuntimeResourceMetrics(); '+marker+'\n'
 if marker in source:
  assert source.count(marker)==1 and source.count(import_line)==1 and source.count(addition)==1,'partial resource instrumentation'
  return source
 assert source.count('Deno.serve(')==1 and 'startRuntimeResourceMetrics' not in source,'upstream router contract changed'
 return import_line+source.replace('Deno.serve(',addition+'Deno.serve(',1)

if __name__=='__main__':
 path=Path(sys.argv[1]);path.write_text(patch(path.read_text()))
