import copy
import importlib.util
from pathlib import Path
import unittest

path=Path(__file__).resolve().parents[1]/'hetzner-supabase/runtime/configure-apple-wallet.py'
spec=importlib.util.spec_from_file_location('apple_wallet_runtime',path)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class AppleWalletRuntimeTest(unittest.TestCase):
    def test_only_wallet_inputs_change_and_repeat_is_idempotent(self):
        env='EMAIL_PAYLOAD_KEY=protected\nCOMPOSE_FILE=all:overlays\n'
        overlay='services:\n  functions:\n    environment:\n      EMAIL_PAYLOAD_KEY: ${EMAIL_PAYLOAD_KEY:?required}\n'
        credentials={'passTypeIdentifier':'pass.net.festapp.tickets','teamIdentifier':'8WKBB6L8LT','signerCert':'public certificate','signerKey':'private test input\nnext line','wwdr':'public certificate'}
        after_env,after_overlay,values=module.planned_files(env,overlay,credentials)
        self.assertTrue(after_env.startswith(env));self.assertEqual(set(values),set(module.KEYS))
        self.assertIn('      EMAIL_PAYLOAD_KEY: ${EMAIL_PAYLOAD_KEY:?required}',after_overlay)
        self.assertEqual(module.planned_files(after_env,after_overlay,credentials)[:2],(after_env,after_overlay))
        before={'services':{'functions':{'image':'pinned','environment':{'EMAIL_PAYLOAD_KEY':'protected'}},'auth':{'environment':{'KEEP':'yes'}}}}
        after=copy.deepcopy(before);after['services']['functions']['environment'].update(values)
        module.assert_bounded_model(before,after,values)
        after['services']['auth']['environment']['KEEP']='no'
        with self.assertRaises(RuntimeError):module.assert_bounded_model(before,after,values)
    def test_rejects_identity_changes_and_dotenv_injection(self):
        base={'passTypeIdentifier':'pass.net.festapp.tickets','teamIdentifier':'8WKBB6L8LT','signerCert':'public','signerKey':'private','wwdr':'public'}
        for change in [{'passTypeIdentifier':'pass.other'},{'signerKey':"'\nEVIL=1"},{'signerKey':'${ENV}'},{'unknown':'value'}]:
            with self.assertRaises(RuntimeError):module.planned_files('','',{**base,**change})

if __name__=='__main__':unittest.main()
