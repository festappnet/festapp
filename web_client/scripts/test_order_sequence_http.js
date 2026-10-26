import assert from 'node:assert/strict';
const url=process.env.SUPABASE_URL, key=process.env.SUPABASE_ANON_KEY;
if (!url || !key || !['127.0.0.1','localhost'].includes(new URL(url).hostname)) throw new Error('Disposable loopback REST/Auth required');
for (const [name,body] of [['next_order_sequence',{p_occasion:1}],['backfill_order_sequences',{p_occasion:1}]]) {
 const response=await fetch(`${url}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify(body)});
 assert.ok([401,403,404].includes(response.status),`${name}: ${response.status}`);
}
const login=await fetch(`${url}/auth/v1/token?grant_type=password`,{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:JSON.stringify({email:'1+t@t.com',password:'test'})});
assert.equal(login.status,200);
const token=(await login.json()).access_token;
const headers={apikey:key,Authorization:`Bearer ${token}`,'Content-Type':'application/json'};
const rpc=async(name,body)=>{
 const response=await fetch(`${url}/rest/v1/rpc/${name}`,{method:'POST',headers,body:JSON.stringify(body)});
 assert.equal(response.status,200,`${name}: ${await response.clone().text()}`);return response.json();
};
const bundle=await rpc('get_orders_tab_data',{p_occasion_link:'e2e-tabs-a'});
assert.equal(bundle.orders.length,3); assert.deepEqual(bundle.orders.map(o=>Number(o.order_sequence)).sort(),[1,2,3]);
for(const order of bundle.orders){
 const history=await rpc('get_order_history',{order_id:order.id});
 assert.equal(Number(history.data.order.order_sequence),Number(order.order_sequence));
 assert.ok(history.data.history.every(h=>Number(h.order_sequence)===Number(order.order_sequence)));
}
const all=await rpc('get_orders',{p_occasion_link:'e2e-tabs-a'});
assert.ok(all.data.orders.every(o=>Number(o.order_sequence)>0));
const byForm=await rpc('get_orders',{p_occasion_link:'e2e-tabs-a',p_form_link:'e2e-first-form'});
assert.ok(byForm.data.orders.every(o=>Number(o.order_sequence)>0));
console.log('PASS: local Auth + REST, both orders projections/history metadata, private allocator and retired residual RPC blocked');
