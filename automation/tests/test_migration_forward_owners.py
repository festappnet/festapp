"""History and owner safety contracts for the shared manifest-driven checker."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import migration_forward_owners as owners


class ForwardOwnerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        owners.verify_forward.cache_clear()
        self.root = Path(self.tmp.name)
        self.old = '20260101000000_history.sql'
        self.new = '20260102000000_forward.sql'
        self.original = 'CREATE OR REPLACE FUNCTION public.sample() RETURNS text LANGUAGE sql AS $$old$$;'
        self.current = self.original.replace('$$old$$', '$$new$$')
        for folder in ('automation', 'supabase/migrations', 'database/functions'):
            (self.root / folder).mkdir(parents=True)
        self.write('database/functions/owner.sql', self.current)
        frozen = '-- SOURCE: owner.sql\n' + self.original + '\n'
        self.write('supabase/migrations/' + self.old, frozen)
        self.entries = [
            {'migration': self.old, 'sha256': hashlib.sha256(frozen.encode()).hexdigest(),
             'sources': ['owner.sql'], 'checkSources': True},
            {'migration': self.new, 'manifest': 'forward.json', 'active': True},
        ]
        self.write('automation/forward.json', json.dumps({'header': '-- Forward', 'sources': ['owner.sql']}))
        self.save_registry()
        target, content = owners.render_forward(self.root, self.entries[1])
        target.write_text(content)
        paths = lambda root: sorted((root / 'supabase/migrations').glob('*.sql'))
        self.patcher = patch.object(owners.migration_inputs, 'migration_paths', paths)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def write(self, name, text):
        (self.root / name).write_text(text)

    def save_registry(self):
        self.write('automation/migration-forward-owners.json', json.dumps({'version': 1, 'migrations': self.entries}))

    def test_explicit_forward_allows_changed_owner_without_touching_history(self):
        owners.verify_forward(self.root)
        self.assertEqual(owners.historical_source(self.root, self.old, 'owner.sql'), self.original)

    def test_outer_execution_role_is_not_an_authored_source_statement(self):
        frozen = '-- SOURCE: owner.sql\nSET LOCAL ROLE postgres;\n' + self.original + '\nRESET ROLE;\n'
        self.write('supabase/migrations/' + self.old, frozen)
        self.entries[0]['sha256'] = hashlib.sha256(frozen.encode()).hexdigest()
        self.save_registry()
        self.assertEqual(owners.historical_source(self.root, self.old, 'owner.sql'), self.original)

    def test_frozen_history_tampering_is_rejected(self):
        self.write('supabase/migrations/' + self.old, '-- edited historical bytes\n' + self.original)
        with self.assertRaisesRegex(SystemExit, 'Immutable migration bytes changed'):
            owners.verify_forward(self.root)

    def test_missing_registered_forward_is_rejected(self):
        (self.root / 'supabase/migrations' / self.new).unlink()
        with self.assertRaisesRegex(SystemExit, 'effective migration head|missing or stale'):
            owners.verify_forward(self.root)

    def test_unplanned_source_drift_cannot_hide_behind_function_parity(self):
        self.entries.pop()
        self.save_registry()
        self.write('database/functions/owner.sql', self.original + '\nALTER TABLE public.sample ENABLE ROW LEVEL SECURITY;')
        with self.assertRaisesRegex(SystemExit, 'Unplanned canonical source drift'):
            owners.check_frozen(self.root, self.old)

    def test_other_migration_cannot_silently_replace_current_function_body(self):
        self.write('supabase/migrations/20260103000000_unplanned.sql', self.original)
        with self.assertRaisesRegex(SystemExit, 'effective migration head'):
            owners.verify_forward(self.root)

    def test_function_only_owner_cannot_reintroduce_backfill(self):
        self.entries[0]['functionOnlySources'] = ['owner.sql']
        self.save_registry()
        self.write('database/functions/owner.sql', self.current + '\nUPDATE public.orders SET state=\'paid\';')
        with self.assertRaisesRegex(SystemExit, 'migration-only SQL'):
            owners.check_frozen(self.root, self.old)

    def test_stale_forward_is_rejected_even_when_later_function_is_current(self):
        self.write('supabase/migrations/' + self.new, '-- missing a non-function statement\n' + self.current)
        with self.assertRaisesRegex(SystemExit, 'missing or stale'):
            owners.verify_forward(self.root)


if __name__ == '__main__':
    unittest.main()
