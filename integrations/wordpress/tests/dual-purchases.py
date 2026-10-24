"""Actual anonymous purchases through each independently installed WP plugin."""
from pathlib import Path
import subprocess,json,re,time
R=Path(__file__).resolve().parents[1]
B=['agent-browser','--config',str(R/'.private/stable-browser.json'),'--headed','false','--session','vo-shared-purchases']
def run(*a):return subprocess.check_output(B+list(a),text=True)
def ref(label):
 end=time.monotonic()+20
 while time.monotonic()<end:
  lines=run('snapshot','-i').splitlines();found=[l for l in lines if label in l]
  if found:return '@'+re.search(r'ref=(e\d+)',found[0])[1]
  time.sleep(.25)
 raise AssertionError('Missing control '+label)
DB='supabase_db_festapp-vo-wordpress-20261023'
q="select count(*) from eshop.orders where data->>'email' in ('acceptance@example.invalid','seats-final@example.invalid')"
assert subprocess.check_output(['docker','exec',DB,'psql','-U','postgres','-d','postgres','-Atqc',q],text=True).strip()=='0','Inspect existing orders instead of duplicating purchases'
run('open','http://localhost:59811/vo-block/');run('frame',ref('Iframe "Testovací vstupenky"'));run('fill',ref('textbox "Email *"'),'acceptance@example.invalid');run('click',ref('radio "Synthetic admission'));run('fill',ref('textbox "Name *"'),'Shared');run('fill',ref('textbox "Surname *"'),'Czech buyer');run('click',ref('button "CONTINUE"'));run('network','har','start');run('click',ref('button "SUBMIT ORDER"'));ref('Your order was accepted!');run('network','har','stop',str(R/'.private/shared-czech-order.har'))
run('frame','main');run('open','http://localhost:59811/vo-global-seats/');run('frame',ref('Iframe "Global reserved seats"'));run('fill',ref('textbox "Email *"'),'seats-final@example.invalid');run('click',ref('button "SEAT SELECTION"'));run('wait','.blueprint-seat-container[data-seat-id="2"]');run('click','.blueprint-seat-container[data-seat-id="2"]');run('click','.blueprint-btn-confirm');run('fill',ref('textbox "Name *"'),'Shared');run('fill',ref('textbox "Surname *"'),'Global seat buyer');run('click',ref('button "CONTINUE"'));run('network','har','start');run('click',ref('button "SUBMIT ORDER"'));ref('Your order was accepted!');run('network','har','stop',str(R/'.private/shared-global-order.har'))
print('PASS: real anonymous Czech ordinary ticket and global A2 seat orders through the final shared-source ZIPs')
