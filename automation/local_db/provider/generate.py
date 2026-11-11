#!/usr/bin/env python3
"""Explicit regeneration from a fresh pinned provider; never reads application data."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[3]


def command(*argv):return subprocess.check_output(argv,text=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--major',type=int,choices=[15,17],default=15)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    PROJECT='festapp-provider-artifact-pg'+str(args.major)
    CONTAINER='supabase_db_'+PROJECT
    if command('supabase','--version').strip()!='2.111.0':raise ValueError('Supabase CLI 2.111.0 required')
    if subprocess.run(['docker','container','inspect',CONTAINER],capture_output=True).returncode==0:
        raise ValueError('Artifact builder container already exists; inspect its owner before retrying')
    with tempfile.TemporaryDirectory(prefix='festapp-provider-artifact-') as directory:
        config=Path(directory)/'supabase';config.mkdir()
        (config/'config.toml').write_text(f'project_id = "{PROJECT}"\n[db]\nport = 55562\nshadow_port = 55560\nmajor_version = {args.major}\n[db.seed]\nenabled = false\n')
        try:
            subprocess.run(['supabase','db','start','--workdir',directory],check=True)
            image=json.loads(command('docker','container','inspect',CONTAINER))[0]['Config']['Image']
            expected='15.8.1.085' if args.major==15 else '17.6.1.156'
            if not image.endswith('supabase/postgres:'+expected):raise ValueError('Unexpected provider image')
            def sql(query):return command('docker','exec','-e','PGPASSWORD=postgres',CONTAINER,'psql','-X','-U','supabase_admin','-d','postgres','-Atqc',query).strip()
            if sql("SELECT to_regclass('public.organizations') IS NULL AND (SELECT count(*)=0 FROM auth.users) AND (SELECT count(*)=0 FROM storage.objects) AND (SELECT count(*)=0 FROM vault.secrets)")!='t':
                raise ValueError('Provider artifact builder is not pristine')
            dump=command('docker','exec','-e','PGPASSWORD=postgres',CONTAINER,'pg_dump','-U','supabase_admin','-d','postgres','--clean','--if-exists','--exclude-schema=pgsodium','--exclude-schema=pgsodium_masks')
            # PG15's wrapper is an extension member recreated by a late DDL
            # hook. PG17's real placeholder is standalone and already dumped.
            member=sql("SELECT count(*) FROM pg_depend d JOIN pg_extension e ON e.oid=d.refobjid WHERE d.classid='pg_proc'::regclass AND d.objid='graphql_public.graphql(text,text,jsonb,jsonb)'::regprocedure AND d.deptype='e' AND e.extname='pg_graphql'")
            if member=='1':
                wrapper=sql("SELECT pg_get_functiondef('graphql_public.graphql(text,text,jsonb,jsonb)'::regprocedure)")+';\nALTER EXTENSION pg_graphql ADD FUNCTION graphql_public.graphql(text,text,jsonb,jsonb);\n'
                match=re.search(r'--\n-- Name:.*?; Type: ACL;',dump)
                if not match:raise ValueError('Provider dump has no ACL section')
                dump=dump[:match.start()]+wrapper+'\n'+dump[match.start():]
            roles=command('docker','exec','-e','PGPASSWORD=postgres',CONTAINER,'pg_dumpall','-U','supabase_admin','--roles-only','--no-role-passwords')
            roles=re.sub(r'CREATE ROLE (\w+);',lambda m:"DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='%s') THEN CREATE ROLE %s; END IF; END $$;"%(m[1],m[1]),roles)
            for name,text in [('provider.sql',dump),('roles.sql',roles)]:
                (args.output/name).write_text('\n'.join(line for line in text.splitlines() if not line.startswith(('\\restrict','\\unrestrict')))+'\n')
            manifest={'formatVersion':1,'schema':'provider.sql','image':'public.ecr.aws/supabase/postgres:'+expected,'supabaseCli':'2.111.0',
              'sourcePlatform':command('docker','image','inspect',image,'--format','{{.Os}}/{{.Architecture}}').strip(),
              'provenance':'Fresh CLI provider only; no app schema/environment/data. Exact provider extension-member wrapper and password-free role definitions.',
              'files':{name:hashlib.sha256((args.output/name).read_bytes()).hexdigest() for name in ['provider.sql','roles.sql']}}
            (args.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
        finally:subprocess.run(['supabase','stop','--project-id',PROJECT,'--no-backup'],check=True)


if __name__=='__main__':main()
