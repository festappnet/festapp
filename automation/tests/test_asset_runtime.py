"""Canonical Compose/Envoy contraction; requires distribution python3-yaml."""
import copy
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'hetzner-supabase/runtime/prepare-asset-runtime.py'
spec = importlib.util.spec_from_file_location('asset_runtime', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AssetRuntime(unittest.TestCase):
    def fixture(self):
        compose = {'services': {'db': {'image': 'pinned-db', 'environment': {'DB': '${DB:?required}'}},
                                'studio': {'depends_on': {'db': {'condition': 'service_healthy'}}, 'mem_limit': '512m'},
                                'storage': {'depends_on': ['db', 'imgproxy']}, 'imgproxy': {}},
                   'volumes': {'db-data': {}}, 'networks': {'default': {}}}
        clusters = {'resources': [{'name': 'storage'}, {'name': 'auth', 'connect_timeout': '5s'}]}
        listeners = {'resources': [{'filter_chains': [{'filters': [{'typed_config': {'route_config': {'virtual_hosts': [
            {'routes': [{'match': {'prefix': '/storage/v1/'}, 'route': {'cluster': 'storage'}},
                        {'match': {'prefix': '/auth/v1/'}, 'route': {'cluster': 'auth'}}]}]}}}]}]}]}
        return compose, clusters, listeners

    def test_retirement_preserves_every_unrelated_service_and_route(self):
        inputs = self.fixture()
        snapshot = copy.deepcopy(inputs)
        result = module.prepare(*inputs)
        self.assertEqual(inputs, snapshot, 'preparation must not mutate original inputs')
        expected = copy.deepcopy(snapshot)
        for name in ['storage', 'imgproxy']:
            del expected[0]['services'][name]
        expected[1]['resources'].pop(0)
        expected[2]['resources'][0]['filter_chains'][0]['filters'][0]['typed_config']['route_config']['virtual_hosts'][0]['routes'].pop(0)
        self.assertEqual(result, expected)

    def test_new_upstream_consumer_or_route_blocks_retirement(self):
        inputs = self.fixture()
        inputs[0]['services']['other'] = {'environment': {'URL': 'http://imgproxy:5001'}}
        with self.assertRaisesRegex(ValueError, 'remaining_storage_consumer'):
            module.prepare(*inputs)
        inputs = self.fixture()
        inputs[0]['services']['studio']['depends_on']['storage'] = {'condition': 'service_started'}
        with self.assertRaisesRegex(ValueError, 'remaining_storage_consumer'):
            module.prepare(*inputs)
        inputs = self.fixture()
        routes = inputs[2]['resources'][0]['filter_chains'][0]['filters'][0]['typed_config']['route_config']['virtual_hosts'][0]['routes']
        routes[0]['match']['prefix'] = '/another-file-service/'
        with self.assertRaisesRegex(ValueError, 'unreviewed_storage_route'):
            module.prepare(*inputs)


if __name__ == '__main__':
    unittest.main()
