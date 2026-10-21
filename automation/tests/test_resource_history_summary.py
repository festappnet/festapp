import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('summary', Path(__file__).parents[1] /
    'hetzner-supabase/runtime/summarize-resource-history.py')
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


class ResourceSummaryTest(unittest.TestCase):
    def test_distinguishes_simultaneous_usage_missing_samples_and_screen(self):
        budget = {'admin_limits': {'studio': {'mem_limit': 20}}, 'reserve_policy': {
            'os_headroom_target_bytes': 10, 'logical_backup_transient_target_bytes': 10}}
        def container(name, memory):
            return {'name': name, 'memory_bytes': memory, 'working_set_bytes': memory - 5, 'pids': 2}
        samples = [
            {'at': 10, 'host': {'MemTotal': 100, 'MemAvailable': 30},
             'database': {'connections': 4, 'active': 2},
             'edge': {'activeUserWorkersCount': 3},
             'containers': [container('/supabase-studio', 10), container('/db', 40), container('/edge', 10)]},
            {'at': 70, 'host': {'MemTotal': 100, 'MemAvailable': 20},
             'containers': [container('/supabase-studio', 10), container('/db', 10), container('/edge', 50)]},
            {'at': 190, 'host': {'MemTotal': 100, 'MemAvailable': 10},
             'containers': [container('/supabase-studio', 10), {'name': '/db', 'unavailable': True}, container('/edge', 20)]},
        ]
        result = summary.summarize(samples, budget)
        self.assertEqual(result['max_simultaneously_sampled_container_memory_bytes'], 70)
        self.assertEqual(result['incomplete_container_samples'], 1)
        self.assertEqual(result['largest_sample_gap_seconds'], 120)
        self.assertEqual(result['feasibility_screen']['shortfall_before_safety_margin_bytes'], 20)
        self.assertEqual(result['valid_database_samples'], 1)
        self.assertEqual(result['valid_edge_samples'], 1)
        self.assertEqual(result['max_sampled_database_connections'], 4)
        self.assertEqual(result['max_sampled_active_database_connections'], 2)
        self.assertEqual(result['max_sampled_live_edge_workers'], 3)
        missing = summary.summarize(samples[1:], budget)
        self.assertIsNone(missing['max_sampled_live_edge_workers'])
        self.assertIsNone(missing['max_sampled_database_connections'])
        self.assertFalse(result['whole_host_hard_cap_budget_complete'])
        with self.assertRaises(ValueError):
            summary.summarize(samples + [samples[0]], budget)
        with self.assertRaises(ValueError):
            summary.summarize([], budget)


if __name__ == '__main__':
    unittest.main()
