"""Exercise the production Stripe environment declarations through real Compose."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

@unittest.skipUnless(shutil.which('docker'), 'Docker Compose CLI required')
class StripeRuntimeConfigTest(unittest.TestCase):
    def render(self, values):
        source = (ROOT / 'automation/hetzner-supabase/runtime/docker-compose.festapp.yml').read_text()
        declarations = re.findall(r'^      STRIPE_[A-Z_]+:.*$', source, re.M)
        self.assertEqual(len(declarations), 8, 'the runtime must forward the complete configuration')
        environment = {k: v for k, v in os.environ.items() if not k.startswith('STRIPE_')}
        environment.update(values)
        with tempfile.TemporaryDirectory(prefix='festapp-stripe-compose-') as directory:
            path = Path(directory) / 'compose.yml'
            path.write_text('services:\n  functions:\n    image: scratch\n    environment:\n' + '\n'.join(declarations) + '\n')
            result = subprocess.run((['docker-compose'] if shutil.which('docker-compose') else ['docker', 'compose']) + ['-f', str(path), 'config', '--format', 'json'],
                                    env=environment, text=True, capture_output=True, check=True)
        return json.loads(result.stdout)['services']['functions']['environment']

    def test_unprovisioned_runtime_remains_disabled(self):
        actual = self.render({})
        self.assertEqual(actual['STRIPE_MODE'], '')
        self.assertEqual(actual['STRIPE_SECRET_KEY'], '')
        self.assertEqual(json.loads(actual['STRIPE_ALLOWED_ORIGINS']), [])
        self.assertEqual(json.loads(actual['STRIPE_WEBHOOK_SECRETS']), [])

    def test_provisioned_values_reach_functions_without_value_rewriting(self):
        values = {
            'STRIPE_MODE': 'test', 'STRIPE_SECRET_KEY': 'sk_test_fixture123',
            'STRIPE_PLATFORM_ACCOUNT_ID': 'acct_fixture', 'STRIPE_API_VERSION': '2025-06-30.basil',
            'STRIPE_ALLOWED_ORIGINS': '["https://fixture.invalid"]',
            'STRIPE_CONNECT_CLIENT_ID': 'ca_fixture',
            'STRIPE_CONNECT_CALLBACK_URL': 'https://fixture.invalid/stripe/connect/callback',
            'STRIPE_WEBHOOK_SECRETS': '["whsec_fixture123"]',
        }
        self.assertEqual(self.render(values), values)
        schema = json.loads((ROOT / 'automation/private-inputs.schema.json').read_text())
        self.assertTrue(set(values) <= schema['properties'].keys())
        self.assertEqual(set(schema['x-operationRequirements']['stripeConnectPreview']), set(values) - {'STRIPE_WEBHOOK_SECRETS'})

if __name__ == '__main__':
    unittest.main()
