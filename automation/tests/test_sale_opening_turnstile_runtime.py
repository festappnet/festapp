import importlib.util
from pathlib import Path
import unittest

path=Path(__file__).resolve().parents[1]/'hetzner-supabase/runtime/configure-sale-opening-turnstile.py'
spec=importlib.util.spec_from_file_location('turnstile_runtime',path)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class TurnstileRuntimeTest(unittest.TestCase):
    def test_preserves_unrelated_inputs_and_installs_three_exact_names(self):
        env='EMAIL_PAYLOAD_KEY=protected\nCOMPOSE_FILE=all:overlays\n'
        overlay='services:\n  functions:\n    environment:\n      EMAIL_PAYLOAD_KEY: ${EMAIL_PAYLOAD_KEY:?required}\n'
        credentials={'mode':'managed','domains':['vstupenky.online','localhost'],'sitekey':'0x-public','secret':'0x-private'}
        after_env,after_overlay,values=module.planned_files(env,overlay,credentials)
        self.assertTrue(after_env.startswith(env))
        self.assertEqual(len(values),3)
        self.assertEqual(values[module.KEYS[2]],'vstupenky.online')
        self.assertIn('      EMAIL_PAYLOAD_KEY: ${EMAIL_PAYLOAD_KEY:?required}',after_overlay)
        self.assertEqual(module.planned_files(after_env,after_overlay,credentials)[:2],(after_env,after_overlay))
        before={'services':{'functions':{'image':'pinned','environment':{'EMAIL_SES_SECRET_ACCESS_KEY':'protected'}},'auth':{'environment':{'KEEP':'yes'}}}}
        import copy
        after=copy.deepcopy(before);after['services']['functions']['environment'].update(values)
        module.assert_bounded_model(before,after,values)
        after['services']['auth']['environment']['KEEP']='no'
        with self.assertRaises(RuntimeError):module.assert_bounded_model(before,after,values)
    def test_rejects_dummy_keys_and_unexpected_overlay(self):
        for site in ['1x00000000000000000000AA','bad\nENV=attack']:
            with self.assertRaises(RuntimeError):module.planned_files('','',{'mode':'managed','domains':['vstupenky.online'],'sitekey':site,'secret':'0x-private'})

if __name__=='__main__':unittest.main()
