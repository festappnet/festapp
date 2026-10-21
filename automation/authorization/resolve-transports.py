#!/usr/bin/env python3
"""Bind reviewed dispatch origins to exact source bytes; never authorize requests."""
import hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
FOLDER=ROOT/'docs/plans/evidence/canonical-authorization-20261020'
source=json.loads((FOLDER/'source-inventory.json').read_text())
review=json.loads((ROOT/'automation/authorization/transport-decisions.json').read_text())
reviews={entry['source']:entry for entry in review['entries']}
functions={f['signature'].split('(')[0].removeprefix('public.') for f in json.loads((FOLDER/'catalog-after.json').read_text())['functions']}
edge_names={p.name for p in (ROOT/'supabase/functions').iterdir() if p.is_dir() and not p.name.startswith('_')}
resolved=[];unresolved=[]
for call in source['callsites']:
 if not call['kind'].startswith('dynamic'):continue
 decision=reviews.get(call['source']);path=ROOT/call['source']
 if not decision or decision['sourceSha256']!=hashlib.sha256(path.read_bytes()).hexdigest():
  unresolved.append(call);continue
 # These literal names support navigation only. The reviewed origin mechanism
 # explains the actual dispatch; lexical candidates do not prove a policy gate.
 literals=set(re.findall(r"['\"]([a-z][a-z0-9_-]*)['\"]",path.read_text()))
 resolved.append(dict(**call,dispatchDecision=decision,
  lexicalSqlCandidates=sorted(literals&functions),lexicalEdgeCandidates=sorted(literals&edge_names),
  domainAuthorizationState='Separate SQL operation/grant/technical-proof evidence; not inferred from forwarding.'))
result=dict(scope='Dynamic forwarding origins only; not full entrypoint or domain-policy closure',
 reviewedDispatchSites=len(resolved),unresolvedDispatchSites=unresolved,sites=resolved)
(FOLDER/'transport-resolution.json').write_text(json.dumps(result,indent=2)+'\n')
print(f'Dispatch origins: {len(resolved)} source-bound decisions; {len(unresolved)} unresolved sites.')
if unresolved:raise SystemExit(1)
