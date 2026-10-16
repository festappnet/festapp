import { assertEquals, assertExists } from "jsr:@std/assert@1";

type Handler = (request: Request) => Promise<Response>;
const notification = "a0000000-0000-4000-8000-000000000001";
const secret = "fixture-notification-webhook-token";
let handler: Handler;
async function fixture(run: (handle: Handler, calls: Record<string, unknown>[]) => Promise<void>, rejection?: "quota" | "dispatch") {
  const names = { SUPABASE_URL: "https://push-test.invalid", SUPABASE_SERVICE_ROLE_KEY: "fixture-key", NOTIFY_WEBHOOK_TOKEN: secret };
  const before = Object.fromEntries(Object.keys(names).map(k => [k, Deno.env.get(k)]));
  const originalFetch = globalThis.fetch;
  const originalServe = Deno.serve;
  const calls: Record<string, unknown>[] = [];
  try {
    for (const [k,v] of Object.entries(names)) Deno.env.set(k,v);
    if (!handler) {
      Deno.serve = ((fn: Handler) => { handler=fn; return {} as Deno.HttpServer; }) as typeof Deno.serve;
      await import("./index.ts?push-behavior");
    }
    const { supabaseAdmin } = await import("../_shared/supabaseUtil.ts");
    Object.defineProperty(supabaseAdmin,"rpc",{configurable:true,value: async (name: string, args: unknown) => {
      if (name === "admit_notification_delivery_v1") {
        assertEquals(args,{p_notification:notification});
        if (rejection==="quota") return {data:null,error:{code:"PT429"}};
        if (rejection==="dispatch") return {data:{allowed:false},error:null};
        return {data:{id:notification,allowed:true,organization:1,occasion:2,occasion_link:"canonical-event",to:["canonical-user"],heading:"Canonical heading",content:"Canonical message",data:{path:"news"}},error:null};
      }
      assertEquals(name,"get_organization_notification_delivery_config");
      return {data:{onesignal_app_id:"fixture-app",onesignal_rest_api_key:"fixture-provider-key",default_url:"https://app.example.invalid"},error:null};
    }});
    globalThis.fetch = async (input, init) => {
      assertEquals(String(input),"https://onesignal.com/api/v1/notifications");
      assertExists(init?.signal);
      calls.push(JSON.parse(String(init?.body)));
      return Response.json({id:"fixture-provider-receipt"});
    };
    await run(handler,calls);
  } finally {
    globalThis.fetch=originalFetch;Deno.serve=originalServe;
    for (const [k,v] of Object.entries(before)) { if(v===undefined)Deno.env.delete(k);else Deno.env.set(k,v); }
  }
}
const request = (token=secret) => new Request("https://push-test.invalid/notify",{method:"POST",headers:{Authorization:`Bearer ${token}`,"Content-Type":"application/json"},body:JSON.stringify({record:{id:notification,organization:999,content:"forged content",to:["foreign-user"]}})});

Deno.test("signed push loads canonical content and reuses the existing log UUID for provider replay",async()=>{
  await fixture(async(handle,calls)=>{
    assertEquals((await handle(request())).status,202);
    assertEquals((await handle(request())).status,202);
    assertEquals(calls.length,2);
    for (const payload of calls) {
      assertEquals(payload.idempotency_key,notification);
      assertEquals(payload.contents,{en:"Canonical message"});
      assertEquals(payload.include_aliases,{external_id:["canonical-user"]});
    }
  });
});
for (const rejection of ["quota","dispatch"] as const) Deno.test(`${rejection} rejection never calls the push provider`,async()=>{
  await fixture(async(handle,calls)=>{assertEquals((await handle(request())).status,429);assertEquals(calls.length,0);},rejection);
});
Deno.test("unsigned push never reaches provider work",async()=>{
  await fixture(async(handle,calls)=>{assertEquals((await handle(request("wrong"))).status,401);assertEquals(calls.length,0);});
});
