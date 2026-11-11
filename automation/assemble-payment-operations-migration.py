#!/usr/bin/env python3
"""Assemble the unified payment-operation forward; no activation or external effects."""
import migration_inputs
import argparse,json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def render():
 m=json.loads(migration_inputs.read_text(ROOT/'automation/payment-operations-migration.json'))
 parts=['-- Unified incoming/outgoing payment operations. No activation or network jobs.']
 for source in m['sources']:
  parts.append('-- SOURCE: '+source+'\n'+migration_inputs.read_text(ROOT/'database/functions'/source).rstrip())
 return ROOT/'supabase/migrations'/m['migration'],'\n\n'.join(parts)+'\n'
def render_readonly_qr():
 sources={'payment_providers/builtin.sql':['bank_payment_provider_internal'],
          'payment_providers/operations.sql':['payment_method_context_internal','get_bank_refund_instructions']}
 parts=['-- Read-only bank refund QR; no payment reservation or financial write.']
 for source,names in sources.items():
  text=(ROOT/'database/functions'/source).read_text()
  for name in names:
   start=text.index('CREATE OR REPLACE FUNCTION public.'+name+'(')
   end=text.index('END $$;',start)+len('END $$;')
   parts.append('-- SOURCE: '+source+'\n'+text[start:end])
 parts.append('REVOKE ALL ON FUNCTION public.get_bank_refund_instructions(jsonb) FROM PUBLIC,anon,service_role;\nGRANT EXECUTE ON FUNCTION public.get_bank_refund_instructions(jsonb) TO authenticated;')
 return ROOT/'supabase/migrations/20261111012000_readonly_bank_refund_qr.sql','\n\n'.join(parts)+'\n'
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');a=p.parse_args();dest,content=render()
 if a.check:
  if not migration_inputs.exists(dest) or hashlib.sha256(migration_inputs.read_bytes(dest)).hexdigest()!='268ec4905adf7b863683260e025b6de4b4fbb735f446cfa83a69dccc3b2fc5fa': raise SystemExit('Installed payment operations migration bytes changed')
  qr_path,qr_content=render_readonly_qr()
  if migration_inputs.read_text(qr_path)!=qr_content: raise SystemExit('Read-only bank QR migration differs from canonical owners')
  from generate_canonical_source_contract import render as source_contract
  source_contract(ROOT,additional_sources=json.loads(migration_inputs.read_text(ROOT/'automation/payment-operations-migration.json'))['sources'])
  print('Payment operations migration matches ordered canonical owners')
 else: raise SystemExit('Installed payment operations migration is immutable; author a scoped forward migration')
