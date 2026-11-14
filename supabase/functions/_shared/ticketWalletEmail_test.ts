import {assert,assertEquals,assertRejects,assertThrows} from 'jsr:@std/assert@1';
import {walletEmailProviders} from './wallet/emailProviders.ts';
import {prepareWalletEmail,ticketWalletEnabled,walletEmailCopy,walletEmailTicket,walletEmailSection,walletTicketLabel,googleWalletBadgeUrl} from './ticketWalletEmail.ts';
import {prepareTicketDelivery} from './ticketDelivery.ts';
import {renderEmail} from './emailDelivery.ts';
Deno.test('email worker offers Wallet without access to the isolated signing credential',async()=>{
 const previousKey=Deno.env.get('EMAIL_PAYLOAD_KEY');
 const previousSigning=Deno.env.get('GOOGLE_WALLET_SERVICE_ACCOUNT');
 Deno.env.set('EMAIL_PAYLOAD_KEY',btoa('a'.repeat(32)));
 Deno.env.delete('GOOGLE_WALLET_SERVICE_ACCOUNT');
 try {
  let source:any;
  const rpc=async(name:string,p:any)=>{
   assertEquals(name,'prepare_ticket_wallet');
   if(p.p_hash)source={sealed:p.p_sealed,tokenHash:p.p_hash};
   return {providers:{google:true,apple:false},organization:3,occasion:7,webOrigin:'https://vstupenky.online',badgeUrls:{cs:'https://img.festapp.net/assets/google-wallet/v1/cs.png'},source};
  };
  const html=await prepareWalletEmail({message_id:'message',data:{lang:'cs'}},[{id:1,ticket_symbol:'SAMPLE'}],{is_enabled:true},rpc);
  assert(html.includes('https://vstupenky.online/wallet?provider=google&amp;lang=cs#'));
  assert(html.includes('Přidat do Peněženky Google'));
  assertEquals(Deno.env.get('GOOGLE_WALLET_SERVICE_ACCOUNT'),undefined);
 }finally{
  if(previousKey===undefined)Deno.env.delete('EMAIL_PAYLOAD_KEY');else Deno.env.set('EMAIL_PAYLOAD_KEY',previousKey);
  if(previousSigning===undefined)Deno.env.delete('GOOGLE_WALLET_SERVICE_ACCOUNT');else Deno.env.set('GOOGLE_WALLET_SERVICE_ACCOUNT',previousSigning);
 }
});
Deno.test('Wallet preference defaults true, rejects invalid values, and false/readiness skip issuance',async()=>{
 assertEquals(ticketWalletEnabled({}),true);assertEquals(ticketWalletEnabled({wallet_enabled:false}),false);
 for(const v of [null,0,'false'])assertThrows(()=>ticketWalletEnabled({wallet_enabled:v}));
 for(const feature of [{is_enabled:false},{is_enabled:true,wallet_enabled:false}])assertEquals(await prepareWalletEmail({},[],feature,()=>{throw new Error('must not call');},true),'');
 assertEquals(await prepareWalletEmail({},[],{is_enabled:true},()=>{throw new Error('must not call');},false),'');
});
Deno.test('1/N tickets across every delivery mode compose once per ticket in templates and retain capability on resend',async()=>{
 Deno.env.set('EMAIL_PAYLOAD_KEY',btoa('a'.repeat(32)));
 try {
  for(const mode of ['pdf_attachment','inline_qr','both'])for(const count of [1,3]){
   const saved=new Map<number,any>();let creates=0;
   const rpc=async(_name:string,p:any)=>{
    if(p.p_hash){creates++;saved.set(p.p_ticket,{sealed:p.p_sealed,tokenHash:p.p_hash});}
    return {providers:{google:true,apple:false},organization:1,occasion:7,webOrigin:'https://tenant.invalid',badgeUrls:{en:'https://img.festapp.net/assets/google-wallet/v1/en.png'},source:saved.get(p.p_ticket)};
   };
   const feature={code:'ticket',is_enabled:true,delivery_mode:mode};
   const tickets=Array.from({length:count},(_,i)=>({id:i+1,occasion:7,state:'paid',ticket_symbol:'EXACT-'+i}));
   const delivery=await prepareTicketDelivery({id:7,features:[feature]}, {},tickets,async()=>async()=>({bytes:new Uint8Array([1])}),async()=>new Uint8Array([2]));
   const wallet=await prepareWalletEmail({message_id:'message',data:{lang:'en'}},delivery.tickets,feature,rpc,true);
   assertEquals(creates,count);assertEquals(await prepareWalletEmail({message_id:'resend',data:{lang:'en'}},delivery.tickets,feature,rpc,true),wallet);assertEquals(creates,count);
   for(const body of ['custom body','{{tickets}} {{tickets}}']){
    const rendered=await renderEmail({to:'test@example.invalid',from:'sender@example.invalid',context:{organization:1},substitutions:{},ticketBlock:delivery.html+wallet,attachments:delivery.attachments},async()=>({template:{id:1,subject:'Tickets',html:body},wrapper:{id:2,html:'{{content}}'}}));
    assertEquals((rendered.html.match(/\/wallet\?/g)??[]).length,count);
   }
  }
 }finally{Deno.env.delete('EMAIL_PAYLOAD_KEY');}
});
Deno.test('Wallet RPC failures propagate only from the optional owner, not original delivery',async()=>{
 await assertRejects(()=>prepareWalletEmail({},[{id:1}],{is_enabled:true},async()=>{throw new Error('offline');},true));
 const delivery=await prepareTicketDelivery({id:7,features:[{is_enabled:true,code:'ticket',delivery_mode:'inline_qr'}]}, {},[{id:1,occasion:7,ticket_symbol:'ORIGINAL',state:'paid'}],async()=>{throw new Error('no pdf expected');},async()=>new Uint8Array([1]));
 assert(delivery.html.includes('ORIGINAL'));assertEquals(delivery.attachments.length,1);
});
Deno.test('Wallet offer uses localized official artwork and readable ticket labels in live and inert previews',async()=>{
 for(const lang of ['cs','sk','en','de','pl','uk']){
  const translations=JSON.parse(await Deno.readTextFile(new URL(`../../../assets/translations/${lang}.json`,import.meta.url))).TicketDelivery;
  const copy=walletEmailCopy[lang];
  assertEquals(copy.title,translations.walletEmailTitle);
  assertEquals(copy.help,translations.walletEmailHelp);
  assertEquals(copy.ticket,translations.walletEmailTicket);
  assertEquals(copy.fallback,translations.walletEmailFallback);
  const label=walletTicketLabel(2,3,lang)+' <script>';
  const preview=walletEmailSection([walletEmailTicket(label,[{provider:'google',badge:googleWalletBadgeUrl(lang)}],lang)],lang);
  assert(preview.includes(`/${lang}.png`));assert(preview.includes('height="48"'));
  assert(!preview.includes('href='));assert(!preview.includes('<script>'));assert(preview.includes('&lt;script&gt;'));
  assert(!preview.includes('Apple'));
  const live=walletEmailSection([walletEmailTicket(label,[{provider:'google',url:'https://tenant.invalid/wallet#capability',badge:googleWalletBadgeUrl(lang)}],lang)],lang);
  assertEquals((live.match(/href=/g)??[]).length,1);
  assertEquals(live.replace(/href="[^"]+" /,'').replace(/aria-label="[^"]+" /,'').replaceAll('<a ','<span ').replaceAll('</a>','</span>'),preview);
 }
 assertEquals(walletEmailSection([],'cs'),'');
});

