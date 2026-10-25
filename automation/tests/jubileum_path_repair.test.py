"""Replay the public map incident in a disposable local PostgreSQL database.

Run: python3 automation/tests/jubileum_path_repair.test.py --container <local-db>
Only the client-sync publication boundary is simulated; SQL repair and guards
run unchanged. The caller's existing databases are never altered.
"""
import argparse
import json
from pathlib import Path
import subprocess
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = json.loads((ROOT / 'automation/tests/fixtures/jubileum-path-repair.json').read_text())
MIGRATION = (ROOT / 'supabase/migrations/20261025200000_jubileum_path_place_references.sql').read_text()


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def sql(source, succeeds=True):
    result = subprocess.run(
        ['docker', 'exec', '-i', CONTAINER, 'psql', '-X', '-U', 'postgres',
         '-d', DATABASE, '-v', 'ON_ERROR_STOP=1', '-Atq'],
        input=source, text=True, capture_output=True,
    )
    if succeeds and result.returncode:
        raise AssertionError(result.stderr)
    if not succeeds:
        if result.returncode == 0:
            raise AssertionError('Expected guarded repair to fail')
        return result.stderr
    return result.stdout.strip()


class PathRepairTests(unittest.TestCase):
    def setUp(self):
        sql('''DROP SCHEMA public CASCADE; CREATE SCHEMA public;
          DROP SCHEMA IF EXISTS festapp_merge CASCADE; CREATE SCHEMA festapp_merge;
          CREATE TABLE public.occasions(id bigint PRIMARY KEY, organization bigint, link text);
          CREATE TABLE public.places(id bigint PRIMARY KEY, occasion bigint);
          CREATE TABLE public.path_groups(id bigint PRIMARY KEY, occasion bigint, path_data jsonb);
          CREATE TABLE public.client_aggregate_versions(aggregate_type text, scope_type text,
            scope_id bigint, aggregate_id text, version bigint, updated_at timestamptz,
            PRIMARY KEY(aggregate_type,scope_type,scope_id,aggregate_id));
          CREATE TABLE festapp_merge.import_runs(run_id uuid PRIMARY KEY, source_alias text, status text);
          CREATE TABLE festapp_merge.id_mappings(run_id uuid, source_table text, source_id text, target_id text);
          CREATE TABLE public.publication_calls(occasion bigint, source text, items jsonb,
            components text[], actor text);
          CREATE FUNCTION public.record_client_sync_commit_v1(bigint,text,text,jsonb,text[],jsonb,jsonb,text,text)
            RETURNS jsonb LANGUAGE plpgsql AS $$ BEGIN
              INSERT INTO public.publication_calls VALUES($1,$2,$4,$5,$8); RETURN '{}';
            END $$;
          INSERT INTO public.occasions VALUES(1072521,9,'jm2025'),(99,3,'unrelated');
          INSERT INTO public.path_groups VALUES(99,99,'[[1,2]]');
          INSERT INTO festapp_merge.import_runs VALUES
            ('b1e710d5-e3e5-4ae9-9376-c84c7c1afc8b','a','validated');
        ''')
        statements = []
        for place in FIXTURE['places']:
            statements.append(f"INSERT INTO public.places VALUES({place['id']},1072521);")
        for path in FIXTURE['paths']:
            statements.append(f"INSERT INTO public.path_groups VALUES({path['id']},1072521,{literal(json.dumps(path['path_data']))});")
            statements.append(f"INSERT INTO public.client_aggregate_versions VALUES('path','occasion',1072521,'{path['id']}',54,now());")
        for old, new in FIXTURE['mapping'].items():
            statements.append("INSERT INTO festapp_merge.id_mappings VALUES"
                              f"('b1e710d5-e3e5-4ae9-9376-c84c7c1afc8b','public.places',{literal(old)},{literal(new)});")
        sql('\n'.join(statements))

    def test_restores_exact_place_identity_order_segments_and_publishes_once(self):
        # This is the reported empty route, before the repair.
        self.assertEqual(sql('''SELECT count(*) FROM public.path_groups g,
          LATERAL jsonb_array_elements(g.path_data) s,
          LATERAL jsonb_array_elements(s) n JOIN public.places p ON p.id=(n#>>'{}')::bigint
          WHERE g.id=3'''), '0')
        sql('BEGIN;\n' + MIGRATION + '\nCOMMIT;')
        actual = json.loads(sql("SELECT jsonb_object_agg(id,path_data) FROM public.path_groups WHERE occasion=1072521"))
        for path in FIXTURE['paths']:
            expected = [[FIXTURE['mapping'][str(n)] for n in segment] for segment in path['path_data']]
            self.assertEqual(actual[str(path['id'])], expected)
        self.assertEqual(actual['3'], [[205, 206, 207, 208, 205]])
        self.assertEqual(actual['7'][2], [314, 322, 323, 324, 318])
        self.assertEqual(sql("SELECT path_data FROM public.path_groups WHERE id=99"), '[[1, 2]]')
        self.assertEqual(sql("SELECT count(*) FROM public.client_aggregate_versions WHERE version=55"), '7')
        self.assertEqual(sql("SELECT count(*) FROM public.publication_calls WHERE occasion=1072521 AND components=ARRAY['map_catalog'] AND actor='system' AND jsonb_array_length(items)=7"), '1')
        sql('BEGIN;\n' + MIGRATION + '\nCOMMIT;')
        self.assertEqual(sql("SELECT count(*) FROM public.publication_calls"), '1')
        self.assertEqual(sql("SELECT count(*) FROM public.client_aggregate_versions WHERE version=55"), '7')

    def test_refuses_changed_path_and_rolls_back_earlier_paths(self):
        sql("UPDATE public.path_groups SET path_data='[[1,2]]' WHERE id=9")
        error = sql('BEGIN;\n' + MIGRATION + '\nCOMMIT;', succeeds=False)
        self.assertIn('path 9 changed', error)
        self.assertEqual(sql("SELECT path_data FROM public.path_groups WHERE id=3"), '[[189, 190, 191, 192, 189]]')
        self.assertEqual(sql("SELECT count(*) FROM public.client_aggregate_versions WHERE version=54"), '7')

    def test_refuses_missing_provenance(self):
        sql("DELETE FROM festapp_merge.id_mappings WHERE source_id='189'")
        self.assertIn('unproven place mapping', sql('BEGIN;\n' + MIGRATION, succeeds=False))

    def test_refuses_foreign_target(self):
        sql('UPDATE public.places SET occasion=99 WHERE id=205')
        self.assertIn('unproven place mapping', sql('BEGIN;\n' + MIGRATION, succeeds=False))

    def test_refuses_wrong_occasion_identity(self):
        sql('UPDATE public.occasions SET organization=3 WHERE id=1072521')
        self.assertIn('occasion identity mismatch', sql('BEGIN;\n' + MIGRATION, succeeds=False))

    def test_unaffected_installation(self):
        sql('DELETE FROM public.occasions WHERE id=1072521; DROP SCHEMA festapp_merge CASCADE;')
        sql('BEGIN;\n' + MIGRATION + '\nCOMMIT;')
        self.assertEqual(sql('SELECT count(*) FROM public.publication_calls'), '0')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    args = parser.parse_args()
    CONTAINER = args.container
    DATABASE = 'festapp_path_repair_test_' + uuid.uuid4().hex[:12]
    subprocess.run(['docker', 'exec', CONTAINER, 'createdb', '-U', 'postgres', DATABASE], check=True)
    try:
        result = unittest.TextTestRunner(verbosity=1).run(unittest.defaultTestLoader.loadTestsFromTestCase(PathRepairTests))
    finally:
        subprocess.run(['docker', 'exec', CONTAINER, 'dropdb', '-U', 'postgres', DATABASE], check=True)
    raise SystemExit(0 if result.wasSuccessful() else 1)
