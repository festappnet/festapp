import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.58.0';
import { handleMcpExchange } from '../../../../supabase/functions/mcp-session-exchange/handler.ts';
import { parseMcpTenants } from '../../../../supabase/functions/mcp-session-exchange/config.ts';
const input = JSON.parse(await Deno.readTextFile(Deno.args[0]));
if (input.api !== 'http://127.0.0.1:59721' && !(input.api === 'http://127.0.0.1:61421' && input.disposableProject === 'festapp-authz-20261020')) throw Error('task backend required');
const config = parseMcpTenants(JSON.stringify([input.tenant]))[0];
const options = { auth: { persistSession: false, autoRefreshToken: false } };
const admin = createClient(input.api,input.service,options);
const makeAnon = () => createClient(input.api,input.anon,options);
// Exercise the real handler over HTTP; TLS termination is a local test boundary.
const brokerFetch: typeof fetch = (input, init) => {
 const url = new URL(input instanceof Request ? input.url : input.toString());
 if (url.origin !== config.issuer) throw Error('unexpected broker origin');
 url.protocol = 'http:';
 return fetch(url,init);
};
Deno.serve({hostname:'127.0.0.1',port:input.port}, req => new URL(req.url).pathname === '/__closure-health' ? Response.json({instanceId:input.instanceId}) : handleMcpExchange(req,{config,admin,makeAnon,fetch:brokerFetch}));
