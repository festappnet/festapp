import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import threading
import unittest
from contextlib import redirect_stdout
from http.server import HTTPServer
from unittest.mock import patch
import urllib.error
import urllib.request

spec = importlib.util.spec_from_file_location('broker', Path(__file__).with_name('broker.py'))
broker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(broker)


class BrokerTests(unittest.TestCase):
    def setUp(self):
        self.secret = 'synthetic-test-secret'
        self.config = {'token_sha256': hashlib.sha256(self.secret.encode()).hexdigest(),
                       'expires_at': 200, 'revoked': False}
        self.body = {'operation': 'probe', 'tenant': 'festapp', 'organization': 1}
        self.headers = {'X-Festapp-Agent-Token': self.secret}

    def test_authentication_expiry_and_revocation(self):
        self.assertEqual(broker.authorize(self.config, self.headers, self.body, 100), 'probe')
        for headers, config in [({}, self.config),
                                ({'X-Festapp-Agent-Token': 'wrong'}, self.config),
                                (self.headers, {**self.config, 'revoked': True}),
                                (self.headers, {**self.config, 'expires_at': 100})]:
            with self.assertRaises(broker.Denied):
                broker.authorize(config, headers, self.body, 100)

    def test_scope_and_operations(self):
        for change in [{'tenant': 'csm'}, {'organization': 2}, {'organization': True},
                       {'operation': 'release'}, {'operation': "probe; DROP TABLE orders"},
                       {'sql': 'select 1'}]:
            with self.assertRaises(broker.Denied):
                broker.authorize(self.config, self.headers, {**self.body, **change}, 100)

    def test_http_denial_size_limit_and_secret_free_audit(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'config.json'
            config.write_text(json.dumps({**self.config, 'expires_at': 9999999999}))
            server = HTTPServer(('127.0.0.1', 0), broker.Handler)
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            logs = io.StringIO()
            try:
                with patch.object(broker, 'CONFIG', config), patch.object(broker, 'query', return_value={'ok': True}) as query, redirect_stdout(logs):
                    worker.start()
                    url = f'http://127.0.0.1:{server.server_port}/v1/diagnostics'
                    def request(body, headers):
                        req = urllib.request.Request(url, data=body, headers=headers)
                        try:
                            with urllib.request.urlopen(req, timeout=2) as response:
                                return response.status
                        except urllib.error.HTTPError as error:
                            status = error.code
                            error.close()
                            return status
                    valid = json.dumps(self.body).encode()
                    self.assertEqual(request(valid, {}), 403)
                    self.assertEqual(request(b'x' * 1025, self.headers), 403)
                    self.assertEqual(request(json.dumps({**self.body, 'organization': 2}).encode(), self.headers), 403)
                    query.assert_not_called()
                    self.assertEqual(request(valid, self.headers), 200)
                    query.assert_called_once_with('probe')
                self.assertNotIn(self.secret, logs.getvalue())
                self.assertEqual(len(logs.getvalue().splitlines()), 4)
            finally:
                server.shutdown()
                server.server_close()
                worker.join(timeout=2)

    def test_database_identity_and_output_limits(self):
        from types import SimpleNamespace
        correct = {'database': broker.DATABASE, 'role': broker.ROLE, 'organization': 1}
        for output in [b'x' * 16385, json.dumps({**correct, 'database': 'other'}).encode(),
                       json.dumps({**correct, 'organization': 2}).encode()]:
            with patch.object(broker.subprocess, 'run', return_value=SimpleNamespace(stdout=output)):
                with self.assertRaises(broker.Denied):
                    broker.query('probe')
        with patch.object(broker.subprocess, 'run', return_value=SimpleNamespace(stdout=json.dumps(correct).encode())) as run:
            self.assertEqual(broker.query('probe'), correct)
            args = run.call_args
            self.assertEqual(args.kwargs['timeout'], 6)
            self.assertIn('BEGIN READ ONLY', args.args[0][-1])
            self.assertIn('statement_timeout=3000', args.args[0][-1])


if __name__ == '__main__':
    unittest.main()
