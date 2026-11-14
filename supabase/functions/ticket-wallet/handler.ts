import type {WalletRegistry} from '../_shared/wallet/registry.ts';
export function walletHandler(registry:WalletRegistry,origins:string[]) {
 return async(req:Request)=>{
  const origin=req.headers.get('origin')||'';
  const isForm=req.headers.get('content-type')?.split(';')[0]==='application/x-www-form-urlencoded';
  const headers:Record<string,string>={'Cache-Control':'no-store','Referrer-Policy':'no-referrer','Vary':'Origin','Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Headers':'content-type, apikey, authorization, x-client-info'};
  const failure=(status:number,error='wallet_unavailable')=>{
   if(!isForm)return Response.json({error},{status,headers});
   const messages:Record<string,[string,string]>={
    cs:['Vstupenku se nepodařilo připravit','Vraťte se na předchozí stránku nebo znovu otevřete odkaz z e-mailu se vstupenkami. Pokud potíže trvají, obraťte se na pořadatele.'],
    sk:['Vstupenku sa nepodarilo pripraviť','Vráťte sa na predchádzajúcu stránku alebo znovu otvorte odkaz z e-mailu so vstupenkami. Ak problém pretrváva, kontaktujte organizátora.'],
    en:['Your ticket could not be prepared','Go back or reopen the link from your ticket email. If the problem continues, contact the organizer.'],
    de:['Ihr Ticket konnte nicht vorbereitet werden','Gehen Sie zurück oder öffnen Sie den Link aus Ihrer Ticket-E-Mail erneut. Falls das Problem weiterhin besteht, wenden Sie sich an den Veranstalter.'],
    pl:['Nie udało się przygotować biletu','Wróć lub ponownie otwórz link z wiadomości z biletami. Jeśli problem się powtarza, skontaktuj się z organizatorem.'],
    uk:['Не вдалося підготувати квиток','Поверніться назад або знову відкрийте посилання з листа з квитками. Якщо проблема не зникає, зверніться до організатора.'],
   };
   const locale=(req.headers.get('accept-language')||'en').slice(0,2);const lang=Object.hasOwn(messages,locale)?locale:'en';const [title,help]=messages[lang];
   return new Response(`<!doctype html><html lang="${lang}"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><style>html{color-scheme:light}body{max-width:440px;margin:48px auto;padding:24px;background:white;color:#19243b;font:16px system-ui;line-height:1.6}</style><main><h1>${title}</h1><p>${help}</p></main></html>`,{status,headers:{...headers,'Content-Type':'text/html; charset=utf-8','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'"}});
  };
  if(!origins.includes(origin))return failure(403);
  headers['Access-Control-Allow-Origin']=origin;
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(req.method!=='POST')return new Response(null,{status:405,headers});
  try {
   if(Number(req.headers.get('content-length'))>1024)return failure(400);
   const reader=req.body?.getReader();if(!reader)throw new SyntaxError();
   const chunks:Uint8Array[]=[];let total=0;
   try {
    while(true){const {done,value}=await reader.read();if(done)break;total+=value.length;if(total>1024){await reader.cancel();throw new SyntaxError();}chunks.push(value);}
   }finally{reader.releaseLock();}
   const bytes=new Uint8Array(total);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
   const text=new TextDecoder().decode(bytes);
   const form=isForm?new URLSearchParams(text):null;
   const body=form?Object.fromEntries(form):JSON.parse(text);
   if(!body||typeof body.token!=='string'||! /^[a-f0-9]{64}$/.test(body.token)||Object.keys(body).some(k=>!['token','provider','action','part','revision'].includes(k))||
    (body.provider!==undefined&&!registry.has(body.provider))||
    (body.action!==undefined&&!['plan','issue'].includes(body.action))||
    (body.revision!==undefined&&(typeof body.revision!=='string'||! /^[a-f0-9]{64}$/.test(body.revision)))||
    (body.part!==undefined&&(form?! /^(0|[1-9][0-9]{0,2})$/.test(body.part):!Number.isInteger(body.part)||body.part<0||body.part>999))||
    (form&&(form.getAll('token').length!==1||form.getAll('provider').length!==1||['action','part','revision'].some(key=>form.getAll(key).length>1))))return failure(400);
   // The trusted gateway must replace, rather than append arbitrary client IP headers.
   const source=req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()||'unknown';
   const connector=registry.resolve(body.provider??registry.defaultId);
   if(form&&(connector.delivery!=='file'||body.action==='plan'))return failure(400);
   const input={token:body.token,source,origin,...(body.part!==undefined?{part:Number(body.part)}:{}),...(body.revision!==undefined?{revision:body.revision}:{})};
   if(body.action==='plan'){
    const plan=await connector.plan?.(input);
    return plan?Response.json(plan,{headers}):failure(404);
   }
   const result=await connector.issue(input);
   if(!result)return failure(404);
   if(result.kind==='file'){
    if(!/^[a-zA-Z0-9_.-]+$/.test(result.filename))throw new Error('wallet_filename');
    return new Response(result.bytes,{headers:{...headers,'Content-Type':result.contentType,'Content-Disposition':`attachment; filename="${result.filename}"`,'X-Content-Type-Options':'nosniff'}});
   }
   return Response.json({url:result.url,state:result.state},{headers});
  }catch(error){return failure(error instanceof SyntaxError?400:503,error instanceof SyntaxError?'wallet_unavailable':'wallet_retry');}
 };
}
