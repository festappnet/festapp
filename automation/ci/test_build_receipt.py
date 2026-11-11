"""Real tenant source and artifact mutations at the checked reuse boundary."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('build_receipt', Path(__file__).resolve().parents[1]/'release/build_receipt.py')
receipt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(receipt)


FINGERPRINTS={'flutter':'f'*64,'vite':'b'*64,'bundle':'c'*64}
COMPONENTS={name:{'source':'a'*40,'key':FINGERPRINTS[name],'outputHash':'d'*64,'toolchainHash':'e'*64} for name in ['flutter','vite']}
INPUTS={'source':'fixture','componentFingerprints':FINGERPRINTS}
def cache_contract(action,target):
    return FINGERPRINTS if action=='fingerprints' else {'components':COMPONENTS,'inputFingerprints':FINGERPRINTS}

class BuildReceiptTest(unittest.TestCase):
    def test_upload_retry_requires_identical_source_config_tenant_flags_and_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL)
            git('init','-q');git('config','user.email','test@example.invalid');git('config','user.name','Receipt fixture')
            (root/'.gitignore').write_text('/build/\n')
            (root/'automation').mkdir()
            overlay=root/'automation/tenant-overlay.json'
            overlay.write_text(json.dumps({'baseMainSha':'a'*40,'tenantId':'fixture'}))
            config=root/'automation/project.conf';config.write_text('VERSION=1\nDOMAIN=fixture.invalid\n')
            source=root/'app.dart';source.write_text('original')
            git('add','.');git('commit','-qm','tenant source')
            bundle=root/'build/web';bundle.mkdir(parents=True)
            manifest=bundle/'festapp-version.json';manifest.write_text('{"version":"1","main":"main.js"}')
            main=bundle/'main.js';main.write_text('compiled')
            with patch.object(receipt,'ROOT',root),patch.object(receipt,'tools',return_value={'flutter':'fixture'}),patch.object(receipt,'cache_contract',side_effect=cache_contract):
                initial=receipt.inputs('cloudflare')
                receipt.seal(bundle,'cloudflare',initial)
                sealed=manifest.read_bytes()
                # An upload failure does not consume or mutate the artifact.
                first=receipt.verify(bundle,'cloudflare')
                self.assertEqual(receipt.verify(bundle,'cloudflare'),first)
                self.assertEqual(manifest.read_bytes(),sealed)
                with self.assertRaisesRegex(ValueError,'already sealed'):receipt.seal(bundle,'cloudflare',initial)
                for file,content in [(config,'VERSION=2'),(source,'changed'),(overlay,'{"baseMainSha":"a","tenantId":"other"}'),(main,'tampered')]:
                    old=file.read_bytes();file.write_text(content)
                    with self.assertRaises(ValueError):receipt.verify(bundle,'cloudflare')
                    file.write_bytes(old)
                main.chmod(0o755)
                with self.assertRaises(ValueError):receipt.verify(bundle,'cloudflare')
                main.chmod(0o644)
                source.chmod(0o755)
                with self.assertRaises(ValueError):receipt.verify(bundle,'cloudflare')
                source.chmod(0o644)
                with patch.dict(os.environ,{'DART_DEFINES':'changed'}):
                    with self.assertRaises(ValueError):receipt.verify(bundle,'cloudflare')
                with patch.object(receipt,'tools',return_value={'flutter':'different'}):
                    with self.assertRaises(ValueError):receipt.verify(bundle,'cloudflare')
                with self.assertRaises(ValueError):receipt.verify(bundle,'static')
                changed=json.loads(manifest.read_text());changed['version']='2';manifest.write_text(json.dumps(changed))
                with self.assertRaises(ValueError):receipt.verify(bundle,'cloudflare')
                manifest.write_bytes(sealed)
                (bundle/'unexpected.js').write_text('new output')
                with self.assertRaises(ValueError):receipt.verify(bundle,'cloudflare')
                (bundle/'unexpected.js').unlink()
                main.unlink()
                with self.assertRaises(ValueError):receipt.verify(bundle,'cloudflare')
                manifest.write_text('{"version":"1"}')
                with self.assertRaises(KeyError):receipt.verify(bundle,'cloudflare')

    def test_new_build_preserves_sealed_predecessors_under_distinct_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            bundle=Path(directory)/'web';bundle.mkdir()
            (bundle/'festapp-version.json').write_text('{"version":"1"}')
            (bundle/'main.js').write_text('first')
            with patch.object(receipt,'inputs',return_value=INPUTS),patch.object(receipt,'cache_contract',side_effect=cache_contract):
                receipt.seal(bundle,'cloudflare',INPUTS)
                receipt.preserve(bundle)
                self.assertFalse(bundle.exists())
                first=list((Path(directory)/'web-artifacts').iterdir())[0]
                self.assertEqual((first/'main.js').read_text(),'first')
                bundle.mkdir();(bundle/'festapp-version.json').write_text('{"version":"1"}')
                (bundle/'main.js').write_text('second')
                receipt.seal(bundle,'cloudflare',INPUTS)
                receipt.preserve(bundle)
                self.assertEqual(len(list((Path(directory)/'web-artifacts').iterdir())),2)
                self.assertEqual((first/'main.js').read_text(),'first')
                bundle.mkdir();(bundle/'festapp-version.json').write_text('{"version":"1"}')
                (bundle/'main.js').write_text('third')
                receipt.seal(bundle,'cloudflare',INPUTS)
                (bundle/'main.js').write_text('changed after sealing')
                with self.assertRaises(ValueError):receipt.verify(bundle,'cloudflare')
                receipt.preserve(bundle)
                altered=list((Path(directory)/'web-artifacts').glob('unverified-*'))
                self.assertEqual(len(altered),1)
                self.assertEqual((altered[0]/'main.js').read_text(),'changed after sealing')
                self.assertFalse(bundle.exists())

    def test_source_change_during_build_cannot_be_sealed(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'festapp-version.json').write_text('{"version":"1"}')
            (root/'main.js').write_text('compiled')
            with patch.object(receipt,'inputs',return_value={'source':'changed'}):
                with self.assertRaisesRegex(ValueError,'changed during compilation'):
                    receipt.seal(root,'cloudflare',{'source':'original'})
            self.assertNotIn('buildReceipt',json.loads((root/'festapp-version.json').read_text()))
