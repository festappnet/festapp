#!/usr/bin/env python3
"""Offline, SDK-free loopback launcher for a copied demo kit. Never opens a browser."""
import json,os,pathlib,signal,subprocess,sys,time,urllib.request
kit=pathlib.Path(__file__).resolve().parent
state=kit/'.demo-server.json'
server=kit/'server.py'
def owned():
    if not state.exists(): return None
    try:
        value=json.loads(state.read_text());pid=int(value['pid'])
        command=subprocess.check_output(['ps','-p',str(pid),'-o','command='],text=True).strip()
        if str(server) not in command or value.get('root')!=str(kit): return None
        return value
    except (ValueError,OSError,subprocess.CalledProcessError): return None
command=sys.argv[1] if len(sys.argv)>1 else 'open'
if command=='stop':
    value=owned()
    if value: os.kill(value['pid'],signal.SIGTERM)
    state.unlink(missing_ok=True)
    print('Owned demo server stopped')
elif command=='open':
    value=owned()
    if not value:
        state.unlink(missing_ok=True)
        subprocess.Popen([sys.executable,str(server),str(kit),str(state)],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
        for _ in range(50):
            value=owned()
            if value: break
            time.sleep(.05)
        if not value: raise SystemExit('Demo server failed to start')
    base='http://127.0.0.1:'+str(value['port'])
    with urllib.request.urlopen(base+'/flutter/index.html',timeout=3) as response:
        if response.status!=200: raise SystemExit('Demo index unavailable')
    print('Flutter editor: '+base+'/flutter/')
    print('JS picker: '+base+'/js/demo/')
    print('Stop: python3 '+str(kit/'run.py')+' stop')
else: raise SystemExit('Usage: python3 run.py open|stop')
