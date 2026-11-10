#!/usr/bin/env python3
"""Assemble the unified payment-operation forward; no activation or external effects."""
import argparse,json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def render():
 m=json.loads((ROOT/'automation/payment-operations-migration.json').read_text())
 parts=['-- Unified incoming/outgoing payment operations. No activation or network jobs.']
 for source in m['sources']:
  parts.append('-- SOURCE: '+source+'\n'+(ROOT/'database/functions'/source).read_text().rstrip())
 return ROOT/'supabase/migrations'/m['migration'],'\n\n'.join(parts)+'\n'
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');a=p.parse_args();dest,content=render()
 if a.check:
  if not dest.exists() or hashlib.sha256(dest.read_bytes()).hexdigest()!='268ec4905adf7b863683260e025b6de4b4fbb735f446cfa83a69dccc3b2fc5fa': raise SystemExit('Installed payment operations migration bytes changed')
  from generate_canonical_source_contract import render as source_contract
  source_contract(ROOT,additional_sources=json.loads((ROOT/'automation/payment-operations-migration.json').read_text())['sources'])
  print('Payment operations migration matches ordered canonical owners')
 else: raise SystemExit('Installed payment operations migration is immutable; author a scoped forward migration')
