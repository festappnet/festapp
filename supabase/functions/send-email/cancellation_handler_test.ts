import { assertEquals, assertExists } from "jsr:@std/assert@1";

Deno.test("actual send-email handler preserves automatic identity, explicit resend and authorization", async () => {
  const environment = { SUPABASE_URL: "https://cancellation-handler.invalid", SUPABASE_ANON_KEY: "fixture", SUPABASE_SERVICE_ROLE_KEY: "fixture" };
  const previous = Object.fromEntries(Object.keys(environment).map(k => [k,Deno.env.get(k)]));
  const originalServe=Deno.serve, originalFetch=globalThis.fetch;
  let handler: ((request:Request)=>Promise<Response>) | undefined;
  const queued: Record<string,unknown>[]=[];
  let editor=true, state="accepted";
  const json=(data:unknown)=>Response.json(data);
  globalThis.fetch=async(input,init)=>{
    const url=new URL(input instanceof Request?input.url:String(input));
    if(url.hostname!=="cancellation-handler.invalid") throw new Error("Unexpected external request");
    if(url.pathname==="/auth/v1/user") return json({id:"00000000-0000-4000-8000-000000000001",aud:"authenticated",email:"fixture@example.invalid"});
    if(url.pathname==="/rest/v1/occasion_users") return json({is_editor_order:editor});
    const args=JSON.parse(String(init?.body??"{}"));
    if(url.pathname.endsWith("/get_order_details_for_email")) return json({code:200,data:{occasion:{id:12,organization:1,unit:2}}});
    if(url.pathname.endsWith("/is_demo_occasion")) return json(false);
    if(url.pathname.endsWith("/enqueue_order_email")){queued.push(args);return json({message_id:"fixture-message"});}
    if(url.pathname.endsWith("/get_internal_email_state")) return json(state);
    throw new Error(`Unexpected fixture route ${url.pathname}`);
  };
  Deno.serve=((first:unknown)=>{handler=first as typeof handler;return {finished:Promise.resolve(),shutdown:()=>Promise.resolve(),ref(){},unref(){}} as unknown as Deno.HttpServer;}) as typeof Deno.serve;
  try {
    for(const [k,v] of Object.entries(environment)) Deno.env.set(k,v);
    await import("./index.ts?cancellation-handler-fixture");assertExists(handler);
    const request=(requestId?:string)=>new Request("https://cancellation-handler.invalid",{method:"POST",headers:{Authorization:"Bearer fixture"},body:JSON.stringify({code:"TICKET_ORDER_STORNO",data:{orderId:42},...(requestId?{requestId}:{})})});
    assertEquals((await handler(request())).status,200);
    assertEquals(queued[0].p_request,undefined);
    assertEquals(queued[0].p_data,{order_id:42,requested_by:"00000000-0000-4000-8000-000000000001"});
    state="expired";assertEquals((await handler(request())).status,503);
    assertEquals(queued[1],queued[0]);
    state="accepted";assertEquals((await handler(request("explicit-resend"))).status,200);
    assertEquals(queued[2].p_request,"manual:explicit-resend");
    editor=false;assertEquals((await handler(request())).status,403);assertEquals(queued.length,3);
  } finally {
    globalThis.fetch=originalFetch;Deno.serve=originalServe;
    for(const [k,v] of Object.entries(previous)) {if(v===undefined) Deno.env.delete(k);else Deno.env.set(k,v);}
  }
});
