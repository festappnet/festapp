#!/usr/bin/env python3
"""Seal source/catalog reachability and reviewed boundary decisions, not test coverage."""
import collections,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
F=ROOT/'docs/plans/evidence/canonical-authorization-20261020'
read=lambda n:json.loads((F/n).read_text())
write=lambda n,v:(F/n).write_text(json.dumps(v,indent=2)+'\n')
catalog=read('catalog-after.json');inventory=read('entrypoint-inventory.json');source=read('source-inventory.json')
entries={e['signature']:e for e in inventory['functions']}
assert all(e['sourceState'].startswith('matched-') for e in entries.values())
by_name=collections.defaultdict(list)
for f in catalog['functions']:by_name[f['signature'].split('(')[0]].append(f)
# This is a conservative overload union, never used by runtime authorization.
def calls(f):
 body=re.sub(r'--[^\n]*|/\*.*?\*/','',f['definition'],flags=re.S)
 return set(re.findall(r'\b(?:public\.)?([a-z_]\w*)\s*\(',body))&by_name.keys()
def closure(name):
 seen=set();todo=[name]
 while todo:
  n=todo.pop()
  if n in seen:continue
  seen.add(n)
  for f in by_name[n]:todo.extend(calls(f)-seen)
 return [f for n in sorted(seen) for f in by_name[n]]
# All API-callable SECURITY DEFINER paths without identity/technical admission.
# Reviewed individually: these retain public/fact/visibility semantics, not editor rights.
public={
 'check_bank_account_writable':'Demo write fence only; does not grant bank administration. Bank commands additionally use can_manage_bank_account.',
 'check_occasion_writable':'Demo write fence only; does not grant editorial permission. Commands additionally check their operation owner.',
 'demo_entity_is_protected':'Public demo-protection classification of an entity, not private entity contents or mutation.',
 'get_all_occasions':'Public unit catalog: actual unit row, only non-hidden occasions; original form response preserved.',
 'get_available_occasions':'Public catalog: actual organization/unit relation, non-hidden occasions, promoted-only global listing.',
 'get_available_platforms':'Public platform configuration selected by organization ID; no private member or credential fields.',
 'get_counseling_topics_overview':'Public enabled-counseling catalog: visible topics/speakers and aggregate free capacity, no attendee identities.',
 'get_current_quote':'Public enabled unit-quote selection: only visible unit quotes; row lock persists daily selection, not editorial content.',
 'get_exists_on_occasion_user':'Original membership-existence fact for supplied user/occasion; no role grant or private profile payload.',
 'get_is_counseling_enabled_on_occasion':'Public feature-enabled fact from stored occasion configuration.',
 'get_is_event_feedback_enabled_on_occasion':'Public feature-enabled fact from stored occasion configuration.',
 'get_public_occasions':'Public organization/unit catalog: validated stored relationship, non-hidden occasions, existing promotion filter.',
 'get_speakers':'Public visible speakers/topics/event links, constrained to actual occasion and non-hidden linked records.',
 'get_sync_occasions':'Public external catalog: open, visible, promoted occasions; optional stored organization/unit filters.',
 'get_unit':'Public unit catalog with visible occasions and original form metadata; no member credentials.',
 'is_demo_bank_account':'Public demo-account classification, not bank administration.',
 'is_demo_occasion':'Public demo-occasion classification, not editorial admission.',
 'is_demo_unit':'Public demo-unit classification, not unit administration.',
 'search_occasion_content':'Public occasion search: visible events/places/information/speakers, public news, enabled feature filters and bounded limit.',
}
records=[];exceptions=set();adapters=[]
for f in catalog['functions']:
 signature=f['signature'];name=signature.split('(')[0];e=entries[signature];chain=closure(name)
 ops=[x['signature'] for x in chain if x['signature'].split('(')[0].startswith(('can_','get_can_','check_is_','get_is_','assert_','require_'))]
 identity=[x['signature'] for x in chain if re.search(r'auth\.uid|current_setting|require_service_role|is_service_role|token|secret|session',x['definition'],re.I)]
 api=f['execute']['anon'] or f['execute']['authenticated']
 if not api:kind='trusted-owner/service or internal helper';rule='Exact EXECUTE ACL is the admission boundary; service actor/resource invariants remain in the listed SQL implementation.'
 elif not f['definer']:kind='invoker boundary';rule='Caller SQL privileges and RLS remain effective; pure helpers cannot elevate. Named operation calls, if any, are listed separately.'
 elif identity:kind='identity/resource or technical-proof boundary';rule='Listed SQL admission owners bind verified JWT/service identity or technical proof to stored resource; full implementation is linked by body digest.'
 else:
  assert name in public, 'Unreviewed public SECURITY DEFINER path: '+signature
  exceptions.add(name);kind='reviewed public/fact boundary';rule=public[name]
 owner=e['sourceOwners'] or [e['effectiveHistoryOwner']]
 record=dict(signature=signature,kind=kind,actorAdmission=rule,execute=f['execute'],grants=f['grants'],sourceOwners=owner,
  bodyMd5=f['bodyMd5'],bodySha256=e['bodySha256'],operationOwners=sorted(set(ops)),identityOrTechnicalOwners=sorted(set(identity)),
  resourceBinding='Stored SQL relations and exact predicate body in catalog-after.json; caller IDs identify resources and never supply role claims.',
  directCallers=e['clientCallerCandidates'],sqlCalls=sorted(calls(f)),testReferences=e['testCandidates'],
  testCoverage='Role truth table executed' if isinstance(e['authorizationGate'],dict) else 'See domain gate receipts; textual test references alone are not executed coverage')
 records.append(record)
 # Individually enumerate old public boundaries that forward into a canonical command.
 targets=sorted(n for n in calls(f) if n.endswith('_client_sync_v1'))
 if api and targets and not name.endswith('_client_sync_v1'):
  adapters.append(dict(signature=signature,sourceOwners=owner,canonicalTargets=targets,bodyMd5=f['bodyMd5'],
   supportedConsumer='Pre-cutover public RPC protocol present at base ce77a1e4; concrete current source callsites listed when present. Installed-client telemetry was not queried.',
   currentSourceCallers=e['clientCallerCandidates'],
   retention='Preserve the existing public payload/error contract; the canonical command owns current authorization and receipt mutation. No second role formula is introduced.',
   removalCondition='A separately authorized client compatibility retirement establishes that no supported binary/integration uses this exact RPC signature.'))
