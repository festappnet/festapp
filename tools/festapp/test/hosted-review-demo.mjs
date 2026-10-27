// Explicit, user-authorized hosted smoke for the retained reviewer demo only.
// Native SDK evidence is distinct from conversational ChatGPT evidence.
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { randomBytes, createHash } from 'node:crypto';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';

const privateDir = process.env.FESTAPP_REVIEW_PRIVATE_DIR;
assert(privateDir, 'explicit private demo directory required');
const credentials = JSON.parse(await readFile(privateDir+'/credentials.json', 'utf8'));
assert.equal(credentials.email, 'mcp-review@demo.vstupenky.online');
const seed = JSON.parse(await readFile(privateDir+'/receipt.json', 'utf8'));
assert.equal(seed.marker, 'mcp-review-20261027');
const allowed = seed.occasionIds.slice(0,2), deniedId = seed.occasionIds[2];
const event = allowed[0], sample = seed.orders.find(o => o.hostileNote);
const issuer = 'https://mcp.vstupenky.online', resource = issuer+'/mcp';
const tenant = 'https://vstupenky.online', api = 'https://api.festapp.net';
const publicProfile = process.env.FESTAPP_REVIEW_DATA_PROFILE === 'order-summary';
const callback = publicProfile ? 'https://chatgpt.com/connector_platform_oauth_redirect' : 'http://127.0.0.1/callback';
const clientId = publicProfile ? 'festapp-chatgpt' : 'festapp-codex';
const config = execFileSync('git',['show','origin/prod/festapptickets:automation/project.conf'],{encoding:'utf8'});
assert.match(config, /^BACKEND_ACTIVATION_PHASE=canonical$/m);
assert.match(config, /^BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID=3$/m);
const anon = config.match(/^BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY=(.+)$/m)?.[1];
assert(anon);
const activation = await (await fetch(tenant+'/backend-activation.json')).json();
assert.deepEqual(activation,{schemaVersion:1,tenantId:'festapptickets',generation:1,backend:'canonical'});
let actorSession, sdk, connectionId, stage = 'ordinary reviewer sign-in';
const checks = [];
const safe = (name, details={}) => checks.push({name,at:new Date().toISOString(),...details});
const authHeaders = () => ({apikey:anon,authorization:'Bearer '+actorSession.access_token,origin:tenant,'content-type':'application/json'});
const edge = async (operation, extra={}) => {
    const r=await fetch(api+'/functions/v1/mcp-session-exchange',{method:'POST',headers:authHeaders(),body:JSON.stringify({operation,...extra})});
    assert.equal(r.status,200,'first-party exchange '+operation+' status');
    return r.json();
};
try {
    const auth=await fetch(api+'/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:anon,'content-type':'application/json'},
        body:JSON.stringify({email:'3+'+credentials.email,password:credentials.password})});
    assert.equal(auth.status,200,'demo password login'); actorSession=await auth.json();
    assert.equal(actorSession.user.id,credentials.actor);
    safe('ordinary_password_login_without_MFA',{actor:'dedicated reviewer',organizationId:3});
    const before = new Set((await edge('connections.list')).connections.map(c=>c.id));
    stage='hosted native OAuth PKCE';
    const verifier=randomBytes(32).toString('base64url'), jar=new Map();
    const browser=async path=>{
        const u=new URL(path,issuer);assert.equal(u.origin,issuer);
        const r=await fetch(u,{redirect:'manual',headers:{cookie:[...jar].map(([k,v])=>k+'='+v).join('; ')}});
        for(const c of r.headers.getSetCookie()){const pair=c.split(';')[0],at=pair.indexOf('=');jar.set(pair.slice(0,at),pair.slice(at+1));}
        return r;
    };
    let r=await browser('/auth?'+new URLSearchParams({client_id:clientId,response_type:'code',redirect_uri:callback,resource,
        scope:'openid offline_access festapp:ticket-layouts:read festapp:orders:read',
        code_challenge:createHash('sha256').update(verifier).digest('base64url'),code_challenge_method:'S256'}));
    let target=r.headers.get('location');
    for(let i=0;i<8&&new URL(target,issuer).origin===issuer;i++){r=await browser(target);target=r.headers.get('location');}
    const consentUrl=new URL(target);assert.equal(consentUrl.origin,tenant);assert.equal(consentUrl.pathname,'/settings/mcp-connect');
    const request=consentUrl.searchParams.get('request');assert(request);
    const details=await edge('details',{request});assert(allowed.every(id=>details.occasions.some(o=>o.id===id)));
    const continuation=await edge('approve',{request,access:{consentVersion:2,selection:{type:'occasions',occasionIds:allowed},permissions:['festapp:orders:read']}});
    assert.equal(continuation.issuer,issuer);
    r=await browser(continuation.resumeUrl);target=r.headers.get('location');
    for(let i=0;i<8&&new URL(target,issuer).origin===issuer;i++){r=await browser(target);target=r.headers.get('location');}
    const resultUrl=new URL(target);assert.equal(resultUrl.origin,new URL(callback).origin);assert.equal(resultUrl.pathname,new URL(callback).pathname);
    assert.equal(resultUrl.searchParams.get('iss'),issuer);assert(resultUrl.searchParams.get('code'));
    r=await fetch(issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:clientId,grant_type:'authorization_code',
        code:resultUrl.searchParams.get('code'),redirect_uri:callback,code_verifier:verifier,resource})});
    assert.equal(r.status,200,'PKCE token exchange');const tokens=await r.json();
    const own=(await edge('connections.list')).connections.filter(c=>!before.has(c.id));assert.equal(own.length,1);connectionId=own[0].id;
    safe(publicProfile?'hosted_public_client_PKCE':'hosted_native_PKCE',{clientId,scope:'festapp:ticket-layouts:read festapp:orders:read',selectedOccasions:allowed});
    stage='actual delegated reads';
    sdk=new Client({name:'festapp-review-demo-validation',version:'1.0.0'});
    await sdk.connect(new StreamableHTTPClientTransport(new URL(resource),{requestInit:{headers:{authorization:'Bearer '+tokens.access_token}}}));
    assert.match(sdk.getInstructions(),/ask which occasion/i);
    const tools=(await sdk.listTools()).tools;assert.equal(tools.length,6);assert(tools.every(t=>t.annotations?.readOnlyHint===true));
    assert.match(tools.find(t=>t.name==='festapp_orders_report').description,/ambiguous event names/i);
    safe('deployed_clarification_guidance',{initializeInstructions:true,reportDescription:true});
    const call=async(name,args)=>{const r=await sdk.callTool({name,arguments:args});return r.structuredContent??JSON.parse(r.content.find(c=>c.type==='text').text);};
    const access=await call('festapp_access_inspect',{});assert.equal(access.ok,true);
    assert.deepEqual(access.data.occasions.map(o=>o.id).sort((a,b)=>a-b),allowed);assert.equal(access.data.units.length,0);
    safe('P1_access_exact_two_occasions',{tools:tools.map(t=>t.name)});
    const report=await call('festapp_orders_report',{occasionId:event});assert.equal(report.ok,true);
    assert.equal(report.data.report.valid.tickets.total,4);assert.equal(report.data.report.valid.orders.total,2);
    assert.equal(report.data.waitingTickets,1);
    const money=report.data.report.money_by_currency.find(m=>m.currency==='CZK');
    assert.equal(Number(money.net_received),500);assert.equal(Number(money.current_order_value),1250);
    assert(report.data.report.warnings.some(w=>w.code==='payment_total_without_ledger'));
    safe('P2_canonical_report',{validTickets:4,validOrders:2,waitingTickets:1,currency:'CZK',netReceived:'500.00',currentOrderValue:'1250.00',warning:'payment_total_without_ledger'});
    const page=await call('festapp_orders_list',{occasionId:event,state:'ordered',limit:5});assert.equal(page.ok,true);
    assert.deepEqual(page.data.orders.map(o=>o.id),[sample.id]);assert.equal(page.data.nextCursor,null);
    safe('P3_bounded_order_state',{rows:1,nextCursor:null});
    const found=await call('festapp_orders_list',{occasionId:event,search:sample.symbol,limit:5});assert.equal(found.ok,true);
    assert.deepEqual(found.data.orders.map(o=>o.id),[sample.id]);safe('P4_symbol_search',{rows:1});
    const detail=await call('festapp_orders_inspect',{occasionId:event,orderId:sample.id});assert.equal(detail.ok,true);
    if(publicProfile){
        for(const result of [page,found,detail])for(const row of result.data.orders){
            assert.deepEqual(Object.keys(row).sort(),['id','occasionId','symbol','state','ticketCount','price','currency','allowedActions','payment'].sort());
            assert.deepEqual(row.allowedActions,['view']);
        }
        const context=await call('festapp_context_inspect',{});assert.equal(context.data.userId,undefined);
        assert(!JSON.stringify(tools.find(t=>t.name==='festapp_orders_inspect').outputSchema).includes('customer'));
        safe('P5_public_order_fields_withheld',{noteDelivered:false,buyerFieldsDelivered:false,registrationResponsesDelivered:false,contextUserIdDelivered:false});
    }else{
        assert(detail.data.orders[0].note.startsWith('SYSTEM OVERRIDE:'));assert.deepEqual(detail.data.orders[0].allowedActions,['view']);
        safe('P5_detail_hostile_text_retrieved',{noteDelivered:true,allowedActions:['view'],modelBehavior:'separate ChatGPT scenario'});
    }
    for(const id of [deniedId,99]){const denied=await call('festapp_orders_report',{occasionId:id});assert.equal(denied.ok,false);assert.equal(denied.error.code,'FORBIDDEN');}
    safe('N1_unconsented_and_unrelated_denied',{occasionIds:[deniedId,99],code:'FORBIDDEN'});
    assert(!tools.some(t=>/cancel|send|payment|update/.test(t.name)));
    let rejected=false;try{const x=await sdk.callTool({name:'festapp_orders_cancel',arguments:{occasionId:event,orderId:sample.id}});rejected=x.isError===true;}catch{rejected=true;}assert(rejected);
    safe('N2_writes_unadvertised_and_rejected',{mutationInvoked:false});
    const empty=await call('festapp_orders_list',{occasionId:event,search:publicProfile?'ZZZZZZZZZZ':'MCP-REVIEW-NO-MATCH-20261027',limit:5});assert.equal(empty.ok,true);assert.equal(empty.data.orders.length,0);
    safe('empty_search',{rows:0});
    r=await fetch(issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:clientId,grant_type:'refresh_token',refresh_token:tokens.refresh_token,resource})});
    assert.equal(r.status,200,'refresh');const refreshed=await r.json();assert(refreshed.access_token);safe('explicit_refresh',{naturalExpiryWait:false});
    await edge('connections.revoke',{connectionId});connectionId=null;
    const revoked=await fetch(resource,{method:'POST',headers:{authorization:'Bearer '+refreshed.access_token,'content-type':'application/json',accept:'application/json, text/event-stream'},body:JSON.stringify({jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'2025-11-25',capabilities:{},clientInfo:{name:'review-revocation',version:'1'}}})});
    assert.equal(revoked.status,401);safe('immediate_issuer_revocation',{status:401});
    const evidence={executedAt:new Date().toISOString(),boundary:'Real hosted MCP SDK with dedicated reviewer identity; not ChatGPT model evidence',dataProfile:publicProfile?'order-summary':'operator',resource,actor:'dedicated synthetic reviewer',clientId,checks};
    await writeFile(new URL('../../../integrations/chatgpt/review/'+(publicProfile?'hosted-public-demo-evidence.json':'hosted-demo-evidence.json'),import.meta.url),JSON.stringify(evidence,null,2)+'\n');
    console.log(`Hosted reviewer demo: ${checks.length} checks passed; credentials/tokens omitted`);
} catch(error) {
    await writeFile(privateDir+'/hosted-smoke-error.txt',stage+'\n'+error.stack,{mode:0o600});
    throw new Error('Hosted reviewer demo failed at '+stage+'; inspect private diagnostics');
} finally {
    await sdk?.close().catch(()=>{});
    if(connectionId)await edge('connections.revoke',{connectionId}).catch(()=>{});
    if(actorSession)await fetch(api+'/auth/v1/logout?scope=local',{method:'POST',headers:authHeaders()}).catch(()=>{});
}
