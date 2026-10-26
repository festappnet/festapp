"""Generate canonical resources from actual rehearsal documents, never fake glyphs."""
import argparse,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('package');p.add_argument('festapp');p.add_argument('output',type=Path);p.add_argument('--locale',choices=['cs','en'],default='cs');p.add_argument('--brand',action='store_true');a=p.parse_args()
base=Path(__file__).resolve().parent;documents=json.loads((base/'fixtures/growth-resource-documents.cs.json').read_text());target=a.output/'resource-inputs';target.mkdir(parents=True,exist_ok=True);args=[]
for i,raw in enumerate(documents):
 d=json.loads(raw) if isinstance(raw,str) else raw
 if a.brand:
  from brand_style import brand
  d=brand(d)
 for number in range(1,21):
  for node in d['nodes']:
   if node.get('kind')=='table':node['label']=('Stůl ' if a.locale=='cs' else 'Table ')+str(number)
  q=target/f'doc-{i}-{number}.json';q.write_text(json.dumps(d));args+=['--document',str(q)]
subprocess.run(['python3',str(base/'prepare_resources.py'),a.package,a.festapp,str(a.output),'--locale',a.locale,*(['--brand-font'] if a.brand else []),*args, *(['--document',str(base/f'fixtures/brand-empty.{a.locale}.json')] if a.brand else [])],check=True)
