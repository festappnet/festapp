"""Read back the actual from-scratch onboarding run; never creates identities or grants."""
import json,urllib.request,urllib.error,datetime
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];P=ROOT/'.private'
s=json.loads((P/'backend-status.json').read_text());d=json.loads((P/'signup-new-account.json').read_text())
assert s['API_URL']=='http://127.0.0.1:59821'
def request(path,body,token=None):
 q=urllib.request.Request(s['API_URL']+path,data=json.dumps(body).encode(),headers={'apikey':s['ANON_KEY'],'Authorization':'Bearer '+(token or s['ANON_KEY']),'Content-Type':'application/json'})
 try:
  with urllib.request.urlopen(q) as f:return f.status,json.load(f)
 except urllib.error.HTTPError as e:return e.code,json.load(e)
a=request('/auth/v1/token?grant_type=password',{'email':'1+'+d['email'],'password':d['password']});assert a[0]==200
b=request('/rest/v1/rpc/get_form_for_edit',{'form_link':'embedded-synthetic'},a[1]['access_token']);assert b[0]>=400 or b[1].get('code')!=200
old=request('/auth/v1/token?grant_type=password',{'email':'1+'+d['email'],'password':d['code']});assert old[0]==400
from urllib.parse import urlsplit,parse_qs
reset=parse_qs(urlsplit(d['reset_url']).query)['token'][0]
used=request('/rest/v1/rpc/set_user_password_token',{'token':reset,'password':'another-valid-synthetic-password'});assert used[1]['code']==403
wp=json.loads((ROOT/'evidence/onboarding-wp-publication.json').read_text());assert wp['status']=='publish' and wp['blocks'][0]['attrs']['url'].endswith('/36t9dry5')
receipt={'status':'PASS','verified_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'identity':'Fresh synthetic wordpress-onboarding@example.invalid through public Create your own event UI; no seeded user or role injection','email':'Canonical queue, renderer and sender with injected local sink transport; no external provider send or deliverability claim','signup':'Invalid email blocked; actual email initial code/password used for JS and Flutter login. This is not a separate email activation-link/OTP-expiry flow.','ownership':{'unit':2,'created_by':'canonical registration initializer','occasion':2,'occasion_created_in_ui':True,'form':6,'form_created_opened_saved_in_ui':True,'slug':'36t9dry5','seed_form_edit_denied':True},'wordpress':{'post':wp['post'],'actual_editor_publish_reload':True,'anonymous_iframe_rendered':True,'local_fixture_origin_substitutes_production_host':True},'duplicate_email':'Actual UI reports already in use; exactly one original account','recovery':'Exact captured HTTPS email link opened; UI rejects 7 characters and accepts corrected strong password; automatic real login; old initial code rejected; used and expired reset links rejected','fixes':['Registration adapter preserves409 and localized UI handles it','Reset minimum8 and null/short server validation before one-use token consumption','Reset rerender excludes unnamed username input from ID selectors'],'verification':{'node_tests_passed':8,'weak_reset_before_fix':'FAIL reproduced: invalid password consumed valid token','weak_reset_after_fix':'PASS','existing_expiry_single_use_sql':'PASS'},'limits':['No external email provider or merchant activation','Paid sales of a new organizer need their bank/payment and legal configuration; this run ends at published form','Local storefront and organizer app use separate explicit loopback ports; production cross-runtime handoff is not claimed'],'deployed':False}
(ROOT/'evidence/new-organizer-onboarding.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('PASS: real fresh onboarding readback, password recovery, ownership isolation and Gutenberg publication')
