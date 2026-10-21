#!/usr/bin/env python3
"""Summarize completed measurements without treating warm results as cold proof."""
import hashlib,json,re,statistics
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
FOLDER=ROOT/'docs/plans/evidence/canonical-authorization-20261020'
FILES=['performance-serial-canonical-final.json','performance-concurrent-canonical-final.json',
 'performance-context-navigation-final.json','performance-concurrent-navigation-final.json']
current=json.loads((FOLDER/'current-execution-contract.json').read_text())
catalog=json.loads((FOLDER/'catalog-after.json').read_text())
by_name={}
for f in catalog['functions']:
 by_name.setdefault(f['signature'].split('(')[0].removeprefix('public.'),[]).append(f)
roots={'context':['get_app_config_v218'],'operator':['get_operator_access_v1'],
 'editor_bundle':['get_map_editor_bundle_v1'],'layout_authoring':['get_ticket_layout_for_authoring_v1'],
 'write':['create_occasion_client_sync_v1'],'rls_list':[]}
# RLS expressions are catalog inputs, in addition to their transitive SQL calls.
roots['rls_list']=sorted(set(re.findall(r'\b([a-z_]\w*)\s*\(',str([
 p for p in catalog['policies'] if p['schemaname']=='public' and p['tablename']=='places'])))&by_name.keys())
def closure(names):
 seen=set();todo=list(names)
 while todo:
  name=todo.pop()
  if name in seen:continue
  seen.add(name)
  for f in by_name.get(name,[]):
   todo.extend(set(re.findall(r'\b([a-z_]\w*)\s*\(',f['definition']))&by_name.keys()-seen)
 return seen
current_functions={f['signature']:f for f in current['functions']}
results=[]
for filename in FILES:
 path=FOLDER/filename;data=json.loads(path.read_text())
 assert len(data['blocks'])==(12 if 'concurrent' in filename else 16),filename+' incomplete'
 recorded={f['signature']:f for f in data['executionContracts']['after']['functions']}
 changed=sorted(k for k in current_functions.keys()|recorded.keys() if current_functions.get(k)!=recorded.get(k))
 summaries=[]
 for size in [8,1000]:
  for workload in data['blocks'][0]['results']:
   if workload=='context' and 'canonical-final' in filename:continue # superseded by final navigation projection measurements
   variants={v:[b['results'][workload] for b in data['blocks'] if b['occasions']==size and b['variant']==v] for v in ['before','after']}
   medians={v:{metric:statistics.median(r[metric] for r in rows) for metric in ['p50','p95','throughputPerSecond']} for v,rows in variants.items()}
   ratios={k:100*(medians['after'][k]/medians['before'][k]-1) for k in medians['before']}
   first={v:[r['coldConnectionSamplesMs'][0] for r in rows] for v,rows in variants.items()}
   calls=closure(roots[workload])
   affected=[s for s in changed if s.split('(')[0].removeprefix('public.') in calls]
   summaries.append(dict(occasions=size,workload=workload,medianOfRounds=medians,percentageChange=ratios,
    warmedMedianGate=ratios['p95']<=5 and ratios['throughputPerSecond']>=-5,
    firstUseSamplesMs=first,firstUseMedianChange=100*(statistics.median(first['after'])/statistics.median(first['before'])-1),
    finalChangedStaticCallCandidates=affected,rpcCountPerDomainRequest=1))
 results.append(dict(file=filename,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
  measuredMigrationSha256=data['migrationFileSha256'],finalContractDifferences=changed,summaries=summaries))
coldpath=FOLDER/'performance-first-request-navigation-final.json'
cold=json.loads(coldpath.read_text());assert len(cold['blocks'])==24
coldresults=[]
for size in [8,1000]:
 for kind in ['sequentialMs','concurrentMs']:
  samples={v:sorted(x for b in cold['blocks'] if b['size']==size and b['variant']==v for x in b[kind]) for v in ['before','after']}
  values={v:dict(p50=statistics.median(a),p95=a[int(len(a)*.95)],samples=len(a)) for v,a in samples.items()}
  change=100*(values['after']['p95']/values['before']['p95']-1)
  coldresults.append(dict(occasions=size,mode=kind,values=values,p95Change=change,gate=change<=5))
assert all(s['warmedMedianGate'] and not s['finalChangedStaticCallCandidates'] for r in results for s in r['summaries']), 'Invalidated or regressed warm measurement'
assert all(r['gate'] for r in coldresults),'Cold first-request regression'
recordedcold={f['signature']:f for f in cold['executionContracts']['after']['functions']}
coldchanges=sorted(k for k in recordedcold.keys()|current_functions.keys() if recordedcold.get(k)!=current_functions.get(k))
assert not [k for k in coldchanges if k.split('(')[0].removeprefix('public.') in closure(roots['context'])], 'Cold context call closure changed'

result=dict(state='passed local paired warm and first-request gates',
 cold=dict(file=coldpath.name,sha256=hashlib.sha256(coldpath.read_bytes()).hexdigest(),summaries=coldresults,unrelatedFinalFunctionDifferences=coldchanges,finalContextClosureUnchanged=True),
 rejectedExperiments=[dict(file='performance-context-single-plan.json',reason='One materialized SQL expression plan increased warmed context p95; source restored.'),
 dict(file='performance-context-fact-plan.json',reason='Combined PL/pgSQL fact initialization did not close first-use regression; original constructor restored.')],
 limits=['Static call closure is conservative provenance evidence; explicit source-bound dynamic dispatch and service registries are recorded in the boundary/domain ledgers.',
 'The final navigation projection supersedes earlier context timings only; the remaining five measured workload closures are unchanged.',
 'Later scanner proof and direct DELETE ACL contraction do not alter the six measured workload closures.',
 'Fresh connection/function plans do not flush shared buffers or the operating-system cache.',
 'The synthetic database accumulated benchmark fixtures; no production distribution or production latency is claimed.'],results=results)
(FOLDER/'performance-summary.json').write_text(json.dumps(result,indent=2)+'\n')
print('Passed all six local warm workload gates and four final first-request gates; unchanged measured call closures verified.')
