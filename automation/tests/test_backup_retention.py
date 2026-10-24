import datetime as dt
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('retention', Path(__file__).parents[1] / 'hetzner-supabase/backup/prune-online-backups.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def prefix(day):
    return module.PREFIX + day.strftime('%Y%m%dT%H%M%SZ')


class RetentionTest(unittest.TestCase):
    def test_daily_window_and_four_completed_weeks_across_year_boundary(self):
        now = dt.datetime(2027, 1, 7, 12, tzinfo=dt.timezone.utc)
        sets = {prefix(now - dt.timedelta(days=days, hours=10)) for days in range(50)}
        keep, remove = module.choose_sets(sets, now)
        self.assertEqual(set(remove) | keep, sets)
        self.assertFalse(set(remove) & keep)
        recent = {p for p in sets if p >= prefix(now - dt.timedelta(days=14))}
        self.assertTrue(recent <= keep)
        weekly = {}
        for p in sorted(sets):
            stamp = dt.datetime.strptime(p.rsplit('/', 1)[-1], '%Y%m%dT%H%M%SZ')
            week = stamp.date().isocalendar()[:2]
            if week < now.date().isocalendar()[:2]:
                weekly[week] = p
        self.assertTrue({weekly[w] for w in sorted(weekly)[-4:]} <= keep)
        self.assertTrue(remove)

    def test_preserves_three_latest_even_when_backup_schedule_has_stopped(self):
        now = dt.datetime(2026, 10, 8, tzinfo=dt.timezone.utc)
        sets = {prefix(now - dt.timedelta(days=40 + i)) for i in range(3)}
        keep, remove = module.choose_sets(sets, now)
        self.assertEqual(keep, sets)
        self.assertEqual(remove, [])

    def test_never_selects_another_bucket_prefix(self):
        with self.assertRaises(ValueError):
            module.choose_sets({'logs/20260901T000000Z'}, dt.datetime.now(dt.timezone.utc))

    def test_minimum_retention_guard(self):
        with self.assertRaises(ValueError):
            module.choose_sets(set(), dt.datetime.now(dt.timezone.utc), daily_days=1)

    def test_incomplete_or_nonroutine_sets_remain_outside_cleanup(self):
        class FakeStore:
            def request(self, *args):
                raise AssertionError('An incomplete set must not be fetched or deleted')
        row = {'Path': module.PREFIX + '20260901T000000Z/postgres.dump.age', 'Size': 42}
        # Fewer than three complete recovery points abort the cleanup entirely.
        with self.assertRaisesRegex(RuntimeError, 'Fewer than three'):
            module.complete_sets(FakeStore(), [row])


if __name__ == '__main__':
    unittest.main()
