// Real preview handler and text preparation, with synthetic admission and font
// transport only. Run in a cold user worker with production filesystem rules.
import {handlePreview} from '../../supabase/functions/preview-ticket-layout/handler.ts';
import {fontCatalog, fontFamilyCatalog, fontMetrics} from '../../supabase/functions/_shared/ticketFonts.ts';

const fontId='gf:7f3ec5073a282c666c9a0063573345841229caf50ed34d33017e20d441bf5caf';
const entry=fontCatalog.find(f=>f.id===fontId)!;
const family=fontFamilyCatalog.find(f=>Object.values(f.faces).includes(fontId))!;
const limits={'document.input.bytes':1048576,'document.asset.bytes':5242880,'document.output.bytes':16777216,'document.output.pages':20};
Deno.serve(async () => {
  const bytes=await Deno.readFile(new URL('./Roboto.ttf',import.meta.url));
  let registered=0;
  const requests=[
    {text:'Bus',size:14,box:{x:-160,y:-12,width:320,height:24}},
    {text:'Driver',size:12,box:{x:-48,y:-10,width:96,height:20}},
  ].map(request=>({...request,role:'text',fontFamilyId:family.id,fontFaceId:fontId,
    language:'und',direction:'auto',lineHeight:1.2,align:'center',fit:'wrap'}));
  const response=await handlePreview(new Request('http://fixture.invalid',{
    method:'POST',headers:{Authorization:'Bearer synthetic-editor'},
    body:JSON.stringify({occasionId:7,mode:'layout-text',resourceProtocol:2,batch:{requests,numericFaces:[]}}),
  }),{
    authorize:async()=>({abuseLimits:limits}),
    font:async()=>({...entry,bytes,metrics:fontMetrics(bytes)}),
    registerLayoutTextResources:async(scope,resources)=>{
      if(scope.occasionId!==7||Object.values(resources.textLayouts).some(text=>text.path.length===0))
        throw Error('Invalid prepared text registration');
      registered++;
    },
    occasion:async()=>{throw Error('Unexpected occasion read');},
    products:async()=>{throw Error('Unexpected products read');},
    resources:async()=>{throw Error('Unexpected ticket resource read');},
  });
  const result=await response.json();
  return Response.json({status:response.status,registered,
    textIds:Object.keys(result.textLayouts??{}),error:result.error??null});
});
