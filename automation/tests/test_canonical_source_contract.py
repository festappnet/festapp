import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('contract', Path(__file__).parents[1] / 'generate_canonical_source_contract.py')
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)


class CanonicalSourceContractTest(unittest.TestCase):
    def test_quoted_function_bodies_are_single_statements(self):
        sql = '''-- CREATE FUNCTION fake() RETURNS void AS $$bad$$;
/* comment; */ CREATE FUNCTION public.real(p_id bigint) RETURNS text
AS $body$BEGIN RETURN 'CREATE FUNCTION fake();'; END;$body$ LANGUAGE plpgsql;
SELECT E'it\\\'s; a value'; SELECT 'it''s; another';'''
        self.assertEqual(len(list(contract.statements(sql))), 3)
        self.assertEqual(list(contract.definitions(sql)), [
            ('public.real(bigint)', "BEGIN RETURN 'CREATE FUNCTION fake();'; END;")])

    def test_identity_distinguishes_overloads_and_ignores_defaults_and_out_args(self):
        self.assertEqual(contract.identity('"public"."sample"',
            '''"p_id" int8, p_data jsonb DEFAULT jsonb_build_object('a', 1),
            OUT result text, INOUT p_flag bool DEFAULT false''', True),
            'public.sample(bigint,jsonb,boolean)')
        self.assertNotEqual(contract.identity('sample', 'bigint'), contract.identity('sample', 'text'))

    def test_nested_comments_do_not_split_statements(self):
        self.assertEqual(len(list(contract.statements('/* outer; /* inner; */ rest */ SELECT 1;'))), 1)

    def test_unterminated_source_fails_instead_of_silently_skipping(self):
        for sql in ["SELECT 'oops", 'DO $$oops', '/* oops']:
            with self.subTest(sql=sql), self.assertRaises(ValueError):
                list(contract.statements(sql))

    def make_release(self, root):
        files = {
            'automation/canonical-source-contract.json': json.dumps({
                'baseline': 'supabase/baseline/20260101000000.sql',
                'baselineVersion': '20260101000000',
                'operationsManifest': 'automation/manifest.json',
                'retainedSignatures': ['public.original(bigint)', 'public.renamed(bigint)', 'public.removed(text)']}),
            'automation/manifest.json': json.dumps({'sources': ['selected.sql']}),
            'supabase/baseline/20260101000000.sql': '''
CREATE FUNCTION public.original(p_id bigint) RETURNS text AS $$old$$ LANGUAGE sql;
CREATE FUNCTION public.removed(p_id text) RETURNS text AS $$removed$$ LANGUAGE sql;''',
            'supabase/migrations/20260102000000.sql': '''
ALTER FUNCTION public.original(bigint) RENAME TO renamed;
DROP FUNCTION public.removed(text);
CREATE FUNCTION public.selected(p_id bigint) RETURNS text AS $$new$$ LANGUAGE sql;''',
            'database/functions/selected.sql': 'CREATE FUNCTION public.selected(p_id bigint) RETURNS text AS $$new$$ LANGUAGE sql;',
        }
        for name, text in files.items():
            p = root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text)

    def test_release_replays_rename_drop_and_current_authored_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_release(root)
            sql = contract.render(root)
            self.assertIn("to_regprocedure('public.original(bigint)') IS NULL", sql)
            self.assertIn("to_regprocedure('public.removed(text)') IS NULL", sql)
            for signature, body in [('public.renamed(bigint)', 'old'), ('public.selected(bigint)', 'new')]:
                self.assertIn(f"to_regprocedure('{signature}') AND md5", sql)
                self.assertIn(hashlib.md5(body.encode()).hexdigest(), sql)
            self.assertEqual(sql, contract.render(root))

    def test_unassembled_source_drift_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_release(root)
            p = root / 'database/functions/selected.sql'
            p.write_text(p.read_text().replace('$$new$$', '$$unreleased$$'))
            with self.assertRaisesRegex(ValueError, 'not effective at release head'):
                contract.render(root)

    def test_retired_signature_is_checked_absent_and_cannot_be_revived(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_release(root)
            p = root / 'automation/canonical-source-contract.json'
            config = json.loads(p.read_text())
            config['retiredSignatures'] = ['public.removed(text)']
            p.write_text(json.dumps(config))
            self.assertIn("to_regprocedure('public.removed(text)') IS NULL", contract.render(root))
            (root / 'supabase/migrations/20260103000000.sql').write_text(
                'CREATE FUNCTION public.removed(p_id text) RETURNS text AS $$revived$$ LANGUAGE sql;')
            with self.assertRaisesRegex(ValueError, 'Retired implementation remains reachable'):
                contract.render(root)

    def test_different_function_names_cannot_own_the_same_receipted_operation(self):
        body = "PERFORM public.begin_client_mutation_v1(p_id,'profile.user.save',oc,actor,hash);"
        with self.assertRaisesRegex(ValueError, 'Multiple transaction owners for profile.user.save'):
            contract.command_transaction_owners({'public.command()': body, 'public.renamed_copy()': body})

    def test_actor_admission_branches_inside_one_command_share_one_owner(self):
        body = """PERFORM public.begin_anonymous_client_mutation_v1(p_id,'feedback.submit',oc,client,hash);
PERFORM public.begin_client_mutation_v1(p_id,'feedback.submit',oc,actor,hash);"""
        self.assertEqual(contract.command_transaction_owners({'public.feedback()': body}),
                         {'feedback.submit': {'public.feedback()'}})


if __name__ == '__main__':
    unittest.main()
