import json,collections,sys,gzip
from pathlib import Path
root=Path(sys.argv[1]);d=json.load((root/'main.dart.js.info.json').open());packages=collections.Counter();features=collections.Counter();libraries=[]
for lib in d['elements']['library'].values():
 uri=lib['canonicalUri'];size=lib['size'];libraries.append({'uri':uri,'bytes':size})
 if uri.startswith('package:'):
  package=uri[8:].split('/')[0];packages[package]+=size
  if package=='fstapp':
   parts=uri[8:].split('/'); key='/'.join(parts[1:3]) if len(parts)>2 else parts[-1];features[key]+=size
 elif uri.startswith('dart:'):packages[uri.split('/')[0]]+=size
 else:packages['other']+=size
js=(root/'main.dart.js').read_bytes()
result={'mainBytes':len(js),'mainGzipBytes':len(gzip.compress(js,compresslevel=9,mtime=0)),'programBytes':d['program']['size'],'packages':[{'name':k,'bytes':v} for k,v in packages.most_common()],'features':[{'name':k,'bytes':v} for k,v in features.most_common()],'libraries':sorted(libraries,key=lambda x:x['bytes'],reverse=True),'outputUnits':d['outputUnits'],'deferredFiles':d['deferredFiles']}
(root/'size-summary.json').write_text(json.dumps(result,indent=2))
print(root.name,'main:',len(js),'gzip:',result['mainGzipBytes']);print('packages:',packages.most_common(18));print('features:',features.most_common(14));print('libraries:',result['libraries'][:7]); print('units:',len(d['outputUnits']))
