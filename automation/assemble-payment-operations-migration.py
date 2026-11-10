#!/usr/bin/env python3
"""Assemble the unified payment-operation forward; no activation or external effects."""
import argparse,json
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
  if not dest.exists() or dest.read_text()!=content: raise SystemExit('Payment operations migration is stale')
  print('Payment operations migration matches ordered canonical owners')
 else: dest.write_text(content)
