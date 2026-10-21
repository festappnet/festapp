#!/usr/bin/env python3
"""Preserve effective policy expressions while delegating inspected domain checks.

The captured, task-owned pre-change catalog is evidence, not a runtime ACL catalog.
ALTER POLICY deliberately retains policy command, roles and permissiveness.
"""
import argparse,json,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'automation'))
from generate_canonical_source_contract import statements
TARGET=ROOT/'database/functions/user_permissions/operation_policies.sql'
BASE=ROOT/'docs/plans/evidence/canonical-authorization-20261020/catalog-before.json'
COMMON={'get_is_editor_order_on_occasion':'can_write_orders',
        'get_is_editor_order_view_on_occasion':'can_read_orders'}
DOMAINS={
 ('public','events'):{'get_is_editor_on_occasion':'can_write_schedule','get_is_editor_view_on_occasion':'can_read_schedule_editor'},
 ('public','news'):{'get_is_editor_on_occasion':'can_write_news'},
 ('public','information'):{'get_is_editor_on_occasion':'can_write_information','get_is_editor_view_on_occasion':'can_read_information_editor_bundle'},
}
def rewrite(sql,schema,table):
    if sql is None:return None
    for old,new in {**COMMON,**DOMAINS.get((schema,table),{})}.items():
        sql=re.sub(r'\b'+old+r'(?=\s*\()',new,sql)
    return sql

def render():
    quote=lambda s:'"'+s.replace('"','""')+'"'
    result=['-- Effective pre-change RLS expressions, delegated to canonical operation owners.']
    for p in json.loads(BASE.read_text())['policies']:
        old=[p['qual'],p['with_check']]
        new=[rewrite(v,p['schemaname'],p['tablename']) for v in old]
        if (p['schemaname'],p['tablename'],p['policyname'])==('public','occasions','data_security_occasion_context_read'):
            new[0]='public.can_read_occasion_context_row(id)'
        if (p['schemaname'],p['tablename'],p['policyname'])==('public','occasion_users','Enable all for managers'):
            new=['public.can_manage_occasion_participants(occasion)']*2
        if old==new:continue
        result.append('ALTER POLICY '+quote(p['policyname'])+' ON '+quote(p['schemaname'])+'.'+quote(p['tablename'])+
          (('\n  USING ('+new[0]+')') if new[0] is not None else '')+
          (('\n  WITH CHECK ('+new[1]+')') if new[1] is not None else '')+';')
    return '\n'.join(result)+'\n'

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');a=parser.parse_args()
    output=render()
    if a.check:
        if not TARGET.exists() or TARGET.read_text()!=output:raise SystemExit('Authorization policies are stale')
    else:TARGET.write_text(output)
