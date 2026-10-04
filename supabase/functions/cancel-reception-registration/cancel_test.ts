import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { cancelRegistration } from "./cancel.ts";
const user = "00000000-0000-4000-8000-000000000001";
function fixture() {
  const calls: string[] = [];
  const userClient = { rpc() { calls.push("domainCancel"); return Promise.resolve({data:{code:200},error:null}); } } as unknown as SupabaseClient;
  const row = { userId: user, authEmail:"9+guest@test.local" };
  const admin = {
    rpc(name:string) { calls.push(name); return Promise.resolve({data:row,error:null}); },
    auth:{admin:{
      generateLink(input:{type:string}) { calls.push(`generate:${input.type}`); return Promise.resolve({data:{user:{id:user},properties:{hashed_token:"proof"}},error:null}); },
      signOut() { calls.push("revokeRejectedMint"); return Promise.resolve({error:null}); },
    }},
  } as unknown as SupabaseClient;
  const anon = {auth:{verifyOtp(input:{type:string}) { calls.push(`verify:${input.type}`); return Promise.resolve({data:{session:{user:{id:user},access_token:"temporary"}},error:null}); }}} as unknown as SupabaseClient;
  return {calls,userClient,admin,anon};
}
Deno.test("cancel blocks domain, holds shared lease through global revocation, then records receipt",async()=>{
  const {calls,userClient,admin,anon}=fixture();
  const result=await cancelRegistration(42,user,userClient,admin,anon,async()=>{calls.push("globalSignOut");});
  assertEquals(calls,["domainCancel","resolve_existing_user_session_v1","acquire_existing_user_session_lease_v1","generate:recovery","verify:recovery","check_existing_user_session_lease_v1","globalSignOut","check_existing_user_session_lease_v1","release_existing_user_session_lease_v1","mark_reception_auth_revoked_v1"]);
  assertEquals(result,{status:200,body:{status:"cancelled"}});
});
Deno.test("failed auth revocation keeps domain blocked and receipt pending",async()=>{
  const {calls,userClient,admin,anon}=fixture();
  const result=await cancelRegistration(42,user,userClient,admin,anon,async()=>{calls.push("globalSignOut");throw new Error("unavailable");});
  assertEquals(calls.includes("release_existing_user_session_lease_v1"),false);
  assertEquals(calls.includes("mark_reception_auth_revoked_v1"),false);
  assertEquals(result,{status:202,body:{status:"domain_blocked_auth_revocation_pending"}});
});
