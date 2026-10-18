"""Exact real-PG17 data/sync rollback contract, sharing the existing test owner."""
import importlib.util,json,os,subprocess,unittest
from pathlib import Path
import test_cutover_pg17 as base
ROOT=base.ROOT
from test_reference_disposition import fixture,m

@unittest.skipUnless(os.environ.get('FESTAPP_ASSET_CUTOVER_PG17_TEST')=='1','explicit isolated PG17 contract')
class Disposition(unittest.TestCase):
 setUpClass=classmethod(base.PostgreSQLCutover.setUpClass.__func__)
 sql=base.PostgreSQLCutover.sql
 def setUp(self):
  base.PostgreSQLCutover.setUp(self)
  self.sql("ALTER TABLE public.occasions ADD COLUMN data jsonb; ALTER TABLE public.occasions ADD COLUMN organization bigint DEFAULT 3; CREATE TABLE public.events(id bigint PRIMARY KEY,data jsonb,occasion bigint DEFAULT 1072551); CREATE TABLE public.email_wrappers(id bigint PRIMARY KEY,html text,occasion bigint DEFAULT 1072509); UPDATE public.canonical_asset_cutover SET inventory_sha256=repeat('a',64);")
  self.fields=fixture();self.disposition=m.prepare(self.fields,'a'*64)
  self.sql("INSERT INTO public.occasions(id) VALUES(376315),(1072509),(1072551); INSERT INTO public.client_sync_scopes(component,scope_type,scope_id) SELECT 'content_catalog','occasion',x FROM unnest(ARRAY[376315,1072509,1072551]) x;")
  for f in self.fields:
   if f['table']=='occasions':statement="UPDATE public.occasions SET data=$json$"+json.dumps(f['original'])+"$json$::jsonb WHERE id=376315;"
   elif f['table']=='events':statement="INSERT INTO public.events(id,data) VALUES("+str(f['id'])+",$json$"+json.dumps(f['original'])+"$json$::jsonb);"
   else:statement="INSERT INTO public.email_wrappers(id,html) VALUES(20,$html$"+f['original']+"$html$);"
   self.sql(statement)
 def apply(self):
  body=json.dumps(self.disposition);assert '$bundle$' not in body
  sql="BEGIN;CREATE TEMP TABLE asset_reference_disposition_input(payload jsonb) ON COMMIT DROP;INSERT INTO asset_reference_disposition_input VALUES($bundle$"+body+"$bundle$::jsonb);"+(ROOT/'automation/image-migration/apply-approved-reference-cleanup.sql').read_text()+"\nCOMMIT;"
  return self.sql(sql,check=False)
 def test_current_scan_includes_escaped_and_entity_urls_without_history(self):
  from storage_references import inspect_value
  values=[r'https:\/\/api.festapp.net\/storage\/v1\/object\/public\/files\/x',
          'https:&#47;&#47;api.festapp.net&#47;storage&#47;v1&#47;object&#47;public&#47;files&#47;y',
          '<img src="https://img&#46;festapp&#46;net/images/z">']
  self.sql("CREATE TABLE public.scan_fixture(value jsonb);CREATE TABLE public.log_scan_history(value text);CREATE TABLE public.email_messages(workflow_state text,payload jsonb);INSERT INTO public.log_scan_history VALUES('https://img.festapp.net/history-only');")
  for value in values:self.sql("INSERT INTO public.scan_fixture VALUES($value$"+json.dumps({'nested':[value]})+"$value$::jsonb);")
  self.sql("INSERT INTO public.email_messages VALUES('pending','{\"link\":\"https://img.festapp.net/queued-current\"}'),('delivered','{\"link\":\"https://img.festapp.net/delivered-history\"}');")
  result=self.sql((ROOT/'automation/hetzner-supabase/restore/current_asset_fields.sql').read_text())
  rows=[json.loads(line) for line in result.stdout.splitlines() if line.strip()]
  # Test actual PG selection and the same structural parser, not a regex copy.
  self.assertEqual(sum(len(list(inspect_value(row,{'api.festapp.net'}))) for row in rows),2)
  from pathlib import Path
  import sys
  sys.path.insert(0,str(ROOT/'automation/hetzner-supabase/restore'))
  from r2_archive import application_references
  refs=[]
  for row in rows:
   if not list(inspect_value(row,{'api.festapp.net'})):refs+=application_references(row,{'api.festapp.net'})
  self.assertIn('https://img.festapp.net/images/z',refs)
  self.assertIn('https://img.festapp.net/queued-current',refs)
  self.assertNotIn('https://img.festapp.net/history-only',refs)
  self.assertNotIn('https://img.festapp.net/delivered-history',refs)

 def test_iso_utc_target_is_normalized_for_actual_postgres_recovery_guc(self):
  spec=importlib.util.spec_from_file_location('pitr',ROOT/'automation/hetzner-supabase/restore/drill-pgbackrest-local.py')
  pitr=importlib.util.module_from_spec(spec);spec.loader.exec_module(pitr)
  expected='2026-10-18 18:06:00+00:00'
  for value in ['2026-10-18T18:06:00Z','2026-10-18T18:06:00+00:00','2026-10-18T20:06:00+02:00']:
   self.assertEqual(pitr.postgres_recovery_target(value),expected)
  with self.assertRaisesRegex(ValueError,'timezone'):pitr.postgres_recovery_target('2026-10-18T18:06:00')
  def check(value):
   return subprocess.run(['docker','exec','-u','postgres',self.name,'postgres','-D','/etc/postgresql','-C','recovery_target_time','-c','recovery_target_time='+value],capture_output=True,text=True)
  rejected=check('2026-10-18T18:06:00Z')
  self.assertNotEqual(rejected.returncode,0)
  accepted=check(pitr.postgres_recovery_target('2026-10-18T18:06:00Z'))
  self.assertEqual(accepted.returncode,0,accepted.stderr)
  self.assertEqual(accepted.stdout.strip(),expected)

 def test_exact_fields_and_three_real_canonical_sync_commits(self):
  result=self.apply();self.assertEqual(result.returncode,0,result.stderr)
  self.assertEqual(self.sql("SELECT count(*) FROM public.client_commits WHERE source='storage.r2.approved-reference-cleanup';").stdout.strip(),'3')
  self.assertEqual(self.sql('SELECT data FROM public.events WHERE id=1390;').stdout.strip(),'{"keep": ["text", 42]}')
  self.assertNotEqual(self.apply().returncode,0,'completed approval cannot replay')
 def test_concurrent_edit_rolls_back_preceding_wrapper_update(self):
  self.sql("UPDATE public.events SET data='{}' WHERE id=1390;")
  result=self.apply();self.assertNotEqual(result.returncode,0);self.assertIn('changed since approval',result.stderr)
  self.assertEqual(self.sql('SELECT count(*) FROM public.client_commits;').stdout.strip(),'0')
  self.assertIn('missing0.png',self.sql('SELECT html FROM public.email_wrappers;').stdout)
 def test_sync_failure_rolls_back_all_four_fields(self):
  self.sql("ALTER TABLE public.client_commits ADD CHECK(source<>'storage.r2.approved-reference-cleanup');")
  result=self.apply();self.assertNotEqual(result.returncode,0);self.assertIn('check constraint',result.stderr)
  self.assertIn('missing0.png',self.sql('SELECT html FROM public.email_wrappers;').stdout)
  self.assertIn('header_image',self.sql('SELECT data FROM public.events WHERE id=1390;').stdout)

if __name__=='__main__':unittest.main()
