#!/usr/bin/env python3
"""Select exact original definitions for the final paired SQL workload.

This uses the recorded pre-change catalog, never changes the live database and
never writes a historical migration. New functions do not become baseline rules.
"""
from evidence import evidence_dir
import json
import re
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'automation'))
from generate_canonical_source_contract import statements,CREATE,identity
FOLDER=evidence_dir('catalog-before.json')
base=json.loads((FOLDER/'catalog-before.json').read_text())
key=lambda s:s.replace('public.','').replace(' ','')
previous={key(p['signature']):p['definition']+';' for p in base['functions']}
# The before schema must not inherit the new resource index from an earlier
# after round. Baseline catalog membership is checked before generating its drop.
new_index='occasions_unit_start_time_authorization_idx'
assert not any(i['indexname']==new_index for i in base['indexes'])
selected=['DROP INDEX IF EXISTS public.'+new_index+';']
for statement in statements((ROOT/'supabase/migrations/20261021100000_canonical_authorization.sql').read_text()):
    if match:=CREATE.search(statement):
        if definition:=previous.get(key(identity(match[1],match[2],True))):selected.append(definition)
quote=lambda s:'"'+s.replace('"','""')+'"'
altered=set(re.findall(r'ALTER POLICY "([^"]+)" ON "([^"]+)"\."([^"]+)"',
    (ROOT/'database/functions/user_permissions/operation_policies.sql').read_text()))
for policy in base['policies']:
    if (policy['policyname'],policy['schemaname'],policy['tablename']) in altered:
        selected.append('ALTER POLICY '+quote(policy['policyname'])+' ON '+quote(policy['schemaname'])+'.'+quote(policy['tablename'])+' '+
            ' '.join(label+' ('+policy[k]+')' for k,label in [('qual','USING'),('with_check','WITH CHECK')] if policy[k] is not None)+';')
(FOLDER/'baseline.sql').write_text('-- Exact original local definitions for paired A/B only.\n'+'\n'.join(selected)+'\n')
print(f'Baseline: {len(selected)} original definitions and policies')