Deno.test('Apple-only readiness offers the shared capability without Google credentials or a Google badge',async()=>{
 Deno.env.set('EMAIL_PAYLOAD_KEY',btoa('a'.repeat(32)));
 try {
  let source:any;
  const rpc=async(_name:string,p:any)=>{if(p.p_hash)source={sealed:p.p_sealed,tokenHash:p.p_hash};return {organization:1,occasion:7,webOrigin:'https://tenant.invalid',providers:{google:false,apple:true},source};};
  const html=await prepareWalletEmail({message_id:'message',data:{lang:'cs'}},[{id:1,ticket_symbol:'ORIGINAL'}],{is_enabled:true},rpc,{google:false,apple:true});
  assert(html.includes('Přidat do Apple Peněženky'));assert(!html.includes('Google'));assertEquals((html.match(/\/wallet\?/g)??[]).length,1);
 }finally{Deno.env.delete('EMAIL_PAYLOAD_KEY');}
});

Deno.test('email Wallet actions carry distinct provider and email language before the private fragment',()=>{
 for(const lang of ['cs','en'])for(const provider of ['google','apple']){
  const html=walletEmailTicket('Ticket',[{provider,url:'https://tenant.invalid/wallet#'+'a'.repeat(64)}],lang);
  assert(html.includes(`provider=${provider}&amp;lang=${lang}#`));
  assert(html.includes(lang==='cs'?(provider==='apple'?'Přidat do Apple Peněženky':'Přidat do Peněženky Google'):`Add to ${provider==='apple'?'Apple':'Google'} Wallet`));
 }
});

