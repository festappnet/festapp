import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import docker_cache as cache


class CmsBaseImageCacheTest(unittest.TestCase):
    identity='sha256:'+'a'*64
    digest='wordpress@sha256:'+'b'*64

    def entry(self, directory, **changes):
        (directory/'images.tar').write_bytes(b'only immutable image layers')
        manifest={'key':'fixture-key','sha256':cache.digest_file(directory/'images.tar'),
                  'images':[{'id':self.identity,'digests':[self.digest]}]}
        manifest.update(changes)
        (directory/'manifest.json').write_text(json.dumps(manifest))

    @patch.object(cache,'key',return_value='fixture-key')
    def test_missing_corrupt_foreign_or_unbound_cache_never_loads(self,_):
        with tempfile.TemporaryDirectory() as tmp, patch.object(cache,'docker') as docker:
            d=Path(tmp)
            self.assertFalse(cache.restore(d))
            for changes in [{'key':'other-runtime'}, {'sha256':'wrong'},
                            {'images':[{'id':self.identity,'digests':['untrusted/image@sha256:'+'b'*64]}]},
                            {'images':[{'id':'mutable-tag','digests':[self.digest]}]},
                            {'images':[]}]:
                self.entry(d,**changes)
                self.assertFalse(cache.restore(d))
            docker.assert_not_called()

    @patch.object(cache,'key',return_value='fixture-key')
    def test_loaded_content_identity_must_match_and_warm_save_does_no_work(self,_):
        with tempfile.TemporaryDirectory() as tmp:
            d=Path(tmp);self.entry(d)
            with patch.object(cache,'docker',side_effect=[b'',json.dumps([{'Id':self.identity}]).encode()]) as docker:
                self.assertTrue(cache.restore(d))
                docker.assert_any_call('image','load','--input',str(d/'images.tar'))
            with patch.object(cache,'docker') as docker:
                self.assertTrue(cache.save(d));docker.assert_not_called()
            with patch.object(cache,'docker',side_effect=[b'',b'[{"Id":"wrong"}]']):
                self.assertFalse(cache.restore(d))
            self.assertFalse((d/'verified-key').exists())

    @patch.object(cache,'key',return_value='fixture-key')
    def test_export_excludes_local_builds_and_unrelated_upstream_images(self,_):
        with tempfile.TemporaryDirectory() as tmp:
            d=Path(tmp)
            rows=[{'Id':self.identity,'RepoDigests':[self.digest]},
                  {'Id':'local-build-with-fixture-data','RepoDigests':[]},
                  {'Id':'unrelated','RepoDigests':['other/image@sha256:'+'c'*64]}]
            def docker(*args):
                if args[:2]==('image','ls'):return b'one\ntwo\nthree\n'
                if args[:2]==('image','inspect'):return json.dumps(rows).encode()
                self.assertEqual(args,('image','save','--output',str(d/'images.pending.tar'),self.identity))
                (d/'images.pending.tar').write_bytes(b'public image')
                return b''
            with patch.object(cache,'docker',side_effect=docker):self.assertTrue(cache.save(d))
            manifest=json.loads((d/'manifest.json').read_text())
            self.assertEqual(manifest['images'],[{'id':self.identity,'digests':[self.digest]}])
            self.assertEqual(manifest['sha256'],cache.digest_file(d/'images.tar'))

    def test_key_changes_with_pinned_inputs_and_platform(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'pin').write_text('runtime-a')
            with patch.object(cache,'ROOT',root),patch.object(cache,'INPUTS',('pin',)),patch.dict(cache.os.environ,{'RUNNER_ARCH':'X64'}):
                first=cache.key();(root/'pin').write_text('runtime-b')
                self.assertNotEqual(first,cache.key())
                second=cache.key()
                with patch.dict(cache.os.environ,{'RUNNER_ARCH':'ARM64'}):self.assertNotEqual(second,cache.key())

    def test_prefetch_is_only_the_configured_public_wordpress_bases(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);config=root/'integrations/wordpress/.wp-env.json'
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({'phpVersion':'8.5','env':{'tests':{'phpVersion':'7.4'}}}))
            with patch.object(cache,'ROOT',root),patch.object(cache,'docker',return_value=b'') as docker:
                refs=cache.wordpress_refs()
                self.assertEqual(refs,['wordpress:cli-php7.4','wordpress:cli-php8.5','wordpress:php7.4','wordpress:php8.5'])
                self.assertTrue(cache.prefetch_wordpress())
                self.assertEqual({call.args for call in docker.call_args_list},{('pull',ref) for ref in refs})
                config.write_text(json.dumps({'phpVersion':'8.5; untrusted'}))
                with self.assertRaises(ValueError):cache.wordpress_refs()
