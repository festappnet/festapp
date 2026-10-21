import {assertEquals,assertExists} from 'jsr:@std/assert@1';
const testEnvironment={SUPABASE_URL:'https://edge-test.invalid',SUPABASE_ANON_KEY:'synthetic-anon',SUPABASE_SERVICE_ROLE_KEY:'synthetic-service'};

Deno.test('saved ticket preview works when the demo registry rejects direct service-role reads', async () => {
  const previousEnv = Object.fromEntries(Object.keys(testEnvironment).map(key => [key,Deno.env.get(key)]));
  const previousFetch = globalThis.fetch;
  const layout = JSON.parse(await Deno.readTextFile('database/fixtures/demo_occasions/concert-layout.json'));
  const replies: string[] = [];
  try {
    for(const [key,value] of Object.entries(testEnvironment))Deno.env.set(key,value);
    globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      replies.push(url.pathname);
      const json=(value:unknown,status=200)=>Promise.resolve(new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json'}}));
      if(url.origin!==testEnvironment.SUPABASE_URL)throw new Error('Unexpected external request: '+url.origin);
      if(url.pathname==='/rest/v1/occasions')return json({id:7,organization:1,title:'Koncert',features:[{code:'ticket',ticket_type:'wide',layout}],data:{place_name:'Klub'}});
      if(url.pathname==='/rest/v1/demo_occasions')return json({message:'permission denied for table demo_occasions',code:'42501'},403);
      if(url.pathname==='/rest/v1/rpc/is_demo_occasion')return json(true);
      if(url.pathname==='/rest/v1/rpc/admit_ticket_preview_limits_v1'){const args=JSON.parse(String(init?.body));assertEquals(args.p_read_only,true);return json({abuseLimits:{'document.input.bytes':1048576,'document.asset.bytes':5242880,'document.output.bytes':16777216,'document.output.pages':20}});}
      if(url.pathname==='/rest/v1/rpc/admit_layout_resources_limits_v1'){
        const args=JSON.parse(String(init?.body));
        assertEquals(args.p_occasion,7);
        assertEquals(args.p_bytes>0,true);
        assertEquals('p_read_only' in args,false);
        const headers=new Headers(input instanceof Request?input.headers:init?.headers);
        assertEquals(headers.get('Authorization'),'Bearer synthetic-geometry-editor');
        return json({abuseLimits:{'document.input.bytes':1048576,'document.asset.bytes':5242880,'document.output.bytes':16777216,'document.output.pages':20}});
      }
      if(url.pathname==='/rest/v1/rpc/register_blueprint_text_resources'){
        const args=JSON.parse(String(init?.body));
        assertEquals(args.p_occasion,7);
        assertEquals(args.p_setup_draft,null);
        assertEquals(args.p_resources.protocol,2);
        assertEquals(Object.keys(args.p_resources.textLayouts).length,1);
        return json(null);
      }
      if(url.pathname==='/rest/v1/rpc/get_products_and_types')return json({product_types:[{id:1,occasion:7,title:'Vstupné',admission:true,offered:true,referenced:true}],products:[{id:1,product_type:1,title:'Základní vstupné',price:590,currency_code:'CZK'}]});
      if(url.pathname.startsWith('/rest/v1/rpc/get_is_'))return json(url.pathname.endsWith('get_is_editor_view_on_occasion'));
      throw new Error('Unexpected request: '+url.pathname);
    }) as typeof fetch;
    let handler: ((req: Request) => Response | Promise<Response>) | undefined;
    const serve=Deno.serve;
    Deno.serve=((fn: typeof handler)=>{handler=fn;return {addr:{transport:'tcp',hostname:'127.0.0.1',port:0},finished:Promise.resolve(),shutdown:async()=>{},ref(){},unref(){}};}) as typeof Deno.serve;
    try {await import('./index.ts');} finally {Deno.serve=serve;}
    assertExists(handler);
    const response=await handler(new Request('https://edge-test.invalid',{method:'POST',headers:{Authorization:'Bearer synthetic-viewer','Content-Type':'application/json'},body:JSON.stringify({occasionId:7,mode:'resolve',type:'wide',fontProtocol:2,readOnly:true})}));
    assertEquals(response.status,200,(await response.clone().text())+JSON.stringify(replies));
    const data=await response.json();
    assertEquals(data.template,layout.templates.wide);
    assertEquals(data.data.occasionTitle,'Koncert');
    assertEquals(data.data.productType,'Vstupné: Základní vstupné');
    assertEquals(data.background,null);
    assertExists(data.fonts);
    assertEquals(replies.includes('/rest/v1/demo_occasions'),false);
    assertEquals(replies.includes('/rest/v1/rpc/is_demo_occasion'),true);
    const fontId=Object.keys(data.fonts)[0];
    const fontResponse=await handler(new Request('https://edge-test.invalid',{method:'POST',headers:{Authorization:'Bearer synthetic-geometry-editor','Content-Type':'application/json'},body:JSON.stringify({occasionId:7,mode:'font',fontProtocol:2,fontId})}));
    assertEquals(fontResponse.status,200);
    assertEquals((await fontResponse.json()).id,fontId);
    assertEquals(replies.filter(path=>path==='/rest/v1/rpc/admit_layout_resources_limits_v1').length,1);
    const {fontFamilyCatalog}=await import('../_shared/ticketFonts.ts');
    const family=fontFamilyCatalog.find(f=>Object.values(f.faces).includes(fontId))!;
    const text={text:'Přejmenovaný stůl',role:'text',fontFamilyId:family.id,fontFaceId:fontId,size:24,language:'und',direction:'auto',lineHeight:1.2,align:'left',box:{x:0,y:0,width:240,height:100},fit:'wrap'};
    const renamed=await handler(new Request('https://edge-test.invalid',{method:'POST',headers:{Authorization:'Bearer synthetic-geometry-editor','Content-Type':'application/json'},body:JSON.stringify({occasionId:7,mode:'layout-text',resourceProtocol:2,batch:{requests:[text],numericFaces:[]}})}));
    assertEquals(renamed.status,200);
    assertEquals(Object.keys((await renamed.json()).textLayouts).length,1);
    assertEquals(replies.filter(path=>path==='/rest/v1/rpc/admit_layout_resources_limits_v1').length,2);
    assertEquals(replies.filter(path=>path==='/rest/v1/rpc/register_blueprint_text_resources').length,1);
  } finally {
    globalThis.fetch=previousFetch;
    for(const [key,value] of Object.entries(previousEnv))value===undefined?Deno.env.delete(key):Deno.env.set(key,value);
  }
});
