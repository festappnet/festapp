import datetime
import importlib.util
import io
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('proxy', Path(__file__).with_name('proxy.py'))
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)


class ProxyTests(unittest.TestCase):
    def setUp(self):
        self.config = {'hostname': 'synthetic.festapp.net', 'client_id': 'synthetic.access',
                       'client_secret': 'synthetic-private-value',
                       'expires_at': (datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(days=1)).isoformat()}

    def result(self, config):
        return SimpleNamespace(stdout=json.dumps(config).encode())

    def test_secrets_stay_out_of_command_arguments(self):
        with patch.object(proxy.subprocess, 'run', return_value=self.result(self.config)), \
             patch.object(proxy.os, 'execvpe') as execute:
            proxy.main()
        _, argv, env = execute.call_args.args
        self.assertEqual(argv, ['cloudflared', 'access', 'ssh', '--hostname', self.config['hostname']])
        self.assertNotIn(self.config['client_secret'], argv)
        self.assertEqual(env['TUNNEL_SERVICE_TOKEN_SECRET'], self.config['client_secret'])

    def test_expired_missing_and_invalid_target_fail_before_launch(self):
        for change in [{'expires_at': '2000-01-01T00:00:00Z'}, {'client_secret': ''},
                       {'hostname': 'untrusted.example'}, {'hostname': 'x.festapp.net --extra'},
                       {'client_id': 'wrong'}]:
            with patch.object(proxy.subprocess, 'run', return_value=self.result({**self.config, **change})), \
                 patch.object(proxy.os, 'execvpe') as execute, patch('sys.stderr', new=io.StringIO()):
                with self.assertRaises(SystemExit):
                    proxy.main()
                execute.assert_not_called()

    def test_malformed_credential_logs_no_secret(self):
        stream = io.StringIO()
        with patch.object(proxy.subprocess, 'run', return_value=SimpleNamespace(stdout=b'{synthetic-private-value')), \
             patch.object(proxy.os, 'execvpe') as execute, patch('sys.stderr', new=stream):
            with self.assertRaises(SystemExit):
                proxy.main()
            execute.assert_not_called()
        self.assertNotIn('synthetic-private-value', stream.getvalue())


if __name__ == '__main__':
    unittest.main()
