"""Wallet environment changes preserve the complete installed runtime model."""
from pathlib import Path
import importlib.util,json,unittest
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('wallet_environment',ROOT/'automation/hetzner-supabase/runtime/configure-google-wallet.py')
wallet=importlib.util.module_from_spec(spec);spec.loader.exec_module(wallet)
class WalletEnvironmentTest(unittest.TestCase):
 def credentials(self):
  return {'serviceAccount':{'type':'service_account','project_id':'festapp-d23ef','client_email':'festapp-google-wallet@festapp-d23ef.iam.gserviceaccount.com','token_uri':'https://oauth2.googleapis.com/token','private_key':'-----BEGIN PRIVATE KEY-----\nfixture\n-----END PRIVATE KEY-----\n'},'origins':['https://vstupenky.online']}
 def test_private_key_remains_one_quoted_env_value_and_existing_inputs_survive(self):
  env,overlay,values=wallet.planned_files('COMPOSE_FILE=base.yml:email.yml\nUNCHANGED=value\n','services:\n  functions:\n    environment:\n      EMAIL_PAYLOAD_KEY: ${EMAIL_PAYLOAD_KEY}\n',self.credentials())
  self.assertIn('COMPOSE_FILE=base.yml:email.yml\nUNCHANGED=value\n',env)
  line=next(x for x in env.splitlines() if x.startswith('GOOGLE_WALLET_SERVICE_ACCOUNT='))
  self.assertEqual(json.loads(line.partition('=')[2][1:-1]),self.credentials()['serviceAccount'])
  self.assertEqual(overlay.count('      GOOGLE_WALLET_SERVICE_ACCOUNT: '),1)
  again=wallet.planned_files(env,overlay,self.credentials())
  self.assertEqual(again,(env,overlay,values))
 def test_wrong_project_account_or_origin_are_rejected(self):
  for path,value in [('project_id','another-project'),('client_email','another@example.invalid')]:
   c=self.credentials();c['serviceAccount'][path]=value
   with self.assertRaises(RuntimeError):wallet.planned_files('','',c)
  c=self.credentials();c['origins']=['https://another.invalid']
  with self.assertRaises(RuntimeError):wallet.planned_files('','',c)
 def test_unrelated_model_drift_is_rejected(self):
  before={'services':{'functions':{'environment':{'UNCHANGED':'keep'},'image':'pinned'},'db':{'image':'pinned-db'}}}
  after=json.loads(json.dumps(before));after['services']['functions']['environment'].update({'GOOGLE_WALLET_ALLOWED_ORIGINS':'https://vstupenky.online'})
  wallet.assert_bounded_model(before,after,{'GOOGLE_WALLET_ALLOWED_ORIGINS':'https://vstupenky.online'})
  after['services']['db']['image']='changed'
  with self.assertRaises(RuntimeError):wallet.assert_bounded_model(before,after,{'GOOGLE_WALLET_ALLOWED_ORIGINS':'https://vstupenky.online'})
if __name__=='__main__':unittest.main()
