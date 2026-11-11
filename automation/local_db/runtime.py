#!/usr/bin/env python3
"""Canonical owned PostgreSQL runtime, immutable bases, upgrade checkpoints and leases."""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'automation'))
import baseline
from ci.telemetry import phase

LABEL = 'net.festapp.sql-runtime'
VERSION = '2'
CONFIG = json.loads((ROOT / 'automation/local_db/test-base.json').read_text())
MAJOR = os.environ.get('FESTAPP_TEST_PG_MAJOR','15')
if MAJOR not in CONFIG['providers']: raise ValueError('Unsupported test provider major')
provider=CONFIG['providers'][MAJOR]
CONFIG = {**CONFIG,**provider,'settings':{**CONFIG['settings'],**provider.get('settings',{})}}
CONFIG['providerManifest'] = str(CONFIG['providerManifest'])
IDENTIFIER = re.compile(r'festapp_(?:base|checkpoint|run)_[0-9a-f]{32,40}')


def process_start(pid):
    result = subprocess.run(['ps', '-p', str(pid), '-o', 'lstart='], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def content_digest(paths, root=ROOT):
    digest = hashlib.sha256()
    for path in sorted(set(paths)):
        digest.update(str(path.relative_to(root)).encode() + b'\0' + path.read_bytes() + b'\0')
    return digest.hexdigest()


def sql_sources(root, source):
    """Follow literal psql includes, including nested seed dependencies."""
    paths={source.resolve()};pending=list(paths)
    while pending:
        path=pending.pop()
        for line in path.read_text().splitlines():
            if not re.match(r'^\s*\\ir?(?:\s|$)',line):continue
            match=re.fullmatch(r'\s*\\(ir|i)\s+([A-Za-z0-9_./-]+)\s*',line)
            if not match:raise ValueError('Seed includes must use literal repository paths')
            parent=path.parent if match[1]=='ir' else root
            candidate=parent/match[2]
            included=baseline.repository_path(root,str(candidate.relative_to(root))).resolve()
            if included not in paths:paths.add(included);pending.append(included)
    return paths


def sql_content(root, source, stack=()):
    """Expand validated literal psql includes before streaming into the container."""
    source=source.resolve()
    if source in stack:
        raise ValueError('Cyclic SQL include')
    sql_sources(root,source)
    output=[]
    for line in source.read_text().splitlines(keepends=True):
        match=re.fullmatch(r'\s*\\(ir|i)\s+([A-Za-z0-9_./-]+)\s*',line)
        if match:
            parent=source.parent if match[1]=='ir' else root
            target=baseline.repository_path(root,str((parent/match[2]).relative_to(root)))
            output.append(sql_content(root,target,(*stack,source)))
        else:output.append(line)
    return ''.join(output)


def core_sources(root):
    paths=set()
    for directory in ('automation/local_db','supabase/baseline'):
        paths.update(p for p in (root/directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts and not p.name.startswith('test_'))
    for name in ('automation/baseline.py','automation/historical_inputs.py','automation/historical-inputs/manifest.json',
                 'automation/ci/telemetry.py','automation/historical-sql-manifest.json',
                 'automation/seed_demo_occasions.sql','supabase/seed.sql','automation/order-symbol/backfill.sql',
                 'automation/generate_canonical_source_contract.py','automation/canonical-source-contract.json',
                 'database/tests/canonical_mutation_source_parity_test.sql','database/tests/helpers/assertions.sql',
                 'database/tests/helpers/reset_owned_sequences.sql'):
        paths.add(root/name)
    contract=json.loads((root/'automation/canonical-source-contract.json').read_text())
    for key in ('baselineManifest','operationsManifest'):
        paths.add(baseline.repository_path(root,contract[key]))
    paths.update(sql_sources(root,root/'automation/seed_demo_occasions.sql'))
    for source in (root/'supabase/baseline').glob('*.sql'):
        paths.update(sql_sources(root,source))
    paths.update(path for path in (root/'automation/historical-inputs/objects').iterdir() if path.is_file())
    return paths


def atomic_json(path, value):
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


class Runtime:
    def __init__(self):
        self.project = os.environ.get('FESTAPP_LOCAL_DB_PROJECT_ID', 'festapp-sql-runtime')
        self.port = int(os.environ.get('FESTAPP_LOCAL_DB_PORT', '55542'))
        self.profile=os.environ.get('FESTAPP_TEST_DATA_PROFILE','demo')
        if self.profile not in CONFIG['profiles']:raise ValueError('Unsupported explicit test data profile')
        if not re.fullmatch(r'festapp-[a-z0-9-]+', self.project) or not 1024 <= self.port <= 65535:
            raise ValueError('Invalid owned test runtime project/loopback port')
        self.container = 'supabase_db_' + self.project
        self.cache = Path.home() / '.cache/festapp-sql-runtime' / self.project
        self.cache.mkdir(parents=True, exist_ok=True)

    @contextmanager
    def locked(self):
        with (self.cache / 'runtime.lock').open('a') as lock:
            # Queue only runtime transitions; test execution does not hold this lock.
            with phase('database.lease-queue'):
                fcntl.flock(lock, fcntl.LOCK_EX)
            yield

    def inspect(self):
        result = subprocess.run(['docker', 'container', 'inspect', self.container], capture_output=True, text=True)
        if result.returncode:
            return None
        data = json.loads(result.stdout)[0]
        if (data['Config'].get('Labels') or {}).get(LABEL) != VERSION:
            raise ValueError('Refusing a database container not owned by this runtime')
        if data['HostConfig']['PortBindings'].get('5432/tcp') != [{'HostIp':'127.0.0.1','HostPort':str(self.port)}]:
            raise ValueError('Owned runtime must publish only its exact loopback port')
        expected = ['postgres','-D','/etc/postgresql', *[arg for k,v in CONFIG['settings'].items() for arg in ('-c',k+'='+v)]]
        if data['Config']['Image'] != CONFIG['image']:
            raise ValueError('Owned container image/provider major mismatch')
        if data['Config']['Cmd'] != expected:
            raise ValueError('Runtime configuration drift; release leases and explicitly recreate the owned container')
        return data

    def sql(self, sql=None, *, file=None, database='postgres', user='supabase_admin', capture=False):
        command = ['docker','exec','-i','-e','PGPASSWORD=postgres',self.container,
                   'psql','-X','-U',user,'-d',database,'-v','ON_ERROR_STOP=1','-Atq']
        result = subprocess.run(command, input=sql_content(ROOT,Path(file)).encode() if file else sql.encode(),
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode:
            raise RuntimeError(result.stderr.decode().strip())
        return result.stdout if capture else None

    def url(self, user='postgres', database='postgres'):
        return f'postgresql://{user}:postgres@127.0.0.1:{self.port}/{database}?sslmode=disable'

    def start(self):
        data = self.inspect()
        if not data:
            image = subprocess.run(['docker','image','inspect',CONFIG['image']], capture_output=True)
            if image.returncode:
                with phase('database.image-download'):
                    subprocess.run(['docker','pull',CONFIG['image']], check=True, stdout=sys.stderr)
            with phase('database.container-create'):
                subprocess.run(['docker','run','-d','--name',self.container,'--label',LABEL+'='+VERSION,
                    '-e','POSTGRES_PASSWORD=postgres','-e','PGPASSWORD=postgres','-e','POSTGRES_USER=supabase_admin',
                    '-e','POSTGRES_HOST=/var/run/postgresql','-p',f'127.0.0.1:{self.port}:5432',
                    '-v',self.container+':/var/lib/postgresql/data',CONFIG['image'],
                    'postgres','-D','/etc/postgresql',
                    *[arg for k,v in CONFIG['settings'].items() for arg in ('-c',k+'='+v)]],
                    check=True,stdout=subprocess.DEVNULL)
        elif not data['State']['Running']:
            with phase('database.container-start'):
                subprocess.run(['docker','start',self.container],check=True,stdout=subprocess.DEVNULL)
        with phase('database.readiness'):
            deadline = time.monotonic()+60
            while True:
                try:
                    # The image starts a temporary init server before exec'ing
                    # PostgreSQL as PID 1. It accepts SQL and then shuts down;
                    # publishing a base against it races the final server.
                    process=subprocess.check_output(['docker','exec',self.container,'cat','/proc/1/cmdline']).decode().rstrip('\0').split('\0')
                    if Path(process[0]).name!='postgres' or process[1:3]!=['-D','/etc/postgresql']:
                        raise RuntimeError('Provider initialization is still running')
                    self.sql('SELECT 1',database='template1')
                    break
                except RuntimeError:
                    if time.monotonic() >= deadline:
                        raise RuntimeError('Owned PostgreSQL readiness exceeded 60s')
                    time.sleep(.1)
        self.inspect()
        # Workers process only this inert, empty database, never test queues.
        if not self.sql("SELECT 1 FROM pg_database WHERE datname='festapp_network_sink'", database='template1', capture=True).strip():
            self.sql('CREATE DATABASE festapp_network_sink TEMPLATE template0;',database='template1')
            self.sql('CREATE SCHEMA extensions; CREATE EXTENSION pg_net WITH SCHEMA extensions;',database='festapp_network_sink')

    def identity(self):
        paths=core_sources(ROOT)
        image = json.loads(subprocess.check_output(['docker','image','inspect',CONFIG['image']]))[0]
        tools = {tool:subprocess.check_output(command,text=True).strip() for tool,command in
                 {'psql':['psql','--version'],'supabase':['supabase','--version']}.items()}
        core = {'profile':self.profile,'inputs':content_digest(paths,ROOT),'imageId':image['Id'],'platform':image['Os']+'/'+image['Architecture'],'tools':tools}
        if core['platform'] not in CONFIG['platforms']:
            raise ValueError('Unsupported provider platform')
        # Checkpoints are keyed by the immutable entire migration prefix.
        migrations = [{'name':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
                      for p in sorted((ROOT/'supabase/migrations').glob('*.sql'))]
        if len({p['name'][:14] for p in migrations}) != len(migrations):
            raise ValueError('Duplicate migration versions')
        base_key = hashlib.sha256(json.dumps(core,sort_keys=True).encode()).hexdigest()
        full = {**core,'migrations':migrations,'canonicalSources':content_digest(
            (p for directory in ('database/functions','database/seeds') for p in (ROOT/directory).rglob('*.sql')),ROOT)}
        digest = hashlib.sha256(json.dumps(full,sort_keys=True).encode()).hexdigest()
        return digest,base_key,migrations,full

    def leases(self):
        return [json.loads(p.read_text()) for p in sorted(self.cache.glob('lease-*.json'))]

    def no_clients(self, database=None):
        clause = " AND datname='"+database+"'" if database else ''
        count = self.sql("SELECT count(*) FROM pg_stat_activity WHERE backend_type='client backend' AND pid<>pg_backend_pid()"+clause,database='template1',capture=True)
        if int(count.strip()):
            raise ValueError('Active client sessions block runtime mutation/cleanup')

    def template_exists(self,name,marker):
        if not IDENTIFIER.fullmatch(name):
            raise ValueError('Invalid owned database identifier')
        row = self.sql("SELECT json_build_object('allow',datallowconn,'marker',shobj_description(oid,'pg_database')) FROM pg_database WHERE datname='"+name+"'",database='template1',capture=True).decode().strip()
        if not row:
            return False
        if json.loads(row) != {'allow':False,'marker':marker}:
            raise ValueError('Immutable template marker/fence mismatch')
        return True

    def publish(self,name,marker):
        # Persist ownership before CREATE; recovery never deletes by prefix alone.
        intent=self.cache/('pending-'+name+'.json')
        atomic_json(intent,{'project':self.project,'database':name,'marker':marker})
        self.no_clients('postgres')
        self.sql('ALTER DATABASE postgres ALLOW_CONNECTIONS false;',database='template1')
        try:
            self.sql("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='postgres' AND backend_type='pg_cron launcher'",database='template1')
            self.sql('CREATE DATABASE '+name+' TEMPLATE postgres OWNER postgres ALLOW_CONNECTIONS false;',database='template1')
            self.sql("COMMENT ON DATABASE "+name+" IS '"+marker+"';",database='template1')
        finally:
            self.sql('ALTER DATABASE postgres ALLOW_CONNECTIONS true;',database='template1')
        atomic_json(self.cache/('object-'+name+'.json'),{'project':self.project,'database':name,'marker':marker,'created':time.time()})
        intent.unlink()

    def recover_publications(self):
        for path in self.cache.glob('pending-*.json'):
            intent=json.loads(path.read_text())
            name=intent['database']
            if intent['project']!=self.project or not IDENTIFIER.fullmatch(name):
                raise ValueError('Publication ownership mismatch')
            row=self.sql("SELECT json_build_object('allow',datallowconn,'marker',shobj_description(oid,'pg_database'),'owner',pg_get_userbyid(datdba)) FROM pg_database WHERE datname='"+name+"'",database='template1',capture=True).decode().strip()
            if row:
                data=json.loads(row)
                if data['allow'] or data['owner']!='postgres' or data['marker'] not in (None,intent['marker']):
                    raise ValueError('Refusing recovery of an unowned/unfenced publication')
                self.no_clients(name)
                self.sql('DROP DATABASE '+name+';',database='template1')
            path.unlink()

    def provider(self):
        manifest = json.loads((ROOT/CONFIG['providerManifest']).read_text())
        if manifest['formatVersion']!=1 or set(manifest['files'])!={manifest['schema'],'roles.sql'}:
            raise ValueError('Unsupported provider artifact contract')
        if manifest['image']!=CONFIG['image'].split('@')[0]:raise ValueError('Provider artifact image mismatch')
        for name,expected in manifest['files'].items():
            if hashlib.sha256((ROOT/CONFIG['providerManifest']).parent.joinpath(name).read_bytes()).hexdigest()!=expected:
                raise ValueError('Provider artifact content digest mismatch: '+name)
        self.no_clients()
        with phase('database.provider-initialization'):
            self.sql('DROP DATABASE IF EXISTS postgres WITH (FORCE);',database='template1')
            self.sql('CREATE DATABASE postgres TEMPLATE template0 OWNER postgres;',database='template1')
            self.sql(file=(ROOT/CONFIG['providerManifest']).parent/'roles.sql')
            self.sql(file=(ROOT/CONFIG['providerManifest']).parent/manifest['schema'])
            self.sql("ALTER USER postgres PASSWORD 'postgres'; CREATE EXTENSION pg_cron WITH SCHEMA pg_catalog;")

    def replay(self, checkpoint=None):
        if self.leases():
            raise ValueError('Existing leases block upgrade/cluster-global mutation')
        if checkpoint:
            self.no_clients()
            self.sql('DROP DATABASE IF EXISTS postgres WITH (FORCE);',database='template1')
            self.sql('CREATE DATABASE postgres TEMPLATE '+checkpoint+' OWNER postgres;',database='template1')
        else:
            self.provider()
            manifest = baseline.load_manifest(ROOT)
            for name,field in [('baseline-prerequisites','bootstrap'),('baseline-restore','schema'),('baseline-reference-seed','referenceSeed')]:
                with phase('database.'+name): self.sql(file=ROOT/manifest[field]['path'],user='supabase_admin')
            with phase('database.reference-tenants'): self.sql(file=ROOT/'automation/local_db/reference_tenants.sql',user='postgres')
            self.sql(baseline.ledger_sql(ROOT),user='postgres')
        with phase('database.checkpoint-tail' if checkpoint else 'database.full-history-replay'):
            # The original migration/backfill engine is the sole history owner.
            with open(self.cache/'upgrade.log','w') as log:
                subprocess.run([sys.executable,str(ROOT/'automation/baseline.py'),'upgrade-local','--database-url',self.url('supabase_admin')],check=True,stdout=log,stderr=log)

    def finish_seed(self):
        with phase('database.owner-alignment'): self.sql(file=ROOT/'automation/local_db/align_owners.sql')
        with phase('database.application-seed'): self.sql(file=ROOT/'supabase/seed.sql',user='postgres')
        if self.profile=='demo':
            with phase('database.demo-seed'):
                subprocess.run(['psql',self.url(),'-X','-v','ON_ERROR_STOP=1','-v','demo_organization=1','-f',str(ROOT/'automation/seed_demo_occasions.sql')],cwd=ROOT,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
        self.sql("CREATE SCHEMA festapp_test_support; CREATE TABLE festapp_test_support.disposable_environment(singleton boolean PRIMARY KEY CHECK(singleton),project text NOT NULL); INSERT INTO festapp_test_support.disposable_environment VALUES(true,'"+self.project+"');",user='postgres')
        with phase('database.sequences'): self.sql(file=ROOT/'database/tests/helpers/reset_owned_sequences.sql',user='postgres')

    def validate_base(self):
        # Drift is rejected, not hashed into a supposedly valid migrated base.
        subprocess.run([sys.executable,str(ROOT/'automation/generate_canonical_source_contract.py'),'--check'],check=True,stdout=subprocess.DEVNULL)
        sql='BEGIN;\n'+(ROOT/'database/tests/helpers/assertions.sql').read_text()+'\n'+(ROOT/'database/tests/canonical_mutation_source_parity_test.sql').read_text()+'\nROLLBACK;'
        self.sql(sql,user='postgres')
        missing=int(self.sql("SELECT count(*) FROM client_sync_component_sources t WHERE NOT EXISTS(SELECT FROM pg_class c WHERE c.oid=t.source_relation)",capture=True))
        if missing: raise ValueError('Dangling canonical registry references block template publication')

    def prepare(self, *, full_replay=False, provider_only=False):
        self.start()
        self.recover_publications()
        digest,core,migrations,identity=self.identity()
        if provider_only:
            digest=hashlib.sha256(('provider-only:'+core).encode()).hexdigest()
            template='festapp_base_'+digest[:40];marker=VERSION+':'+digest
            if not self.template_exists(template,marker):
                if self.leases():raise ValueError('Provider rebuild is blocked by existing leases')
                self.provider()
                with phase('database.provider-template-publication'):self.publish(template,marker)
            return {'template':template,'fingerprint':digest,'mode':'provider-prerequisite','identity':identity}
        template='festapp_base_'+digest[:40]
        marker=VERSION+':'+digest
        if not full_replay and self.template_exists(template,marker):
            return {'template':template,'fingerprint':digest,'mode':'behavior-template','identity':identity}
        checkpoint=None
        if not full_replay:
            candidates=[]
            for path in self.cache.glob('checkpoint-*.json'):
                entry=json.loads(path.read_text())
                prefix=entry['migrations']
                if entry['core']==core and migrations[:len(prefix)]==prefix and len(prefix)<len(migrations):
                    if self.template_exists(entry['database'],entry['marker']): candidates.append(entry)
            if candidates: checkpoint=max(candidates,key=lambda e:len(e['migrations']))['database']
        self.replay(checkpoint)
        # Publish checkpoint BEFORE mutable demo/reference scenario data.
        checkpoint_key=hashlib.sha256(json.dumps({'core':core,'migrations':migrations},sort_keys=True).encode()).hexdigest()
        checkpoint_name='festapp_checkpoint_'+checkpoint_key[:32]
        checkpoint_marker=VERSION+':'+checkpoint_key
        if not self.template_exists(checkpoint_name,checkpoint_marker):
            with phase('database.checkpoint-publication'): self.publish(checkpoint_name,checkpoint_marker)
        self.finish_seed()
        with phase('database.template-validation'): self.validate_base()
        if self.identity()[0]!=digest: raise ValueError('Runtime inputs changed during base build')
        atomic_json(self.cache/('checkpoint-'+checkpoint_key+'.json'),{'core':core,'migrations':migrations,'database':checkpoint_name,'marker':checkpoint_marker})
        if not self.template_exists(template,marker):
            with phase('database.template-publication'): self.publish(template,marker)
        return {'template':template,'fingerprint':digest,'mode':'checkpoint-tail' if checkpoint else 'full-replay','identity':identity}

    def acquire(self,owner_pid=None, *, provider_only=False):
        owner_pid=owner_pid or os.getpid()
        owner_start=process_start(owner_pid)
        if not owner_start: raise ValueError('Lease owner PID must be alive')
        base=self.prepare(provider_only=provider_only)
        run_id=uuid.uuid4().hex
        database='festapp_run_'+run_id
        lease={**base,'runId':run_id,'database':database,'project':self.project,'ownerPid':owner_pid,'ownerStart':owner_start,'created':time.time(),'state':'creating'}
        path=self.cache/('lease-'+run_id+'.json')
        atomic_json(path,lease)
        with phase('database.clone',runId=run_id,baseMode=base['mode'],fingerprint=base['fingerprint'],template=base['template']):
            self.sql('CREATE DATABASE '+database+' TEMPLATE '+base['template']+' OWNER postgres ALLOW_CONNECTIONS false;',database='template1')
            self.sql("COMMENT ON DATABASE "+database+" IS '"+run_id+':'+base['fingerprint']+"';",database='template1')
            self.sql('ALTER DATABASE '+database+' ALLOW_CONNECTIONS true;',database='template1')
            lease['state']='ready'
            atomic_json(path,lease)
        return {**lease,'databaseUrl':self.url(database=database)}

    def release(self,run_id, *, abandoned=False):
        if not re.fullmatch(r'[0-9a-f]{32}',run_id or ''): raise ValueError('Invalid lease ID')
        path=self.cache/('lease-'+run_id+'.json')
        lease=json.loads(path.read_text())
        if lease['runId']!=run_id or lease['project']!=self.project or lease['database']!='festapp_run_'+run_id:
            raise ValueError('Lease ownership mismatch')
        if abandoned and process_start(lease['ownerPid'])==lease['ownerStart']: raise ValueError('Refusing to prune live owner')
        row=self.sql("SELECT json_build_object('marker',shobj_description(oid,'pg_database'),'allow',datallowconn,'owner',pg_get_userbyid(datdba)) FROM pg_database WHERE datname='"+lease['database']+"'",database='template1',capture=True).decode().strip()
        if row:
            data=json.loads(row)
            creating=lease.get('state')=='creating' and data['marker'] is None and not data['allow'] and data['owner']=='postgres'
            if not creating and data['marker']!=run_id+':'+lease['fingerprint']:
                raise ValueError('Run database marker mismatch; manual inspection required')
        with phase('database.release',runId=run_id):
            if row:
                self.no_clients(lease['database'])
                self.sql('DROP DATABASE '+lease['database']+';',database='template1')
            path.unlink()

    @contextmanager
    def workspace(self, *, exclusive=False, keep=False, provider_only=False):
        def finish(lease):
            if keep:
                path=self.cache/('lease-'+lease['runId']+'.json')
                record=json.loads(path.read_text());record['retained']=True
                atomic_json(path,record)
                print('Retained SQL inspection workspace: '+lease['runId']+' ('+lease['database']+')',file=sys.stderr)
            else:self.release(lease['runId'])
        if exclusive:
            # Explicit service/global-role proofs own the cluster for their
            # entire execution. Ordinary behavior units hold only short leases.
            with self.locked():
                lease=self.acquire(provider_only=provider_only)
                try:yield lease
                finally:finish(lease)
        else:
            with self.locked():lease=self.acquire(provider_only=provider_only)
            try:yield lease
            finally:
                with self.locked():finish(lease)

    def stop(self):
        data=self.inspect()
        if not data or not data['State']['Running']: return
        if self.leases(): raise ValueError('Leased databases block stop')
        self.no_clients()
        subprocess.run(['docker','stop',self.container],check=True,stdout=subprocess.DEVNULL)

    def prune(self,age):
        data=self.inspect()
        if not data:return
        was_running=data['State']['Running']
        if not was_running:self.start()
        try:
            for lease in self.leases():
                if not lease.get('retained') and time.time()-lease['created']>=age and process_start(lease['ownerPid'])!=lease['ownerStart']:
                    self.release(lease['runId'],abandoned=True)
            if self.leases():return
            digest,core,migrations,_=self.identity()
            checkpoint=hashlib.sha256(json.dumps({'core':core,'migrations':migrations},sort_keys=True).encode()).hexdigest()
            keep={'festapp_base_'+digest[:40],'festapp_checkpoint_'+checkpoint[:32]}
            for path in self.cache.glob('object-*.json'):
                entry=json.loads(path.read_text());name=entry['database']
                if entry['project']!=self.project or not IDENTIFIER.fullmatch(name):raise ValueError('Cache object ownership mismatch')
                if name in keep or time.time()-entry['created']<age:continue
                if self.template_exists(name,entry['marker']):
                    self.no_clients(name)
                    self.sql('DROP DATABASE '+name+';',database='template1')
                path.unlink()
        finally:
            if not was_running:self.stop()


def workspace_env(lease):
    return {'DATABASE_URL':lease['databaseUrl'],'SEAT_CHECKOUT_DATABASE_URL':lease['databaseUrl'],
            'FESTAPP_TEST_ADMIN_DATABASE_URL':lease['databaseUrl'].replace('postgres:postgres@','supabase_admin:postgres@',1),
            'FESTAPP_DB_RUN_ID':lease['runId'],'FESTAPP_LOCAL_DB_PROJECT_ID':lease['project'],
            'FESTAPP_LOCAL_DB_PORT':str(Runtime().port)}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['prepare','upgrade','acquire','release','stop','status','prune','exec'])
    parser.add_argument('--owner-pid',type=int,default=os.getppid())
    parser.add_argument('--run-id')
    parser.add_argument('--exclusive',action='store_true')
    parser.add_argument('--provider-only',action='store_true')
    parser.add_argument('--keep-workspace',action='store_true')
    parser.add_argument('--age-seconds',type=int,default=3600)
    args,argv=parser.parse_known_args()
    if args.command!='exec' and argv: parser.error('Unexpected arguments')
    runtime=Runtime()
    if args.command=='exec':
        argv=argv[1:] if argv[:1]==['--'] else argv
        if not argv: parser.error('exec requires a command after --')
        with runtime.workspace(exclusive=args.exclusive,keep=args.keep_workspace,provider_only=args.provider_only) as lease:
            result=subprocess.run(argv,cwd=ROOT,env={**os.environ,**workspace_env(lease)})
        raise SystemExit(result.returncode)
    with runtime.locked():
        if args.command in ('prepare','upgrade'): print(json.dumps(runtime.prepare(full_replay=args.command=='upgrade')))
        elif args.command=='acquire': print(json.dumps(runtime.acquire(args.owner_pid)))
        elif args.command=='release': runtime.release(args.run_id)
        elif args.command=='stop': runtime.stop()
        elif args.command=='prune': runtime.prune(args.age_seconds)
        else:
            data=runtime.inspect()
            print(json.dumps({'project':runtime.project,'running':bool(data and data['State']['Running']),'leases':runtime.leases(),'cacheObjects':[json.loads(path.read_text()) for path in runtime.cache.glob('object-*.json')]}))


if __name__=='__main__':
    try: main()
    except (ValueError,RuntimeError,subprocess.CalledProcessError) as error:
        print(str(error) if not isinstance(error,subprocess.CalledProcessError) else 'Runtime subprocess failed; inspect the owned upgrade.log',file=sys.stderr)
        sys.exit(1)
