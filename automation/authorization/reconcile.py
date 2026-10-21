#!/usr/bin/env python3
"""Reconcile source candidates with the real local catalog, without inferring policy proof."""
import collections
import hashlib
import json
import re
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'automation'))
from generate_canonical_source_contract import CREATE,identity,statements,definitions
FOLDER=ROOT/'docs/plans/evidence/canonical-authorization-20261020'
key=lambda s:s.replace('public.','').replace(' ','')

def tokens(sql):
    # Preserve quoted values/identifiers. This is only an owner candidate index,
    # never a substitute for the exact catalog body contract or behavior tests.
    pattern=r"(?:[eE])?'(?:''|[^'])*'|\"(?:\"\"|[^\"])*\"|--[^\n]*|/\*.*?\*/|[A-Za-z_]\w*|[0-9]+|\S"
    return tuple(token if token.startswith(("'",'"',"E'","e'")) else token.lower()
                 for token in re.findall(pattern,sql or '',re.S)
                 if not token.startswith(('--','/*')))
history={}
config=json.loads((ROOT/'automation/canonical-source-contract.json').read_text())
inputs=[ROOT/config['baseline']]+sorted(p for p in (ROOT/'supabase/migrations').glob('*.sql') if p.name[:14]>config['baselineVersion'])
for path in inputs:
    for signature,body in definitions(path.read_text()):
        signature=key(signature)
        if isinstance(body,tuple):
            previous=history.get(signature)
            if previous:history[key(body[1])]=(previous[0],str(path.relative_to(ROOT)))
            history[signature]=(None,str(path.relative_to(ROOT)))
        else:history[signature]=(body,str(path.relative_to(ROOT)))
by_signature=collections.defaultdict(list)
for path in (ROOT/'database/functions').rglob('*.sql'):
    for statement in statements(path.read_text()):
        if m:=CREATE.search(statement):
            by_signature[key(identity(m[1],m[2],True))].append(dict(
                source=str(path.relative_to(ROOT)),body=m[5].strip(' \n\r\t')))
source=json.loads((FOLDER/'source-inventory.json').read_text())
catalog=json.loads((FOLDER/'catalog-after.json').read_text())
names={f['signature'].split('(')[0].removeprefix('public.') for f in catalog['functions']}
test_index=collections.defaultdict(list)
for path in (ROOT/'database/tests').rglob('*_test.sql'):
    content=path.read_text()
    record=dict(path=str(path.relative_to(ROOT)),requiresPsql=bool(re.search(r'^\s*\\|:\w',content,re.M)))
    for called in set(re.findall(r'\b([a-zA-Z_]\w*)\s*\(',content))&names:
        test_index[called].append(record)
proof_path=FOLDER/'semantic-contract-evidence.json'
proofs={p['signature']:p for p in json.loads(proof_path.read_text())['functions']} if proof_path.exists() else {}
entries=[]
for f in catalog['functions']:
    name=f['signature'].split('(')[0].removeprefix('public.')
    match=CREATE.search(f['definition'])
    body=match[5].strip(' \n\r\t') if match else None
    candidates=by_signature[key(f['signature'])]
    exact=[p['source'] for p in candidates if p['body']==body]
    owners=exact or [p['source'] for p in candidates if tokens(p['body'])==tokens(body)]
    calls=sorted(set(re.findall(r'\b(?:public\.)?([a-zA-Z_]\w*)\s*\(',body or ''))&names)
    tests=test_index[name]
    historical=history.get(key(f['signature']))
    historical_owner=historical[1] if historical and historical[0] is not None and tokens(historical[0])==tokens(body) else None
    entries.append(dict(signature=f['signature'],execute=f['execute'],acl=f.get('acl'),grants=f.get('grants'),owner=f['owner'],
        sourceOwners=owners,effectiveHistoryOwner=historical_owner,sourceState='matched-exact' if len(exact)==1 else 'matched-token-equivalent' if len(owners)==1 else 'ambiguous' if owners else 'matched-effective-history' if historical_owner else 'source-owner-unresolved',
        bodySha256=hashlib.sha256((body or '').encode()).hexdigest(),
        actorCandidates=[v for v,pattern in [('jwt',r'auth\.uid\('),('service',r'require_service_role|is_service_role'),('technical-token',r'scanner_session|waitlist_capabilit|order_overview|request_secret')]
            if re.search(pattern,body or '')],
        sqlCallCandidates=calls,
        clientCallerCandidates=[c for c in source['callsites'] if c['target']==name],
        testCandidates=tests,
        authorizationGate=(proofs[f['signature']] if f['signature'] in proofs and proofs[f['signature']]['bodyMd5']==f['bodyMd5'] else
          'Admission classification and exact SQL owners are in domain-ledger.json; no dedicated role-truth-table assertion is inferred from textual test references.')))
summary=collections.Counter(e['sourceState'] for e in entries)
transport_path=FOLDER/'transport-resolution.json'
result=dict(notice='Complete source/catalog membership. Explicit admission classification and adapter decisions are sealed separately in domain-ledger.json and boundary-ledger.json; execution evidence remains separate.',
    sourceHead=source['sourceHead'],counts=dict(summary),roleTruthTableTested=sum(isinstance(e['authorizationGate'],dict) for e in entries),functions=entries,
    rlsPolicies=catalog['policies'],tableGrants=catalog['tableGrants'],columnGrants=catalog['columnGrants'],
    schemaGrants=catalog.get('schemaGrants'),defaultGrants=catalog.get('defaultGrants'),
    roles=catalog.get('roles'),roleMemberships=catalog.get('roleMemberships'),platformExtensions=catalog.get('platformExtensions'),
    serviceJobs=catalog['cronJobs'],transportBoundaries=source['transportBoundaries'],dynamicSqlCandidates=source['dynamicSqlCandidates'],
    transportDispatchEvidence=json.loads(transport_path.read_text()) if transport_path.exists() else None)
(FOLDER/'entrypoint-inventory.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(dict(functions=len(entries),sourceStates=dict(summary),rlsPolicies=len(catalog['policies']),transportBoundaries=len(source['transportBoundaries']))))
