// Child process of the owned-disposable GoTrue integration test. Its stdout is
// a private parent pipe; credentials must never be forwarded to test logs.
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.58.0';
import { issueExistingUserSession } from '../functions/_shared/issueExistingUserSession.ts';
const env = (name: string) => { const value = Deno.env.get(name); if (!value) throw new Error('Missing isolated test input'); return value; };
const base = env('FESTAPP_LOCAL_AUTH_URL'), anonKey = env('FESTAPP_LOCAL_AUTH_ANON'), serviceKey = env('FESTAPP_LOCAL_AUTH_SERVICE');
const organization = Number(env('FESTAPP_LOCAL_AUTH_ORGANIZATION'));
const client = (key: string) => createClient(base, key, {auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
const admin = client(serviceKey), browser = client(anonKey), delegated = client(anonKey);
function ensure(value: unknown, message: string): asserts value { if (!value) throw new Error(message); }
async function sql(statement: string) {
    const command = new Deno.Command('psql',{args:[env('FESTAPP_MCP_TEST_DATABASE_URL'),'-X','-qAt','-v','ON_ERROR_STOP=1'],stdin:'piped',stdout:'piped',stderr:'piped'}).spawn();
    const writer = command.stdin.getWriter();await writer.write(new TextEncoder().encode(statement));await writer.close();
    const output = await command.output();ensure(output.success,'Owned SQL request failed');return new TextDecoder().decode(output.stdout).trim();
}
admin.rpc = (async(name: string, args: Record<string,string>) => {
    ensure(['acquire_existing_user_session_lease_v1','check_existing_user_session_lease_v1','release_existing_user_session_lease_v1'].includes(name),'Unknown SQL lease boundary');
    ensure(Object.values(args).every(v=>/^[a-f0-9-]{36}$/.test(v)),'Invalid fixture UUID');
    const output=await sql(`BEGIN; SET LOCAL ROLE service_role; SET LOCAL request.jwt.claim.role='service_role'; SELECT public.${name}('${args.p_user}'::uuid,'${args.p_owner}'::uuid); COMMIT;`);
    return {error:null,data:output?JSON.parse(output):null};
}) as unknown as SupabaseClient['rpc'];
const email = `${organization}+mfa-${crypto.randomUUID()}@example.invalid`, password=crypto.randomUUID()+crypto.randomUUID();
const created = await admin.auth.admin.createUser({email,password,email_confirm:true});ensure(!created.error&&created.data.user,'Owned Auth user creation failed');
const userId=created.data.user.id;ensure(/^[a-f0-9-]{36}$/.test(userId)&&Number.isSafeInteger(organization),'Invalid fixture binding');
await sql(`INSERT INTO public.user_info(id,organization,email_readonly) VALUES('${userId}'::uuid,${organization},'${email.split('+').slice(1).join('+')}');`);
const login=await browser.auth.signInWithPassword({email,password});ensure(!login.error&&login.data.session,'Password login failed');
const factor=await browser.auth.mfa.enroll({factorType:'totp'});ensure(!factor.error&&factor.data,'TOTP enrollment failed');
function decodeBase32(input:string) { let bits='';for(const char of input.replace(/=+$/,''))bits+='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'.indexOf(char.toUpperCase()).toString(2).padStart(5,'0');return Uint8Array.from(bits.match(/.{8}/g)??[],part=>parseInt(part,2)); }
async function code() {
    const key=await crypto.subtle.importKey('raw',decodeBase32(factor.data!.totp.secret),{name:'HMAC',hash:'SHA-1'},false,['sign']);
    const counter=new Uint8Array(8);new DataView(counter.buffer).setBigUint64(0,BigInt(Math.floor(Date.now()/30000)));
    const mac=new Uint8Array(await crypto.subtle.sign('HMAC',key,counter)),offset=mac.at(-1)!&15;
    return String((new DataView(mac.buffer).getUint32(offset)&0x7fffffff)%1000000).padStart(6,'0');
}
const verified=await browser.auth.mfa.challengeAndVerify({factorId:factor.data.id,code:await code()});ensure(!verified.error,'Browser MFA verification failed');
const original=(await browser.auth.getSession()).data.session;ensure(original,'Original browser session missing');
let refused=false;try{await issueExistingUserSession({targetUserId:userId,expectedAuthEmail:email},admin,client(anonKey));}catch(error){refused=error instanceof Error&&error.message==='mfa_required';}
ensure(refused,'Ordinary mint must never bypass MFA');
// GoTrue rejects a reused OTP. The independent connection proves a new code.
await new Promise(resolve=>setTimeout(resolve,30000-Date.now()%30000+1000));
const issued=await issueExistingUserSession({targetUserId:userId,expectedAuthEmail:email},admin,delegated,{
    purpose:'delegation',completeMfa:async session=>{
        ensure(session.access_token!==original.access_token,'Browser access must not be adopted');
        const result=await delegated.auth.mfa.challengeAndVerify({factorId:factor.data!.id,code:await code()});ensure(!result.error,'Independent MFA verification failed');
        const upgraded=(await delegated.auth.getSession()).data.session;ensure(upgraded,'Independent session missing');return upgraded;
    },
});
const identity=await admin.auth.getUser(issued.access_token);ensure(!identity.error&&identity.data.user?.id===userId,'GoTrue did not verify the issued actor');
ensure((await delegated.auth.mfa.getAuthenticatorAssuranceLevel()).data?.currentLevel==='aal2','Independent session did not reach AAL2');
ensure((await browser.auth.getSession()).data.session?.refresh_token===original.refresh_token,'Browser refresh credential changed');
const refreshed=await delegated.auth.refreshSession();ensure(!refreshed.error&&refreshed.data.session,'Independent refresh failed');
const current=await admin.auth.getUser(refreshed.data.session.access_token);ensure(!current.error&&current.data.user?.id===userId,'GoTrue did not verify refresh actor');
console.log(JSON.stringify({issued:issued.access_token,refreshed:refreshed.data.session.access_token,browser:original.access_token,user:current.data.user}));
