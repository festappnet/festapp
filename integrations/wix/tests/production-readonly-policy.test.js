import test from 'node:test';
import assert from 'node:assert/strict';
import {permitsProductionRead, PUBLIC_FORM, PUBLIC_RPC} from './production-readonly-policy.mjs';
const key = `header.${Buffer.from(JSON.stringify({role:'anon'})).toString('base64url')}.signature`;
const read = {url:PUBLIC_RPC,method:'POST',postData:JSON.stringify({form_link:PUBLIC_FORM}),headers:{apikey:key,authorization:`Bearer ${key}`,origin:'https://vstupenky.online'}};
test('production probe admits only the exact public anonymous SELECT and its preflight', () => {
  assert.equal(permitsProductionRead(read), true);
  assert.equal(permitsProductionRead({url:PUBLIC_RPC,method:'OPTIONS',headers:{origin:'https://vstupenky.online'}}), true);
  for (const altered of [
    {url:PUBLIC_RPC+'?extra=1'}, {url:PUBLIC_RPC.replace('https:','http:')},
    {url:PUBLIC_RPC.replace('get_form_by_link','select_spot')},
    {url:'https://api.festapp.net/functions/v1/send-ticket-order'},
    {url:'https://other.supabase.co/rest/v1/rpc/get_form_by_link'},
    {method:'PATCH'}, {method:'DELETE'}, {method:'GET'},
    {postData:JSON.stringify({form_link:'another'})},
    {postData:JSON.stringify({form_link:PUBLIC_FORM,secret:'unexpected'})},
    {headers:{...read.headers,origin:'https://other.invalid'}}, {postData:'null'}, {postData:'[]'}, {headers:{}},
    {headers:{...read.headers,cookie:'session=unexpected'}},
    {headers:{...read.headers,authorization:'Bearer signed-user-session'}},
  ]) assert.equal(permitsProductionRead({...read,...altered}),false,JSON.stringify(altered));
});
