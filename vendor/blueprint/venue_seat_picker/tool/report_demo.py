#!/usr/bin/env python3
"""Build a self-contained, file-open evidence page. Never serves or opens it."""
import base64,html,json,pathlib,sys
root=pathlib.Path(__file__).resolve().parent.parent
out=root/'build/demo/report';out.mkdir(parents=True,exist_ok=True)
data={}
for key,path in [('validation','build/qa/validation.json'),('browser','build/qa/browser/result.json'),('raster','build/qa/raster/result.json'),('archive','build/qa/archive/publish-status.json'),('frameTiming','build/qa/browser/frame-timing.json'),('kit','build/demo/manifest.json')]:
 p=root/path
 data[key]=json.loads(p.read_text()) if p.exists() else {'status':'not recorded'}
data['browserRuns']={}
data['earlierBrowserDiagnostics']={}
for p in sorted((root/'build/qa/browser').rglob('result.json')):
 key=str(p.relative_to(root/'build/qa/browser'))
 bucket='browserRuns' if (key.split('/')[0].startswith('final-') or key.split('/')[0]=='ui') else 'earlierBrowserDiagnostics'
 data[bucket][key]=json.loads(p.read_text())
smoke=root/'build/demo/report/result.json'
if smoke.exists(): data['launcherSmoke']=json.loads(smoke.read_text())
images=[]
journey=root/'build/qa/browser/final-journey/journey1440.png'
if journey.exists(): images.append('<figure><img alt="Verified organizer journey" src="data:image/png;base64,'+base64.b64encode(journey.read_bytes()).decode()+'"><figcaption>Final organizer journey</figcaption></figure>')
for p in sorted((root/'build/qa/browser').rglob('editor-*.png')):
 if 'failure' in p.name: continue
 if len(images)>=6: break
 images.append('<figure><img alt="'+html.escape(p.stem)+'" src="data:image/png;base64,'+base64.b64encode(p.read_bytes()).decode()+'"><figcaption>'+html.escape(p.name)+'</figcaption></figure>')
for name in ['rotated-czech-glyphs-0-360-2-1.0', 'crop-preserves-registration-240-1440-2-2.0']:
 for renderer,folder in [('Flutter', 'build/qa/fixtures/raster'), ('SVG', 'build/qa/raster')]:
  p=root/folder/(name+'.png')
  if p.exists(): images.append('<figure><img alt="'+html.escape(renderer+' '+name)+'" src="data:image/png;base64,'+base64.b64encode(p.read_bytes()).decode()+'"><figcaption>'+html.escape(renderer+' '+name)+'</figcaption></figure>')
report=(root/'doc/blueprint-v2/VERIFICATION.md').read_text()
summary={'verification':data,'simulations':['synthetic seat prices and inherited defaults','selection success/conflict/timeout/resource replies','standing quantity and indivisible couch callback','full local storage and stale font response'], 'deferred':'All Festapp integration, SQL/auth/real locks/inventory/payments/tickets/production font services, registry publication and deployment require new scope.'}
page='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Venue layout stage A evidence</title><style>body{font:16px system-ui,sans-serif;max-width:1100px;margin:32px auto;padding:0 20px;color:#173b37;background:#f6f9f8}h1{font-size:28px}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:white;border:1px solid #d8e5e0;padding:18px;border-radius:10px}img{max-width:100%;height:auto}figure{margin:24px 0}summary{cursor:pointer;padding:16px;background:#e0efe8}a{color:#195c45}</style><h1>Venue layout - stage A evidence</h1><p>Standalone package and local demo. No production changes, publication or deployment.</p>'''
page+='<pre>'+html.escape(report)+'</pre><details><summary>Raw receipts and measurements</summary><pre>'+html.escape(json.dumps(summary,indent=2))+'</pre></details>'+''.join(images)+'</html>'
(out/'index.html').write_text(page)
print(out/'index.html')
