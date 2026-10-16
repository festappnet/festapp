import io,subprocess,tarfile,tempfile,unittest
from pathlib import Path

SCRIPT=Path(__file__).resolve().parents[1]/'hetzner-supabase/backup/archive-runtime.sh'

class RuntimeArchiveTest(unittest.TestCase):
 def fixture(self,base):
  runtime=base/'runtime';system=base/'system'
  for name in ['docker/.env','docker/docker-compose.yml','docker/docker-compose.festapp.yml','docker/docker-compose.database-target.yml','docker/caddy/Caddyfile','docker/volumes/db/roles.sql','docker/volumes/db/data/PG_VERSION','docker/volumes/api/envoy/envoy.yaml','docker/volumes/pooler/pooler.exs','docker/studio-customization/entrypoint.sh']:
   p=runtime/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('synthetic fixture')
  for name in ['docker/volumes/functions','docker/volumes/proxy','docker/volumes/snippets']:(runtime/name).mkdir(parents=True)
  p=system/'etc/festapp-cloudflared/admin-tunnel.token';p.parent.mkdir(parents=True);p.write_text('synthetic fixture only')
  return runtime,system
 def test_complete_archive_keeps_bootstrap_files_and_excludes_live_pgdata(self):
  with tempfile.TemporaryDirectory() as tmp:
   runtime,system=self.fixture(Path(tmp))
   for name in ['etc/festapp-pgbackrest/enabled','etc/festapp-pgbackrest/pgbackrest.conf','etc/festapp-pgbackrest/recovery.json.age','opt/festapp-backup/pgbackrest/Dockerfile','etc/festapp-backup/images.env']:
    p=system/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('fixture')
   result=subprocess.run(['bash',str(SCRIPT),str(runtime),str(system)],capture_output=True,check=True)
   with tarfile.open(fileobj=io.BytesIO(result.stdout)) as archive:
    names=archive.getnames()
    for name in ['docker/volumes/api/envoy/envoy.yaml','docker/volumes/pooler/pooler.exs','docker/studio-customization/entrypoint.sh','docker/volumes/db/roles.sql','etc/festapp-cloudflared/admin-tunnel.token','etc/festapp-pgbackrest/pgbackrest.conf','etc/festapp-pgbackrest/recovery.json.age','opt/festapp-backup/pgbackrest/Dockerfile','etc/festapp-backup/images.env']:self.assertIn(name,names)
    self.assertFalse(any(n.startswith('docker/volumes/db/data') for n in names))
 def test_missing_bootstrap_input_fails_before_any_archive_output(self):
  with tempfile.TemporaryDirectory() as tmp:
   runtime,system=self.fixture(Path(tmp));(runtime/'docker/studio-customization/entrypoint.sh').unlink();(runtime/'docker/studio-customization').rmdir()
   result=subprocess.run(['bash',str(SCRIPT),str(runtime),str(system)],capture_output=True)
   self.assertNotEqual(result.returncode,0);self.assertEqual(result.stdout,b'')
 def test_enabled_pitr_requires_complete_recovery_config(self):
  with tempfile.TemporaryDirectory() as tmp:
   runtime,system=self.fixture(Path(tmp));p=system/'etc/festapp-pgbackrest/enabled';p.parent.mkdir(parents=True);p.touch()
   result=subprocess.run(['bash',str(SCRIPT),str(runtime),str(system)],capture_output=True)
   self.assertNotEqual(result.returncode,0);self.assertEqual(result.stdout,b'')

if __name__=='__main__':unittest.main()
