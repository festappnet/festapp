"""One versioned CS/EN storyboard, capture job and parity gate. No app simulation.

A matched pair proves matching recorded inputs/checkpoints, not pixel identity
or a human visual approval. Full decode/playback and actual outcome review stay
required. Old videos without receipts cannot silently become matched captures.
"""
import argparse,hashlib,json,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SPEC=Path(__file__).with_name('scenarios')/'storyboard.json'
def digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
def read(path):return json.loads(Path(path).read_text())
def write(path,value):
 path=Path(path);path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
def contract(clip,spec=None):
 spec=spec or read(SPEC)
 if clip not in spec['clips']:raise ValueError('Unknown storyboard clip: '+clip)
 return {'schemaVersion':spec['schemaVersion'],'reference':spec['reference'],'clip':clip,**spec['clips'][clip]}
def text(locale):
 if locale not in ('cs','en'):raise ValueError('Only CS/EN capture locales are supported')
 result=read(SPEC.with_name('text.'+locale+'.json'))
 def strings(value):return isinstance(value,str) or isinstance(value,list) and all(isinstance(v,str) for v in value)
 if not all(strings(value) for value in result.values()):raise ValueError('Locale data must contain text only, never geometry/prices/camera')
 if set(result)!=set(read(SPEC.with_name('text.cs.json'))):raise ValueError('Locale text keys differ')
 return result
def subset(actual,expected):return all(actual.get(k)==v for k,v in expected.items())
def prepare(clip,locale,fixture,source):
 c=contract(clip)
 if fixture.get('fixture')!=c['fixture'] or not isinstance(fixture.get('geometry'),dict):raise ValueError('Wrong or missing canonical fixture geometry')
 if not subset(fixture.get('data',{}),c.get('data',{})):raise ValueError('Fixture numeric/business data differs from the original')
 if not subset(fixture.get('before',{}),c['before']):raise ValueError('Fixture preconditions do not match original storyboard')
 if not re.fullmatch('[a-f0-9]{64}',source):raise ValueError('Supply the actual common source-tree SHA-256')
 return {'schemaVersion':1,'clip':clip,'locale':locale,'scenarioSha256':digest(c),'sourceTreeSha256':source,'fixtureGeometrySha256':digest(fixture['geometry']),'fixtureDataSha256':digest(fixture.get('data',{})),'contract':c,'before':fixture['before'],'text':text(locale),'status':'prepared-not-recorded'}
def start_receipt(job,runtime):
 c=contract(job['clip'])
 if job['scenarioSha256']!=digest(c) or job['contract']!=c:raise ValueError('Stale or modified storyboard job')
 if job['text']!=text(job['locale']):raise ValueError('Modified locale data')
 for key in ('sourceTreeSha256','fixtureGeometrySha256','fixtureDataSha256'):
  if not re.fullmatch('[a-f0-9]{64}',job.get(key,'')):raise ValueError('Missing immutable input digest: '+key)
 if not subset(job.get('before',{}),c['before']):raise ValueError('Missing actual fixture preconditions')
 camera=c['camera']
 if runtime.get('viewport')!=camera['viewport'] or runtime.get('deviceScaleFactor')!=camera['deviceScaleFactor']:raise ValueError('Camera/viewport drift: reprepare the shared scene, do not compensate per locale')
 if runtime.get('locale')!=job['locale'] or runtime.get('theme')!=camera['theme']:raise ValueError('Wrong actual UI locale/theme')
 return {**job,'runtime':runtime,'beats':[],'status':'recording'}
def beat(receipt,name):
 expected=receipt['contract']['beats'];index=len(receipt['beats'])
 if receipt['status']!='recording' or index>=len(expected) or expected[index]!=name:raise ValueError('Unexpected/reordered beat: '+name)
 receipt['beats'].append(name)
def finish(receipt):
 if receipt['beats']!=receipt['contract']['beats']:raise ValueError('Incomplete storyboard; no matched capture receipt can be issued')
 receipt['status']='recorded-needs-outcome-and-visual-review';return receipt
