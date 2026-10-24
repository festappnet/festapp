"""Real checkout retry with browser storage disabled; one real isolated gateway outage."""
import json,subprocess,re,time,urllib.request,urllib.error
from pathlib import Path
root=Path(__file__).resolve().parents[1]
b=['agent-browser','--config',str(root/'.private/stable-browser.json'),'--headed','false','--session','vo-storage-20261023']
def run(*a):
 r=subprocess.run(b+list(a),capture_output=True,text=True,timeout=35)
 if r.returncode:raise RuntimeError(r.stderr or r.stdout)
 return r.stdout
run('close')
init=root/'.private/storage-block.js'
init.write_text('Object.defineProperty(window,"localStorage",{get(){throw new DOMException("Blocked for acceptance","SecurityError")}});Object.defineProperty(window,"sessionStorage",{get(){throw new DOMException("Blocked for acceptance","SecurityError")}});')
b.extend(['--init-script',str(init)])
run('open','http://localhost:59811/vo-block/')
run('wait','--load','networkidle')
def ref(text):
    line=next(line for line in run('snapshot','-i').splitlines() if text in line)
    return '@'+re.search(r'ref=(e[0-9]+)',line)[1]
# Selector commands traverse iframe documents; wait is on a real accessible label.
run('fill',ref('textbox "Email *"'),'storage-outage-verified@example.invalid')
run('click',ref('radio "Synthetic admission'))
run('fill',ref('textbox "Name *"'),'Storage')
run('fill',ref('textbox "Surname *"'),'Visitor')
run('click',ref('button "CONTINUE"'))
run('network','har','start')
edge='supabase_kong_festapp-vo-wordpress-20261023'
def count_orders():
    return int(subprocess.check_output(['docker','exec','supabase_db_festapp-vo-wordpress-20261023','psql','-U','postgres','-d','postgres','-Atqc',"select count(*) from eshop.orders where data->>'email'='storage-outage-verified@example.invalid'"],text=True))
assert count_orders()==0,'An earlier attempt exists; inspect it instead of replaying blindly'
subprocess.run(['docker','stop',edge],stdout=subprocess.DEVNULL,check=True)
try:
    try: urllib.request.urlopen('http://127.0.0.1:59821/functions/v1/vo-local-capture',timeout=5)
    except urllib.error.HTTPError as e: assert e.code in (502,503)
    except (urllib.error.URLError, TimeoutError): pass
    else: raise AssertionError('Edge outage not established')
    run('click',ref('button "SUBMIT ORDER"'))
    snap=''
    for _ in range(30):
        snap=run('snapshot','-i')
        if 'heading "Order Failed"' in snap: break
        assert 'Your order was accepted!' not in snap,'Unexpected acceptance during outage'
        time.sleep(.3)
    assert 'heading "Order Failed"' in snap, 'No actual Order Failed result during outage'
    (root/'.private/storage-error-snapshot.txt').write_text(snap)
    assert count_orders()==0
finally:
    subprocess.run(['docker','start',edge],stdout=subprocess.DEVNULL,check=True)
for _ in range(30):
    try: urllib.request.urlopen('http://127.0.0.1:59821/functions/v1/vo-local-capture',timeout=3)
    except urllib.error.HTTPError as e:
        if e.code==403: break
    except urllib.error.URLError: pass
    time.sleep(.3)
run('click',ref('button "BACK TO FORM"'))
run('click',ref('button "CONTINUE"'))
run('click',ref('button "SUBMIT ORDER"'))
for _ in range(40):
    snap=run('snapshot','-i')
    if 'Your order was accepted!' in snap: break
    time.sleep(.3)
assert 'Your order was accepted!' in snap and count_orders()==1
run('network','har','stop',str(root/'.private/storage-outage.har'))
har=json.loads((root/'.private/storage-outage.har').read_text())
entries=[e for e in har['log']['entries'] if '/functions/v1/send-ticket-order' in e['request']['url'] and e['request']['method']=='POST']
assert len(entries)==2
payloads=[json.loads(e['request']['postData']['text']) for e in entries]
assert payloads[0]['commandId']==payloads[1]['commandId'] and payloads[0]['clientId']==payloads[1]['clientId']
result={'status':'PASS','storage':'localStorage and sessionStorage getters throw SecurityError in all frames','failure':'actual owned gateway container stopped; connection failed before SQL owner','http_statuses':[e['response']['status'] for e in entries],'same_command_and_client_identity':True,'orders_after_failure':0,'orders_after_retry':1}
(root/'evidence/storage-outage-receipt.json').write_text(json.dumps(result,indent=2)+'\n')
print('PASS: blocked storage, real gateway outage, same-command UI retry, exactly one stored order')
