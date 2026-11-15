"""Timestamp validation after an actual pgBackRest time-target restore."""
import importlib.util
from pathlib import Path
import unittest

path=Path(__file__).resolve().parents[1]/'hetzner-supabase/restore/drill-pgbackrest-local.py'
spec=importlib.util.spec_from_file_location('pgbackrest_recovery',path)
recovery=importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)

class RecoveryTimestampTest(unittest.TestCase):
 def test_normalized_postgres_target_compares_with_replay_timestamp(self):
  target=recovery.postgres_recovery_target('2026-11-14T03:20:00Z')
  self.assertTrue(recovery.replay_at_or_before_target('2026-11-14T03:19:59.523581+00:00',target))
  self.assertTrue(recovery.replay_at_or_before_target('2026-11-14T04:20:00+01:00',target))
  self.assertFalse(recovery.replay_at_or_before_target('2026-11-14T03:20:00.000616+00:00',target))
  self.assertFalse(recovery.replay_at_or_before_target(None,target))

 def test_naive_timestamps_cannot_attest_recovery(self):
  with self.assertRaises(ValueError):recovery.postgres_recovery_target('2026-11-14T03:20:00')
  with self.assertRaises(ValueError):recovery.replay_at_or_before_target('2026-11-14T03:19:59','2026-11-14T03:20:00+00:00')

if __name__=='__main__':unittest.main()