def pair(cs,en):
 if [cs.get('locale'),en.get('locale')]!=['cs','en']:raise ValueError('A real CS and EN pair is required')
 for r in (cs,en):
  c=contract(r['clip'])
  if r.get('status')!='reviewed' or r.get('scenarioSha256')!=digest(c) or r.get('contract')!=c:raise ValueError('Unreviewed or stale capture receipt')
  if r.get('beats')!=c['beats'] or not subset(r.get('after',{}),c['after']):raise ValueError('Missing beats or wrong actual final state')
  if r.get('edit')!=c['edit']:raise ValueError('Different speed, cuts or original cue assembly')
  if r.get('exports')!={'desktop':c['camera']['desktop'],'mobile':c['camera']['mobile']}:raise ValueError('Export framing differs from original')
  if not all(r.get('checks',{}).get(k) is True for k in ('fullDecode','fullPlayback','firstMiddleLastFrames','actualReadback')):raise ValueError('Incomplete review evidence')
  if not re.fullmatch('[a-f0-9]{64}',r.get('takeSha256','')):raise ValueError('Missing immutable raw-take digest')
  if set(r.get('exportSha256',{}))!={'desktop','mobile'} or not all(re.fullmatch('[a-f0-9]{64}',v) for v in r['exportSha256'].values()):raise ValueError('Missing actual export hashes')
  start_receipt(r,r.get('runtime',{}))
 for key in ('clip','scenarioSha256','sourceTreeSha256','fixtureGeometrySha256','fixtureDataSha256','beats','exports'):
  if cs.get(key)!=en.get(key):raise ValueError('CS/EN drift: '+key)
 if cs['takeSha256']==en['takeSha256']:raise ValueError('Localized footage must be independently recorded, not relabeled')
 return {'clip':cs['clip'],'scenarioSha256':cs['scenarioSha256'],'sourceTreeSha256':cs['sourceTreeSha256'],'csTakeSha256':cs['takeSha256'],'enTakeSha256':en['takeSha256'],'csExportSha256':cs['exportSha256'],'enExportSha256':en['exportSha256'],'status':'matched-inputs-and-reviewed-outcomes'}
def audit(en_manifest):
 spec=read(SPEC);required={en_manifest['hero']}|{i for s in en_manifest['sections'] for i in s['clips']};clips={c['id']:c for c in en_manifest['clips']};rows=[]
 if required!=set(spec['clips']):raise ValueError('Rendered clips and common storyboard differ')
 for key in sorted(required):
  c=clips[key];expected=spec['clips'][key]['camera'];dimensions={'desktop':[c['width'],c['height']],'mobile':[c['mobileWidth'],c['mobileHeight']]}
  rows.append({'clip':key,'referenceScenarioSha256':digest(contract(key)),'dimensionsMatch':dimensions=={'desktop':expected['desktop'],'mobile':expected['mobile']},'pairStatus':'not-proven-without-CS-and-EN-capture-receipts'})
 return {'reference':spec['reference'],'clips':rows,'readyForOneToOnePublication':False}
def verify_pairs(directory, manifest):
 report=audit(manifest);results=[]
 drift=next((r['clip'] for r in report['clips'] if not r['dimensionsMatch']),None)
 if drift:raise ValueError('Published framing does not match original storyboard: '+drift)
 for row in report['clips']:
  key=row['clip']
  if not row['dimensionsMatch']:raise ValueError('Published framing does not match original storyboard: '+key)
  paths=[Path(directory)/(key+'.'+locale+'.json') for locale in ('cs','en')]
  if any(not p.is_file() for p in paths):raise ValueError('Missing paired scenario receipts: '+key)
  match=pair(*(read(p) for p in paths))
  if match['clip']!=key:raise ValueError('Receipt filed under a different clip: '+key)
  results.append(match)
 return results

def main():
 p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
 q=sub.add_parser('prepare');q.add_argument('clip');q.add_argument('--locale',required=True);q.add_argument('--fixture',type=Path,required=True);q.add_argument('--source-sha256',required=True);q.add_argument('--output',type=Path,required=True)
 q=sub.add_parser('compare');q.add_argument('cs',type=Path);q.add_argument('en',type=Path);q.add_argument('--output',type=Path,required=True)
 q=sub.add_parser('audit');q.add_argument('--manifest',type=Path,default=ROOT/'automation/release/organizers/clips.en.json');q.add_argument('--output',type=Path,required=True)
 q=sub.add_parser('verify-pairs');q.add_argument('directory',type=Path);q.add_argument('--manifest',type=Path,default=ROOT/'automation/release/organizers/clips.en.json');q.add_argument('--output',type=Path,required=True)
 q=sub.add_parser('verify-reference')
 a=p.parse_args()
 if a.command=='prepare':write(a.output,prepare(a.clip,a.locale,read(a.fixture),a.source_sha256))
 elif a.command=='compare':write(a.output,pair(read(a.cs),read(a.en)))
 elif a.command=='audit':write(a.output,audit(read(a.manifest)))
 elif a.command=='verify-pairs':write(a.output,{'readyForOneToOnePublication':True,'pairs':verify_pairs(a.directory,read(a.manifest))})
 else:
  s=read(SPEC);ref=s['reference'];data=subprocess.check_output(['git','show',ref['gitRevision']+':'+ref['manifestPath']],cwd=ROOT)
  if hashlib.sha256(data).hexdigest()!=ref['manifestSha256']:raise ValueError('Original reference manifest changed')
  for c in s['clips'].values():
   for asset in c['reference']['assets'].values():
    data=subprocess.check_output(['git','show',ref['gitRevision']+':web'+asset['path']],cwd=ROOT)
    if hashlib.sha256(data).hexdigest()!=asset['sha256']:raise ValueError('Original reference asset changed')
  print('Pinned Czech manifest and 32 original video/poster assets verified')
if __name__=='__main__':
 try:main()
 except (ValueError,KeyError) as e:print(str(e),file=sys.stderr);sys.exit(1)