assert exceptions==set(public),(exceptions^set(public))
# External context/credential adapters retain protocol envelopes, not copied policies.
for name,reason in {
 'get_app_config':'Original mobile context envelope delegates to the shared context owner.',
 'get_app_config_v182':'Versioned installed-client envelope delegates to the shared context owner.',
 'get_app_config_v203':'Versioned installed-client envelope delegates to the shared context owner.',
 'get_app_config_v216':'Versioned installed-client envelope delegates to the shared context owner.',
 'get_app_config_v217':'Versioned installed-client envelope delegates to the shared context owner.',
 'get_app_config_v219':'Current Dart context RPC selection; delegates to shared v218 owner.',
 'get_app_config_v2':'Existing Dart missing-function fallback; kept as an existing supported context protocol.',
 'scan_ticket_v2':'Legacy ticket/order/product response uses the same stored scanner-secret resolver as modern sessions; NULL and revoked codes deny.',
 'get_all_user_basics_for_scan':'Current Dart scanner-directory call shares the same stored scanner-secret resolver.',
 'get_all_occasions_for_edit':'Legacy catalog preserves its narrower unit-only listing instead of widening it to modern discovery.',
 'get_all_occasions_for_edit_v182':'Versioned legacy unit-only listing preserves its supported envelope and narrower scope.',
 'get_is_editor_order_on_occasion':'Public role-named compatibility predicate delegates to can_write_orders; facts are private.',
 'get_is_editor_order_view_on_occasion':'Public role-named compatibility predicate delegates to can_read_orders; facts are private.',
}.items():
 for f in by_name.get(name,[]):
  e=entries[f['signature']]
  adapters.append(dict(signature=f['signature'],reason=reason,bodyMd5=f['bodyMd5'],sourceOwners=e['sourceOwners'] or [e['effectiveHistoryOwner']],
   canonicalTargets=sorted(calls(f)),currentSourceCallers=e['clientCallerCandidates'],
   supportedConsumer='Existing public API at the recorded base; current repository callers are listed. No installed-client telemetry claim.',
   removalCondition='Explicit retirement of this public protocol after supported clients/integrations no longer require it.'))