Deno.test('localized actions never substitute English artwork into a Czech email',()=>{
 const urls={en:'https://img.festapp.net/assets/google-wallet/v1/en.png',apple:{en:'https://img.festapp.net/assets/apple-wallet/v1/en.svg'}};
 for(const descriptor of Object.values(walletEmailProviders)){assertEquals(descriptor.badge(urls,'cs'),undefined);assert(descriptor.badge(urls,'en'));assert(descriptor.labelFallback);}
});

Deno.test('multiple providers share one ticket heading and actions have no repeated visible label',()=>{
 const label='Vstupenka 1 z 3 - Stůl 4 - Místo 7';
 const html=walletEmailTicket(label,[{provider:'google',badge:googleWalletBadgeUrl('cs')},{provider:'apple'}],'cs');
 assertEquals((html.match(/Vstupenka 1 z 3/g)??[]).length,1);
 assertEquals((html.match(/Přidat do Apple Peněženky/g)??[]).length,1);
 assertEquals((html.match(/Přidat do Peněženky Google/g)??[]).length,1);
 assert(html.includes('vertical-align:middle'));assert(html.includes('height="48"'));
 assertEquals(walletEmailTicket(label,[],'cs'),'');assert(!html.includes('href='));
});
Deno.test('live multi-ticket emails preserve one heading per ticket and each providers own destination',async()=>{
 Deno.env.set('EMAIL_PAYLOAD_KEY',btoa('a'.repeat(32)));
 try {
  const saved=new Map<number,any>();
  const rpc=async(_name:string,p:any)=>{
   if(p.p_hash)saved.set(p.p_ticket,{sealed:p.p_sealed,tokenHash:p.p_hash});
   return {organization:3,occasion:7,webOrigin:'https://tenant.invalid',providers:{google:true,apple:true},badgeUrls:{cs:googleWalletBadgeUrl('cs')},source:saved.get(p.p_ticket)};
  };
  const html=await prepareWalletEmail({message_id:'preview',data:{lang:'cs'}},[{id:1},{id:2},{id:3}],{is_enabled:true},rpc,{google:true,apple:true});
  for(let i=1;i<=3;i++)assertEquals((html.match(new RegExp(`>Vstupenka ${i} z 3<`,'g'))??[]).length,1);
  assert(html.includes('aria-label="Vstupenka 2 z 3 - Přidat do Apple Peněženky"'));
  assertEquals((html.match(/provider=apple/g)??[]).length,3);assertEquals((html.match(/provider=google/g)??[]).length,3);
 }finally{Deno.env.delete('EMAIL_PAYLOAD_KEY');}
});

Deno.test('compact official email artwork preserves aspect ratio at 48px across supported locales',async()=>{
 for(const lang of ['cs','sk','en','de','pl','uk']){
  const bytes=await Deno.readFile(new URL(`../../../assets/brand/google-wallet/condensed/${lang}.png`,import.meta.url));
  const header=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);const width=header.getUint32(16),height=header.getUint32(20);
  const artwork=walletEmailProviders.google.artwork(googleWalletBadgeUrl(lang),lang);
  assert(artwork);assertEquals(artwork.url,`https://img.festapp.net/assets/google-wallet/v1/condensed/${lang}.png`);
  assert(Math.abs(artwork.width-width/height*48)<0.01);assert(artwork.width+16<=232);
  assertEquals(walletEmailProviders.google.artwork('https://untrusted.invalid/button.png',lang),undefined);
 }
});
