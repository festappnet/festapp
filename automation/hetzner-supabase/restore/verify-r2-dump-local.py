#!/usr/bin/env python3
"""Verify selected encrypted image archive against pg_restore COPY references.
No Docker, network, SQL execution or production access. Not a service restore.
"""
import argparse,csv,hashlib,json,os,shutil,subprocess,tempfile
from pathlib import Path
from r2_archive import verify_archive

def image_references(sql):
 columns=None;references=[];records=0;finished=False
 for line in sql.splitlines():
  if line.startswith('COPY public.images (') and line.endswith(') FROM stdin;'):
   assert columns is None,'duplicate image COPY'
   columns=next(csv.reader([line[len('COPY public.images ('):-len(') FROM stdin;')]],skipinitialspace=True));index=columns.index('link');continue
  if columns is None or finished:continue
  if line=='\\.':finished=True;continue
  values=line.split('\t');assert len(values)==len(columns),'invalid COPY row'
  records+=1;value=values[index]
  if value.startswith(('https://img.festapp.net/','https://a.img.festapp.net/')):
   assert '\\' not in value,'escaped URL needs explicit COPY handling'
   references.append(value)
 assert columns is not None and finished and records>0,'missing image COPY data'
 return records,references

def main():
 p=argparse.ArgumentParser();p.add_argument('--backup-dir',type=Path,required=True);p.add_argument('--identity',type=Path,required=True);p.add_argument('--evidence',type=Path,required=True);a=p.parse_args()
 os.umask(0o077);assert not a.evidence.exists()
 m=json.loads((a.backup_dir/'manifest.json').read_text());assert m['version']==1 and m['encrypted'] and m['source_database']=='festapp_rehearsal_20260909220601'
 names=['postgres.dump','r2-images.tar']
 for name in names:
  source=a.backup_dir/(name+'.age');metadata=m['artifacts'][source.name]
  with source.open('rb') as stream:assert hashlib.file_digest(stream,'sha256').hexdigest()==metadata['sha256']
  assert source.stat().st_size==metadata['bytes']
 assert shutil.disk_usage(a.backup_dir).free>sum(m['artifacts'][name+'.age']['bytes'] for name in names)+128*1024*1024
 with tempfile.TemporaryDirectory(prefix='festapp-r2-offline-') as temporary:
  work=Path(temporary);work.chmod(0o700)
  for name in names:subprocess.run(['age','-d','-i',str(a.identity),'-o',str(work/name),str(a.backup_dir/(name+'.age'))],check=True,stdout=subprocess.DEVNULL)
  sql=subprocess.check_output(['pg_restore','--data-only','--schema=public','--table=images','--file=-',str(work/'postgres.dump')],stderr=subprocess.DEVNULL).decode()
  records,references=image_references(sql);result=verify_archive(work/'r2-images.tar',references)
 result.update({'status':'pass' if result['consistent'] else 'fail','backup_run_id':m['run_id'],'database_image_records':records,'database_reference_source':'pg_restore COPY data from selected dump; no SQL execution','application_services_started':False,'docker_used':False,'network_used':False,'full_application_restore_proven':False})
 a.evidence.parent.mkdir(parents=True,exist_ok=True);a.evidence.write_text(json.dumps(result,indent=2)+'\n');a.evidence.chmod(0o600)
 assert result['consistent'],'archive lacks selected database image references; bounded result saved'
 print('Offline R2 archive and database dump references: pass')
if __name__=='__main__':main()