# Every actual policy expression is retained, with its named SQL owners. No role
# is inferred from client catalogs, and effective write reachability is tested.
policies=[dict(**p,sqlOwners=sorted(set(re.findall(r'\b([a-z_]\w*)\s*\(',str(p['qual'])+' '+str(p['with_check'])))&by_name.keys()),
 admission='Exact USING/WITH CHECK expression in this catalog record; caller role/table/column grants are collected separately.') for p in catalog['policies']]
retired=json.loads((ROOT/'automation/canonical-source-contract.json').read_text())['retiredSignatures']
registry=catalog['writerRegistry'];latest=max(r['registry_version'] for r in registry)
registry_labels={
 'process_occasion_auto_import/service ticket import':'Descriptive service-import lane, not a SQL function name. process_occasion_auto_import and canonical import functions retain service/resource guards.',
 'shared map direct DML':'Descriptive legacy direct-write lane, not a runtime function. Current application has no direct write caller and the real API table/column/RLS test proves no effective direct API write. Existing sync rollout readiness stays unchanged.',
}
registry_records=[]
for row in registry:
 writers=[]
 for lane in ['canonical_writers','legacy_writers']:
  for name in row[lane]:
   assert name in by_name or name in registry_labels,'Unresolved writer registration '+name
   writers.append(dict(lane=lane,name=name,signatures=[f['signature'] for f in by_name.get(name,[])],
    admission=registry_labels.get(name,'Exact per-function admission, source, ACL and operation owners are recorded above.')))
 registry_records.append(dict(**row,currentVersion=row['registry_version']==latest,writerDecisions=writers))
write('domain-ledger.json',dict(state='source/catalog and boundary ledger sealed',
 limits=['Call closure conservatively includes all overloads; lexical calls are reachability evidence, not an independent authorization proof.',
 'Executed behavior is recorded separately in validation.json. No claim that every catalog function has its own executed test.',
 'Only the marker-fenced disposable local schema was inspected; no production or installed-client telemetry was read.'],
 counts=dict(functions=len(records),policies=len(policies),reviewedPublicFactBoundaries=len(public),externalAdapters=len(adapters)),
 functions=records,policies=policies,externalAdapters=adapters,writerRegistry=registry_records,
 serviceJobs=[dict(**j,admission='Existing postgres-owned fixed scheduler entry; scheduler disabled in this disposable DB. Function EXECUTE and service guards are in the per-function records.') for j in catalog['cronJobs']],
 directAccess=dict(tables=catalog['tableGrants'],columns=catalog['columnGrants'],
  proof='Full-ACL parity and actual API-role table/column write-reachability test in canonical-authorization-postgres.test.mjs; no effective direct API write path.',
  clientAccess='Current client direct table calls are reads; no current Storage/Realtime producer was found. Policies and grants remain explicit.'),
 deletionLedger=dict(retiredSignatures=retired,retirementProof='Catalog absence, dependency/registry/cron guarded DROP RESTRICT, full disappeared-function and source-parity tests.',
  clientPolicy='Functional role composition removed from Dart/JS; role fields retained for editing/display/data relations. Crew and scan navigation use SQL projection.',
  mcp='Detached authorizeContext data preflight removed; SQL mutation/read validates consent narrowing and live authorization atomically.',
  history='Applied migration history unchanged; individually listed public adapters retain supported envelopes.')))
print(f'Sealed {len(records)} function records, {len(policies)} policies and {len(adapters)} individual external adapter decisions.')
