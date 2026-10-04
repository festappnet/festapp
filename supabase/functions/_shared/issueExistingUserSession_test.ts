import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { issueExistingUserSession } from "./issueExistingUserSession.ts";
const target = { targetUserId: "00000000-0000-4000-8000-000000000001", expectedAuthEmail: "1+person@example.com" };
function fixture({ lost = false, wrong = false, unavailable = false } = {}) {
  const calls: string[] = [];
  const row = { userId: target.targetUserId, authEmail: target.expectedAuthEmail };
  const session = { user: { id: wrong ? "other" : target.targetUserId }, access_token: "access", refresh_token: "refresh" };
  const admin = {
    rpc(name: string) { calls.push(name); return Promise.resolve({ error: null, data: unavailable || (lost && name.startsWith("check_")) ? null : row }); },
    auth: { admin: {
      generateLink(input: { type: string }) { calls.push(`generate:${input.type}`); return Promise.resolve({ error: null, data: { user: { id: target.targetUserId }, properties: { hashed_token: "internal" } } }); },
      signOut(_token: string, scope: string) { calls.push(`revoke:${scope}`); return Promise.resolve({ error: null }); },
    } },
  } as unknown as SupabaseClient;
  const anon = { auth: { verifyOtp(input: { type: string }) { calls.push(`verify:${input.type}`); return Promise.resolve({ error: null, data: { session } }); } } } as unknown as SupabaseClient;
  return { admin, anon, calls };
}
Deno.test("only recovery proofs, one owner, pre/post UUID and lease checks", async () => {
  const { admin, anon, calls } = fixture();
  const session = await issueExistingUserSession(target, admin, anon);
  assertEquals(session.user.id,target.targetUserId);
  assertEquals(calls,["acquire_existing_user_session_lease_v1","generate:recovery","verify:recovery","check_existing_user_session_lease_v1","check_existing_user_session_lease_v1","release_existing_user_session_lease_v1"]);
});
Deno.test("missing target never calls GoTrue", async () => {
  const { admin, anon, calls } = fixture({unavailable:true});
  await assertRejects(()=>issueExistingUserSession(target,admin,anon));
  assertEquals(calls,["acquire_existing_user_session_lease_v1"]);
});
for(const variation of [{lost:true},{wrong:true}]) Deno.test(`failed mint revokes only issued session, quarantines lease ${JSON.stringify(variation)}`,async()=>{
  const {admin,anon,calls}=fixture(variation);
  await assertRejects(()=>issueExistingUserSession(target,admin,anon));
  assertEquals(calls.includes("revoke:local"),true);
  assertEquals(calls.includes("release_existing_user_session_lease_v1"),false);
});
Deno.test("revocation holds lease until global signout and rejects receipt failure",async()=>{
  const {admin,anon,calls}=fixture();
  await issueExistingUserSession(target,admin,anon,{useSession:async()=>{calls.push("globalSignout");}});
  assertEquals(calls.indexOf("globalSignout")<calls.indexOf("release_existing_user_session_lease_v1"),true);
});

Deno.test("MFA login is blocked before generating OTP; revocation can still revoke",async()=>{
  const {admin,anon,calls}=fixture();
  const rpc=admin.rpc.bind(admin);
  admin.rpc=(async(name:string,params:Record<string,unknown>)=>{
    const result=await rpc(name,params);
    if(result.data)result.data.requiresMfa=true;
    return result;
  }) as unknown as typeof admin.rpc;
  await assertRejects(()=>issueExistingUserSession(target,admin,anon),Error,"mfa_required");
  assertEquals(calls.includes("generate:recovery"),false);
  await issueExistingUserSession(target,admin,anon,{purpose:"revoke",useSession:async()=>{calls.push("globalSignOut");}});
  assertEquals(calls.includes("globalSignOut"),true);
});
Deno.test("a late revocation/callback cannot return a session after the overall deadline",async()=>{
  const {admin,anon,calls}=fixture();
  const original=Date.now;let elapsed=0;const start=original();
  Date.now=()=>start+elapsed;
  try{
    await assertRejects(()=>issueExistingUserSession(target,admin,anon,{useSession:async()=>{elapsed=21_000;}}),Error,"auth_temporarily_unavailable");
    assertEquals(calls.includes("release_existing_user_session_lease_v1"),false);
    assertEquals(calls.includes("revoke:local"),true);
  }finally{Date.now=original;}
});
