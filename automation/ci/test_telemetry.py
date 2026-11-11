import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from telemetry import input_identity, phase, run_directory, write_receipt, measured_process
from telemetry import ContainerMemory, execution_identity
import selection


class TelemetryTest(unittest.TestCase):
    def test_hosted_identity_records_actual_checkout_and_api_outage_does_not_block_tests(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            subprocess.run(['git','init','-q',str(root)],check=True)
            subprocess.run(['git','-C',str(root),'-c','user.name=Test','-c','user.email=test@example.invalid',
                            'commit','--allow-empty','-qm','actual checkout'],check=True)
            sha=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
            contract={'jobs':{'fixture':{'workflow':'fixture.yml','node':'22.23.4','inputs':['**']}},
                      'knownTestInputs':[]}
            env={'GITHUB_ACTIONS':'true','GITHUB_REPOSITORY':'fixture/repo','GITHUB_REPOSITORY_ID':'7',
                 'GITHUB_RUN_ID':'123','GITHUB_RUN_ATTEMPT':'2','GITHUB_EVENT_NAME':'pull_request',
                 'GITHUB_SHA':'untrusted-head-metadata'}
            with patch.dict(os.environ,env),patch.object(selection,'ROOT',root), \
                 patch.object(selection,'api',return_value={'jobs':[{'name':'fixture','id':456}]}) as api:
                identity=execution_identity(root,'fixture',contract)
                self.assertEqual(identity['checkoutSha'],sha)
                self.assertNotEqual(identity['checkoutSha'],env['GITHUB_SHA'])
                self.assertEqual(identity['jobId'],456)
                self.assertEqual(identity['attempt'],2)
                api.assert_called_once_with('fixture/repo','actions/runs/123/attempts/2/jobs?per_page=100')
                api.side_effect=OSError('offline')
                self.assertIsNone(execution_identity(root,'fixture',contract))

    def test_docker_stream_cursor_controls_do_not_discard_memory_samples(self):
        with patch('telemetry.subprocess.Popen') as popen:
            popen.return_value.stdout=['\x1b[H{"MemUsage":"212.7MiB / 3.814GiB"}\x1b[K\n']
            sampler=ContainerMemory('supabase_db_festapp-fixture')
            sampler.start();sampler.close()
            self.assertEqual(sampler.samples,1)
            self.assertEqual(sampler.peak,int(212.7*1024**2))

    def test_parallel_run_receipts_keep_both_histories(self):
        with tempfile.TemporaryDirectory() as temporary:
            cache = Path(temporary)
            first, second = run_directory(cache), run_directory(cache)
            write_receipt(first, {'complete': True}, cache)
            write_receipt(second, {'complete': False}, cache)
            self.assertNotEqual(first, second)
            self.assertTrue(json.loads((first / 'receipt.json').read_text())['complete'])
            self.assertEqual(json.loads((cache / 'latest.json').read_text())['receipt'], str(second / 'receipt.json'))

    def test_failed_phase_is_recorded_without_secrets(self):
        with tempfile.TemporaryDirectory() as temporary:
            trace = Path(temporary) / 'trace.jsonl'
            with patch.dict(os.environ, FESTAPP_TIMINGS=str(trace)):
                with self.assertRaises(ValueError):
                    with phase('fixture'):
                        raise ValueError('secret')
            event = json.loads(trace.read_text())
            self.assertFalse(event['success'])
            self.assertGreaterEqual(event['seconds'], 0)
            self.assertNotIn('secret', trace.read_text())

    def test_content_change_under_same_filename_invalidates_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            subprocess.run(['git', '-C', str(root), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '--allow-empty', '-qm', 'fixture'], check=True)
            source = root / 'migration.sql'
            source.write_text('select 1;')
            before = input_identity(root)
            source.write_text('select 2;')
            after = input_identity(root)
            self.assertEqual(before['head'], after['head'])
            self.assertNotEqual(before['inputSha256'], after['inputSha256'])

    def test_failed_process_retains_exit_and_memory(self):
        code, seconds, peak = measured_process(['python3', '-c', 'import time; time.sleep(.3); raise SystemExit(17)'])
        self.assertEqual(code, 17)
        self.assertGreater(seconds, .2)
        self.assertGreater(peak, 0)


if __name__ == '__main__':
    unittest.main()
