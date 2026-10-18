import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { generateKeyPair, exportJWK, SignJWT } from "npm:jose@6.1.3";
import { handleGoogleAuth } from "./googleAuthFlow.ts";
import { hash, randomSecret } from "./googleAuthProtocol.ts";

Deno.test("broker bootstraps a host-only cookie, validates signed OIDC and exchanges one handoff using a verifier", async () => {
  const env = { SUPABASE_URL: "https://broker-fixture.invalid", SUPABASE_ANON_KEY: "anon", SUPABASE_SERVICE_ROLE_KEY: "service", GOOGLE_OIDC_CLIENT_ID: "client-fixture", GOOGLE_OIDC_CLIENT_SECRET: "secret-fixture", GOOGLE_OIDC_CALLBACK_URL: "https://api.fixture.invalid/functions/v1/google-auth-callback", GOOGLE_AUTH_ENCRYPTION_KEY: "ab".repeat(32), GOOGLE_AUTH_MAILBOX_HMAC_KEY: "cd".repeat(32) };
  const previous = Object.fromEntries(Object.keys(env).map(k=>[k,Deno.env.get(k)]));
  for(const [k,v] of Object.entries(env)) Deno.env.set(k,v);
  const databaseUrl = Deno.env.get("GOOGLE_AUTH_DATABASE_URL");
  async function sql(statement: string) {
    const result = await new Deno.Command("psql", {
      args: [databaseUrl!, "-XAtq", "-v", "ON_ERROR_STOP=1", "-c", statement],
      stdout: "piped", stderr: "piped",
    }).output();
    if (!result.success) throw new Error(new TextDecoder().decode(result.stderr));
    return new TextDecoder().decode(result.stdout).trim();
  }
  if (databaseUrl) {
    assert(["localhost", "127.0.0.1", "[::1]"].includes(new URL(databaseUrl).hostname), "require a loopback test database");
    assertEquals(await sql("SELECT count(*) FROM festapp_test_support.disposable_environment WHERE singleton"), "1");
    console.log("Google admission uses the real SQL contract in a disposable database");
  }
  const originalFetch=globalThis.fetch;
  const client={client_id:"1:web:https://app.fixture.invalid",organization:1,origin:"https://app.fixture.invalid",redirect_uri:"https://app.fixture.invalid/google-auth",enabled:true};
  let attempt: Record<string,unknown> = {};
  const key=await generateKeyPair('RS256');
  const jwk={...await exportJWK(key.publicKey),kid:'fixture-key',alg:'RS256',use:'sig'};
  let idToken='', minted=false;
  const json=(data:unknown)=>new Response(JSON.stringify(data),{headers:{'Content-Type':'application/json'}});
  const calls:string[]=[];
  globalThis.fetch=async(input,init)=>{
    const url=new URL(typeof input==='string'?input:input instanceof URL?input.href:input.url);
    calls.push(url.pathname);
    if(url.href.startsWith('https://www.googleapis.com/oauth2/v3/certs'))return json({keys:[jwk]});
    if(url.href.startsWith('https://oauth2.googleapis.com/token')) return json({id_token:idToken});
    if(url.pathname==='/rest/v1/external_login_clients') return json(client);
    if(url.pathname==='/rest/v1/external_login_attempts') {
      if(url.searchParams.get('status') && url.searchParams.get('status')!==`eq.${attempt.status}`)return new Response('{}',{status:404});
      return json(attempt);
    }
    const body=JSON.parse(String(init?.body??'{}'));
    if(url.pathname.endsWith('/consume_auth_abuse_v1')) {
      // Match the canonical SQL admission contract, including digest encoding.
      if (databaseUrl) {
        const quote = (value: string) => "'" + value.replaceAll("'", "''") + "'";
        // Roll back each admission: no fixtures or counters survive this test.
        const accepted = await sql(`BEGIN;
          SET LOCAL request.jwt.claims='{"role":"service_role"}';
          SELECT public.consume_auth_abuse_v1(${quote(body.p_family)}, ${quote(body.p_key_hash)});
          ROLLBACK;`);
        return json(accepted === "t");
      }
      return json(/^[0-9a-f]{64}$/.test(body.p_key_hash));
    }
    if(url.pathname.endsWith('/google_auth_transition_v1')){
      const p=body.p_payload;
      switch(body.p_operation){
        case 'start': attempt={id:body.p_attempt,client_id:client.client_id,organization:1,status:'created',challenge:p.challenge,state_hash:p.stateHash,nonce_hash:p.nonceHash,bootstrap_hash:body.p_secret_hash,verifier_encrypted:p.verifierEncrypted,expires_at:new Date(Date.now()+600000).toISOString(),origin:client.origin,redirectUri:client.redirect_uri}; break;
        case 'bootstrap':
          if(attempt.status!=='created'||attempt.bootstrap_hash!==body.p_secret_hash)return new Response(JSON.stringify({message:'invalid_provider_proof'}),{status:400});
          attempt={...attempt,status:'bootstrapped',browser_hash:p.browserHash};break;
        case 'provider': attempt={...attempt,status:'provider_verified',issuer:p.issuer,subject:p.subject,email:p.email,mailbox_verified:p.mailboxVerified,handoff_hash:p.handoffHash};break;
        case 'claim':
          if(attempt.status!=='provider_verified'||attempt.handoff_hash!==body.p_secret_hash||attempt.challenge!==p.challenge)return new Response(JSON.stringify({message:'invalid_provider_proof'}),{status:400});
          attempt={...attempt,status:'awaiting_account_proof',continuation_hash:p.continuationHash};break;
        default: throw new Error('Unexpected operation');
      }
      return json(attempt);
    }
    if(url.pathname.includes('/auth/v1/'))minted=true;
    throw new Error(`Unexpected fixture request ${url.pathname}`);
  };
  const post=(endpoint:'start'|'complete',body:unknown,origin=client.origin)=>handleGoogleAuth(endpoint,new Request(`https://api.fixture.invalid/functions/v1/google-auth-${endpoint}`,{method:'POST',headers:{Origin:origin,'Content-Type':'application/json'},body:JSON.stringify(body)}));
  try {
    const capability = await post('start', { clientId: client.client_id, organization: 1, operation: 'capability' });
    assertEquals(capability.status, 200);
    assertEquals(await capability.json(), { enabled: true });
    const verifier=randomSecret();
    const started=await post('start',{clientId:client.client_id,organization:1,challenge:await hash(verifier)});
    assertEquals(started.status,200);
    assertEquals(started.headers.get('Access-Control-Allow-Origin'),client.origin);
    const start=await started.json();
    const bootstrap=await handleGoogleAuth('start',new Request(start.url));
    assertEquals(bootstrap.status,303);
    const cookie=bootstrap.headers.get('Set-Cookie')!;
    assert(cookie.includes('Secure; HttpOnly; SameSite=Lax; Path=/; Max-Age=600'));
    assertEquals(cookie.includes('Domain='),false);
    const provider=new URL(bootstrap.headers.get('Location')!);
    assertEquals(provider.searchParams.get('scope'),'openid email profile');
    const state=provider.searchParams.get('state')!;
    idToken=await new SignJWT({nonce:provider.searchParams.get('nonce'),email:'person@example.com',email_verified:true}).setProtectedHeader({alg:'RS256',kid:'fixture-key'}).setIssuer('https://accounts.google.com').setSubject('unaltered-google-sub').setAudience(env.GOOGLE_OIDC_CLIENT_ID).setIssuedAt().setExpirationTime('5m').sign(key.privateKey);
    const callbackUrl=`${env.GOOGLE_OIDC_CALLBACK_URL}?state=${state}&code=fixture-code`;
    const noCookie=await handleGoogleAuth('callback',new Request(callbackUrl));
    assertEquals(noCookie.status,400);
    const callback=await handleGoogleAuth('callback',new Request(callbackUrl,{headers:{Cookie:cookie.split(';')[0]}}));
    assertEquals(callback.status,303);
    assertEquals(attempt.subject,'unaltered-google-sub');
    const handoff=new URL(callback.headers.get('Location')!);
    assertEquals(handoff.origin,client.origin);
    assertEquals(handoff.searchParams.has('access_token'),false);
    const body={clientId:client.client_id,organization:1,attempt:start.attempt,operation:'claim',code:handoff.searchParams.get('google_code'),verifier};
    const wrongVerifier=await post('complete',{...body,verifier:randomSecret()});
    assertEquals(wrongVerifier.status,400);
    const wrongOrigin=await post('complete',body,'https://evil.invalid');
    assertEquals(wrongOrigin.status,400);
    assertEquals(wrongOrigin.headers.get('Access-Control-Allow-Origin'),null);
    const complete=await post('complete',body);
    assertEquals(complete.status,200);
    const result=await complete.json();
    assertEquals(result.status,'needs_account_proof');
    assertEquals(typeof result.continuation,'string');
    assertEquals(minted,false,'email equality never issues a session');
    const replay=await post('complete',body);
    assertEquals(replay.status,400);
    assertEquals(calls.includes('/auth/v1/admin/generate_link'),false);
  } finally {
    globalThis.fetch=originalFetch;
    for(const[k,v]of Object.entries(previous)){if(v===undefined)Deno.env.delete(k);else Deno.env.set(k,v);}
  }
});
