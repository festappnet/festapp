"""Exercise the real update journal and its command failure boundary.

Docker/SQL transport is replaced here; actual containers, HTTP, PITR, key
compatibility and index work are covered by the separate native rehearsal.
"""
import copy
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import time
import unittest
from unittest.mock import patch
import urllib.error

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT/'automation/hetzner-supabase/runtime'
spec = importlib.util.spec_from_file_location('runtime_update', RUNTIME/'apply-runtime-update.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class FakeRuntime:
    def __init__(self, folder):
        self.root = folder/'installed'
        self.package = folder/'package'
        self.state = folder/'state'
        self.root.mkdir()
        self.package.mkdir(mode=0o700)
        self.source = 'a'*40
        self.old_db = 'sha256:'+'1'*64
        self.new_db = 'sha256:'+'2'*64
        self.db_image = self.old_db
        self.paused = False
        self.jobs = [{'id':10,'active':True},{'id':12,'active':False}]
        self.calls = []
        self.fail_services = True
        self.fail_database = False
        self.database_running = True
        self.stale_caddy = False
        self.replace_db_mount = False
        self.current_new = False
        self.timers = {m.QUIET_TIMERS[0]:'active',m.QUIET_TIMERS[1]:'inactive'}
        pins = json.loads((RUNTIME/'pins.json').read_text())
        self.images = {service:pins['supabase']['images'][key] for service,key in m.IMAGE_SERVICES.items()}
        self.images['db'] = self.new_db
        self.compose_files = ['docker-compose.yml','docker-compose.festapp.yml','docker-compose.database-target.yml',
            'docker-compose.email.yml','docker-compose.pgbackrest.yml','docker-compose.resource-budget.yml']
        self.env = {'SUPABASE_DB_URL':'postgresql://postgres:fixture@db:5432/'+m.DATABASE,
            'APP_LINKS_ORGANIZATION_ID':'3','SUPABASE_ANON_KEY':'fixture-anon','SUPABASE_SERVICE_ROLE_KEY':'fixture-service'}
        required = ['EMAIL_SES_ACCOUNT_ID','EMAIL_SES_REGION','EMAIL_SES_ACCESS_KEY_ID','EMAIL_SES_SECRET_ACCESS_KEY',
            'EMAIL_SES_TRANSACTIONAL_SET','EMAIL_SES_SECURITY_SET','EMAIL_PAYLOAD_KEY','EMAIL_SNS_TOPIC_ARN',
            'AUTH_EMAIL_PUBLIC_URL','AUTH_EMAIL_HOOK_SECRET','FESTAPP_MONITORING_URL','FESTAPP_MONITORING_TOKEN','DEFAULT_EMAIL']
        self.env.update({key:'fixture-only' for key in required})
        self.model = {'services':{service:{'image':'fixture/'+service+':old'} for service in self.images}}
        self.model['services']['db']['image'] = self.old_db
        self.model['services']['db']['volumes'] = [{'type':'volume','source':'fixture-data','target':'/var/lib/postgresql/data'}]
        self.model['services']['functions'].update({'environment':self.env,'command':['start','--main-service','/home/deno/functions/main']})
        self.model['services']['api-gw'].update({'command':None,'entrypoint':['/bin/sh','/docker-entrypoint.sh']})
        self.model['services']['auth']['command'] = None
        self.model['services']['supavisor']['command'] = ['/bin/sh','-c','exec pooler eval "$$(cat /etc/pooler/pooler.exs)"']
        self.actual_commands = {'api-gw':None,'auth':['auth'], 'supavisor':['/bin/sh','-c','exec pooler eval "$(cat /etc/pooler/pooler.exs)"']}
        self.desired = copy.deepcopy(self.model)
        for service,image in self.images.items():
            self.desired['services'][service]['image'] = image
        self.desired['services']['functions'].update({'mem_limit':'2147483648',
            'command':['start','--user-worker-request-idle-timeout','150000','--main-service','/home/deno/functions/main']})
        self.desired['services']['functions']['environment']['DENO_TLS_CA_STORE'] = 'system,mozilla'
        self.mounts = [{'Type':'volume','Name':'fixture-data','Destination':'/var/lib/postgresql/data','RW':True},
            {'Type':'volume','Name':'fixture-keys','Destination':'/etc/postgresql-custom','RW':True}]
        names = set(self.compose_files) | m.FILES | {'caddy/Caddyfile'}
        self.caddy = '(festapp_supabase_proxy) {\n\treverse_proxy 127.0.0.1:8000 {\n\t\theader_up X-Real-IP {client_ip}\n\t}\n}\n'
        for name in names:
            path=self.root/name
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text(self.caddy if name=='caddy/Caddyfile' else 'original '+name)
        (self.root/'.env').write_text('COMPOSE_FILE='+':'.join(self.compose_files)+'\nFESTAPP_PGBACKREST_DB_IMAGE='+self.old_db+'\nJWT_SECRET=fixture-preserved-key\n')
        for name in m.FILES:
            path=self.package/name
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text('candidate '+name)
        self.manifest = {'manifest_version':1,'source_sha':self.source,'target':m.TARGET,'files':{name:m.digest(self.package/name) for name in m.FILES},
            'rehearsal':{'status':'pass','upgrade_seconds':60,'rollback_seconds':60},'postgres_version_num':'170012',
            'db_image':self.new_db,'baseline_db_image':self.old_db,'baseline_files':{name:m.digest(self.root/name) for name in names},'images':self.images}
        (self.package/'manifest.json').write_text(json.dumps(self.manifest))

    def args(self, **updates):
        values=dict(package=self.package,source_sha=self.source,target=m.TARGET,ack=m.ACK,dry_run=False,resume=False,rollback=False)
        values.update(updates)
        return SimpleNamespace(**values)

    def execute(self, args, **kwargs):
        self.calls.append(list(args))
        output=''
        code=0
        if args[:4] == ['docker','exec','festapp-caddy','stat']:
            value=(self.root/'caddy/Caddyfile').stat()
            output=str(value.st_dev)+':'+str(value.st_ino+int(self.stale_caddy))
        elif args[:2] == ['docker','inspect']:
            name=args[2]
            if name=='supabase-db':
                result={'Image':self.db_image,'Mounts':self.mounts}
            elif name=='supabase-edge-functions':
                config=(self.desired if self.current_new else self.model)['services']['functions']
                result={'State':{'Running':True},'Config':{'Image':config['image'],'Cmd':config['command'],
                    'Env':[key+'='+value for key,value in config['environment'].items()]},
                    'NetworkSettings':{'Networks':{'fixture':{'IPAddress':'127.0.0.1'}}}}
            elif name in m.MCP:
                result={'State':{'Running':True}}
            elif name.startswith('fixture-container-'):
                service=name.removeprefix('fixture-container-')
                wanted=self.model['services'][service]
                result={'Image':self.old_db if service=='db' else 'sha256:'+'3'*64,
                    'State':{'Running':True},'Config':{'Env':[k+'='+v for k,v in wanted.get('environment',{}).items()],
                    'Cmd':self.actual_commands.get(service,wanted.get('command',[]))}}
            else:
                result={'Architecture':'arm64','Config':{'Cmd':['auth']}}
            output=json.dumps([result])
        elif args[:2] == ['docker','ps']:
            output='' if '--filter' in args else 'supabase-db\nsupabase-edge-functions\n'
        elif args[:2] == ['docker','logs']:
            output='festapp_runtime_resource_metrics '+json.dumps({'at':time.time()*1000,
                'receivedRequestsCount':7,'handledRequestsCount':7})
        elif 'pgbackrest' in args and 'info' in args:
            output=json.dumps([{'status':{'code':0},'backup':[{'label':'20261115-031358F','error':False,'timestamp':{'stop':time.time()}}]}])
        elif 'psql' in args:
            if not self.database_running:
                return SimpleNamespace(returncode=1,stdout='')
            query=args[-1]
            if 'UPDATE public.email_capacity' in query:
                self.paused='paused=true' in query
            elif 'UPDATE cron.job' in query:
                active='active=true' in query
                for job in self.jobs:
                    if 'WHERE active' in query or 'jobid='+str(job['id']) in query:
                        job['active']=active
            elif 'SELECT paused ' in query:
                output='t' if self.paused else 'f'
            elif 'json_agg(json_build_object' in query:
                output=json.dumps(self.jobs)
            elif 'SELECT datname ' in query:
                output='\n'.join(sorted([m.DATABASE,'postgres','_supabase','template1']))
            elif 'SELECT extversion' in query or "SELECT format('REINDEX" in query:
                output=''
            elif 'server_version_num' in query:
                output='170012'
            elif 'pg_current_wal_lsn' in query:
                output='26/50000000'
            else:
                output='t'
        elif args[:2] == ['docker','compose']:
            if 'config' in args:
                candidate='candidate.env' in args[args.index('--env-file')+1] or self.new_db in (self.root/'.env').read_text()
                output=json.dumps(self.desired if candidate else self.model)
            elif 'ps' in args:
                output='fixture-container-'+args[-1]
            elif 'up' in args and args[-1]=='db':
                self.mounts.reverse()
                if self.replace_db_mount:self.mounts[0]['Name']='replacement-keys'
                if self.fail_database:
                    code=1
                    self.database_running=False
                else:
                    self.db_image=self.new_db if self.new_db in (self.root/'.env').read_text() else self.old_db
                    self.database_running=True
            elif 'up' in args:
                if self.fail_services:
                    code=1
                else:
                    self.current_new=self.new_db in (self.root/'.env').read_text()
        elif args[0]=='curl':
            output='200' if '--write-out' in args else 'HTTP/2 503\nRetry-After: 60\nCache-Control: no-store\n'
        elif args[0]=='systemctl':
            if 'show' in args:
                output=self.timers.get(args[-1],'inactive')
            else:
                self.timers[args[-1]]='active' if args[1]=='start' else 'inactive'
        return SimpleNamespace(returncode=code,stdout=output)


class RuntimeUpdateTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.fake=FakeRuntime(Path(self.temp.name))
        boot_id=Path(self.temp.name)/'boot-id'
        boot_id.write_text('fixture-boot-id')
        meminfo=Path(self.temp.name)/'meminfo'
        meminfo.write_text('MemAvailable: 1048576 kB\n')
        for name,value in [('ROOT',self.fake.root),('STATE',self.fake.state),('BACKUP_LOCK',Path(self.temp.name)/'backup.lock'),('BOOT_ID_PATH',boot_id),('MEMINFO_PATH',meminfo)]:
            patcher=patch.object(m,name,value)
            patcher.start()
            self.addCleanup(patcher.stop)
        for patcher in [patch.object(m.os,'geteuid',return_value=0),
            patch.object(m.os,'uname',return_value=SimpleNamespace(nodename=m.HOST)),
            patch.object(m,'require_private_root'),patch.object(m.subprocess,'run',side_effect=self.fake.execute),
            patch('urllib.request.urlopen',side_effect=urllib.error.HTTPError('fixture',401,'Unauthorized',{},None))]:
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_wrong_target_cannot_run_commands(self):
        with self.assertRaises(RuntimeError):m.apply(self.fake.args(target='other.invalid'))
        self.assertFalse(self.fake.calls)

    def test_runtime_lock_is_exclusive(self):
        with (self.fake.root/'.festapp-runtime-upgrade.lock').open('a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            with self.assertRaises(BlockingIOError):m.apply(self.fake.args())
        self.assertFalse(self.fake.calls)

    def test_dry_run_never_mutates_sql_or_restarts(self):
        before=(self.fake.root/'.env').read_bytes()
        m.apply(self.fake.args(dry_run=True))
        self.assertEqual((self.fake.root/'.env').read_bytes(),before)
        self.assertFalse((self.fake.state/'state.json').exists())
        self.assertFalse(any('stop' in call or 'up' in call or 'restart' in call for call in self.fake.calls))
        self.assertFalse(any('UPDATE ' in call[-1] for call in self.fake.calls))

    def test_changed_inherited_image_command_is_rejected_before_mutation(self):
        self.fake.actual_commands['auth'] = ['unexpected-override']
        with self.assertRaisesRegex(RuntimeError,'command drift: auth'):
            m.apply(self.fake.args(dry_run=True))
        self.assertFalse((self.fake.state/'state.json').exists())
        self.assertFalse(any('stop' in call or 'up' in call for call in self.fake.calls))

    def test_stale_caddy_inode_stops_before_pause(self):
        self.fake.stale_caddy=True
        with self.assertRaisesRegex(RuntimeError,'stale inode'):
            m.apply(self.fake.args(dry_run=True))
        self.assertFalse(self.fake.paused)
        self.assertFalse((self.fake.state/'state.json').exists())

    def test_actual_key_mount_replacement_is_rejected_before_service_migrations(self):
        self.fake.replace_db_mount=True
        with self.assertRaisesRegex(RuntimeError,'mount identity changed'):
            m.apply(self.fake.args())
        state=json.loads((self.fake.state/'state.json').read_text())
        self.assertFalse(state['migration_point'])
        self.assertNotIn('database_updated',state['done'])

    def test_partial_migration_failure_retains_fence_and_resume_skips_database_restart(self):
        with self.assertRaises(RuntimeError):m.apply(self.fake.args())
        state=json.loads((self.fake.state/'state.json').read_text())
        self.assertTrue(state['migration_point'])
        self.assertTrue(self.fake.paused)
        self.assertIn('503',(self.fake.root/'caddy/Caddyfile').read_text())
        with self.assertRaises(RuntimeError):m.apply(self.fake.args(resume=True,rollback=True))
        self.fake.calls=[]
        self.fake.fail_services=False
        m.apply(self.fake.args(resume=True))
        self.assertFalse(any('up' in call and call[-1]=='db' for call in self.fake.calls))
        self.assertFalse(self.fake.paused)
        self.assertEqual(self.fake.jobs,[{'id':10,'active':True},{'id':12,'active':False}])
        self.assertEqual(self.fake.timers,{m.QUIET_TIMERS[0]:'active',m.QUIET_TIMERS[1]:'inactive'})
        self.assertEqual((self.fake.root/'caddy/Caddyfile').read_text(),self.fake.caddy)
        self.assertIn('JWT_SECRET=fixture-preserved-key',(self.fake.root/'.env').read_text())

    def test_mount_and_credential_changes_are_rejected_before_installation(self):
        for alter in ['mount','secret','memory']:
            desired=copy.deepcopy(self.fake.desired)
            if alter=='mount':desired['services']['db']['volumes'][0]['source']='replacement-data'
            elif alter=='secret':desired['services']['functions']['environment']['EMAIL_SES_SECRET_ACCESS_KEY']='replacement'
            else:desired['services']['functions']['mem_limit']='1073741824'
            with self.assertRaises(RuntimeError):m.validate_model_change(self.fake.model,desired,self.fake.images)

    def test_failed_database_start_can_restore_original_images_and_job_states(self):
        self.fake.fail_database=True
        with self.assertRaises(RuntimeError):m.apply(self.fake.args())
        state=json.loads((self.fake.state/'state.json').read_text())
        self.assertFalse(state['migration_point'])
        self.fake.fail_database=False
        self.fake.fail_services=False
        m.apply(self.fake.args(resume=True,rollback=True))
        self.assertEqual(self.fake.db_image,self.fake.old_db)
        self.assertFalse(self.fake.paused)
        self.assertEqual(self.fake.jobs,[{'id':10,'active':True},{'id':12,'active':False}])
        self.assertEqual((self.fake.root/'caddy/Caddyfile').read_text(),self.fake.caddy)
        self.assertEqual(json.loads((self.fake.state/'state.json').read_text())['phase'],'rolled_back')


if __name__=='__main__':unittest.main()
