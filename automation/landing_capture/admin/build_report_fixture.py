"""Render standalone local fixture from canonical demo seed; never touch production.
Pipe output to explicitly local psql inside one transaction. Separate local form/event,
real 95-order canonical dataset and 24 days of payments; no demo registration.
"""
from pathlib import Path
import re,argparse
p=argparse.ArgumentParser();p.add_argument('--organization',type=int,default=1);p.add_argument('--unit',type=int,default=1);a=p.parse_args()
root=Path(__file__).resolve().parents[3];s=(root/'database/fixtures/demo_occasions/seed.sql').read_text()
s=s.replace('seed_demo_occasions','seed_capture_report')
s=re.sub(r" IF EXISTS\(SELECT 1 FROM public.demo_occasions.*?\n END IF;",'',s,count=1,flags=re.S)
s=s.replace("INSERT INTO public.units(title,organization) VALUES('Ukázkový pořadatel',p_org) RETURNING id INTO un;",f'un:={a.unit};')
s=s.replace("ARRAY['ball','concert','weekend']","ARRAY['ball']")
s=s.replace("'demo-'||p_org||'-'||k||'-20261014'","'capture-report-'||p_org||'-'||k")
s=s.replace("'demo-form-'||p_org||'-'||k","'capture-report-form-'||p_org||'-'||k")
s=re.sub(r'  INSERT INTO public.demo_occasions\(.*?;\n','',s,count=1,flags=re.S)
s=s.replace("'Ukázkový účet - neposílejte platbu'","'Lokální syntetický účet'")
print('BEGIN;')
print((root/'database/fixtures/demo_occasions/layouts.sql').read_text())
print(s)
print(f'SELECT pg_temp.seed_capture_report({a.organization});')
print('COMMIT;')
