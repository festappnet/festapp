"""Reporter contracts independent of Flutter or database availability."""
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'automation'))
from test_client import event_profile
from check_baseline_parity import normalize_schema_dump


class ProfileContractTest(unittest.TestCase):
    def test_profile_keeps_failure_skip_origin_and_load_separate(self):
        events = [
            {'type': 'suite', 'suite': {'id': 1, 'path': 'test/example.dart'}},
            {'type': 'testStart', 'time': 0, 'test': {'id': 1, 'suiteID': 1, 'name': 'loading test/example.dart'}},
            {'type': 'testDone', 'time': 400, 'testID': 1, 'result': 'success'},
            {'type': 'testStart', 'time': 450, 'test': {'id': 2, 'suiteID': 1, 'name': 'actual case', 'url': 'file://test/example.dart'}},
            {'type': 'testDone', 'time': 750, 'testID': 2, 'result': 'failure', 'skipped': False},
            {'type': 'done', 'time': 800, 'success': False},
        ]
        report = event_profile(events, 1.2)
        self.assertAlmostEqual(report['processOverheadSeconds'], .4)
        self.assertEqual(len(report['cases']), 1)
        self.assertEqual(report['cases'][0]['result'], 'failure')
        self.assertEqual(report['cases'][0]['path'], 'test/example.dart')
        self.assertEqual(report['frameworkEvents'][0]['seconds'], .4)
        self.assertEqual(report['cases'][0]['seconds'], .3)

    def test_policy_role_order_is_irrelevant_but_predicate_and_owner_are_not(self):
        left = 'CREATE POLICY sample ON public.rows FOR SELECT TO authenticated, anon USING (allowed);\nALTER TABLE public.rows OWNER TO postgres;\n'
        right = left.replace('authenticated, anon', 'anon, authenticated')
        self.assertEqual(normalize_schema_dump(left), normalize_schema_dump(right))
        self.assertNotEqual(normalize_schema_dump(left), normalize_schema_dump(right.replace('(allowed)', '(true)')))
        self.assertNotEqual(normalize_schema_dump(left), normalize_schema_dump(right.replace('OWNER TO postgres', 'OWNER TO anon')))


if __name__ == '__main__':
    unittest.main()
