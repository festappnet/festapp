import json,urllib.request,time,base64
from pathlib import Path
# Native fallback for the agent-browser iOS wrapper; never starts desktop Safari.
ROOT=Path(__file__).resolve().parents[1]
SESSION=json.loads((ROOT/'.private/safari-webdriver-session.json').read_text())['value']['sessionId']
def call(path,body=None,method=None):
 req=urllib.request.Request('http://localhost:59839/session/'+SESSION+path,data=json.dumps(body).encode() if body is not None else None,headers={'Content-Type':'application/json'},method=method)
 with urllib.request.urlopen(req,timeout=40) as r:d=json.load(r)
 v=d.get('value');
 if isinstance(v,dict) and 'error' in v:raise RuntimeError(v['error']+': '+v['message'])
 return v
def js(script,*args):return call('/execute/sync',{'script':script,'args':list(args)})
def goto(url):return call('/url',{'url':url})
def element(selector):return call('/element',{'using':'css selector','value':selector})
def frame(selector):return call('/frame',{'id':element(selector) if selector else None})
def screenshot(name):
 (ROOT/'evidence'/name).write_bytes(base64.b64decode(call('/screenshot')))
def text():return js('return document.body.innerText')
def wait(predicate,timeout=35):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  try:
   value=predicate()
   if value:return value
  except Exception:pass
  time.sleep(.3)
 raise AssertionError('Safari wait timed out')
