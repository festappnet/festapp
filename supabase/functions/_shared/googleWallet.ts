/** Google Event Tickets only. No ticket/admission decisions live in this adapter. */
import { googleWalletAppearance, walletPublicImage } from './googleWalletAppearance.ts';
import { parseOrganizationBranding } from './organizationBranding.ts';
import { normalizeTicketData } from './ticketRenderData.ts';
export type WalletState = 'ACTIVE' | 'COMPLETED' | 'INACTIVE' | 'EXPIRED';
export type WalletProjection = { state: WalletState; ticket: any; occasion: any; branding?: any };
export type WalletIdentity = { issuer: string; environment: string; organization: number; occasion: number; ticketId: number };
const encoder = new TextEncoder();
const sleep = (ms: number) => new Promise<void>(resolve => setTimeout(resolve, ms));
function b64(bytes: Uint8Array) { return btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replaceAll('=',''); }
export async function walletHash(value: string) {
 return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',encoder.encode(value))), b=>b.toString(16).padStart(2,'0')).join('');
}
export async function walletIds(identity: WalletIdentity) {
 const { issuer, environment, organization, occasion, ticketId }=identity;
 if(!/^\d+$/.test(issuer)||!environment||![organization,occasion,ticketId].every(n=>Number.isSafeInteger(n)&&n>0)) throw new Error('wallet_identity');
 const scope=JSON.stringify([environment,organization,occasion]);
 return {classId:issuer+'.festapp_'+await walletHash(scope),objectId:issuer+'.festapp_'+await walletHash(scope+'/'+ticketId)};
}
const localized = (value: string,language='cs') => ({defaultValue:{language,value}});
/** Wall time with the actual event offset, including DST. */
export function walletDate(value: string, timeZone: string) {
 const date=new Date(value); if(!Number.isFinite(date.getTime()))throw new Error('wallet_metadata');
 const parts=new Intl.DateTimeFormat('sv-SE',{timeZone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23',timeZoneName:'longOffset'}).formatToParts(date);
 const part=(name:string)=>parts.find(p=>p.type===name)?.value;
 const offset=part('timeZoneName')!.replace('GMT','')||'+00:00';
 return `${part('year')}-${part('month')}-${part('day')}T${part('hour')}:${part('minute')}:${part('second')}${offset}`;
}
export function walletDocuments(ids:{classId:string;objectId:string},projection:WalletProjection) {
 const {ticket,occasion,state}=projection;
 if(!occasion?.title||!occasion.start_time||!occasion.end_time||!ticket?.ticket_symbol)throw new Error('wallet_metadata');
 const normalized=normalizeTicketData(ticket,occasion,{});
 const zone=occasion.data?.timezone||'Europe/Prague';
 const appearance=googleWalletAppearance(occasion.ticketFeature,occasion.data);
 const branding=parseOrganizationBranding(projection.branding);
 const overrides=occasion.ticketFeature?.wallet_appearance??{};
 const logo=Object.hasOwn(overrides,'logo')?appearance.logo:walletPublicImage(projection.branding?.WALLET_LOGO_URL)??appearance.logo;
 const image=(uri:string,description:string)=>({sourceUri:{uri},contentDescription:localized(description)});
 const classBody={...(appearance.backgroundColor?{hexBackgroundColor:appearance.backgroundColor}:{}),
 ...(logo?{logo:image(logo,branding.appName)}:{}),
 ...(appearance.heroImage?{heroImage:image(appearance.heroImage,occasion.title)}:{}),id:ids.classId,issuerName:branding.appName,eventName:localized(occasion.title),reviewStatus:'UNDER_REVIEW',
 eventId:ids.classId.split('.')[1].slice(0,64),dateTime:{start:walletDate(occasion.start_time,zone),end:walletDate(occasion.end_time,zone)},
 textModulesData:normalized.occasionPlace?[{id:'place',header:'Místo / Venue',body:normalized.occasionPlace}]:[]};
 const products=ticket.order_product_ticket??[];
 const seat=products.find((p:any)=>p.spot_title);
 const types=[...new Set(products.map((p:any)=>p.product?.title).filter(Boolean))];
 const objectBody:any={id:ids.objectId,classId:ids.classId,state,ticketNumber:ticket.ticket_symbol,
 barcode:{type:'QR_CODE',value:ticket.ticket_symbol},
 validTimeInterval:{start:{date:new Date(occasion.start_time).toISOString()},end:{date:new Date(occasion.end_time).toISOString()}},
 textModulesData:[...(seat?.spot_group_title?[{id:'table',header:'Stůl / Table',body:seat.spot_group_title}]:[]),
 ...(types.length?[{id:'type',header:'Vstup / Admission',body:types.join(', ')}]:[])],
 // Full object updates remove a previously assigned seat for standing admission.
 ...(seat?{seatInfo:{seat:localized(seat.spot_title)}}:{})};
 return {classBody,objectBody};
}
export type GoogleCredentials = {client_email:string;private_key:string;private_key_id?:string};
export async function googleSigner(credentials:GoogleCredentials) {
 const raw=credentials.private_key.replace(/-----[^-]+-----/g,'').replace(/\s/g,'');
 const key=await crypto.subtle.importKey('pkcs8',Uint8Array.from(atob(raw),c=>c.charCodeAt(0)),{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
 return async(payload:Record<string,unknown>)=>{
  const input=b64(encoder.encode(JSON.stringify({alg:'RS256',typ:'JWT',...(credentials.private_key_id?{kid:credentials.private_key_id}:{})})))+'.'+b64(encoder.encode(JSON.stringify(payload)));
  return input+'.'+b64(new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,encoder.encode(input))));
 };
}
export class GoogleWallet {
 private access?:{value:string;expires:number};
 private pending?:Promise<string>;
 constructor(readonly email:string,readonly sign:(payload:Record<string,unknown>)=>Promise<string>,readonly http:typeof fetch=fetch,readonly now=Date.now,readonly delay=sleep){}
 private async accessToken(before:()=>Promise<void>) {
  if(this.access&&this.access.expires>this.now()+60000)return this.access.value;
  if(this.pending)return await this.pending;
  this.pending=(async()=>{
   await before();
   const iat=Math.floor(this.now()/1000);
   const assertion=await this.sign({iss:this.email,scope:'https://www.googleapis.com/auth/wallet_object.issuer',aud:'https://oauth2.googleapis.com/token',iat,exp:iat+3600});
   const res=await this.http('https://oauth2.googleapis.com/token',{method:'POST',signal:AbortSignal.timeout(7000),body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion})});
   if(!res.ok)throw new Error('wallet_oauth');
   const data=await res.json();if(typeof data.access_token!=='string'||!Number.isFinite(data.expires_in))throw new Error('wallet_oauth');
   this.access={value:data.access_token,expires:this.now()+data.expires_in*1000};return data.access_token;
  })();
  try{return await this.pending;}finally{this.pending=undefined;}
 }
 private async request(path:string,method:string,body:unknown,before:()=>Promise<void>) {
  const token=await this.accessToken(before);
  for(let attempt=0;attempt<3;attempt++) {
   await before();
   const res=await this.http('https://walletobjects.googleapis.com/walletobjects/v1/'+path,{method,headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},signal:AbortSignal.timeout(7000),...(body?{body:JSON.stringify(body)}:{})});
   if(res.status===401)this.access=undefined;
   if((res.status===429||res.status>=500)&&attempt<2){await this.delay(Math.min(2000,Math.max(250*2**attempt,Number(res.headers.get('retry-after')||0)*1000)));continue;}
   return res;
  }
  throw new Error('wallet_transport');
 }
 async upsert(kind:'eventTicketClass'|'eventTicketObject',body:any,before:()=>Promise<void>) {
  const path=kind+'/'+encodeURIComponent(body.id);
  let res=await this.request(path,'GET',null,before);
  if(res.status===404){
   res=await this.request(kind,'POST',body,before);
   if(res.status===409){
    res=await this.request(path,'GET',null,before);
    if(res.ok)res=await this.request(path,'PUT',body,before);
   }
  }else if(res.ok)res=await this.request(path,'PUT',body,before);
  if(!res.ok)throw new Error('wallet_google_unavailable');
  return await res.json();
 }
 async synchronize(ids:{classId:string;objectId:string},projection:WalletProjection,before:()=>Promise<void>) {
  // Revoked/deleted tickets retain remote identity without needing historical QR/PII.
  if(projection.state==='INACTIVE') {
   const res=await this.request('eventTicketObject/'+encodeURIComponent(ids.objectId),'PATCH',{state:'INACTIVE'},before);
   if(!res.ok&&res.status!==404)throw new Error('wallet_google_unavailable');return;
  }
  const {classBody,objectBody}=walletDocuments(ids,projection);
  const cls=await this.upsert('eventTicketClass',classBody,before);
  if(String(cls.reviewStatus).toUpperCase()!=='APPROVED')throw new Error('wallet_class_pending');
  await this.upsert('eventTicketObject',objectBody,before);
 }
 async saveUrl(objectId:string,origin:string) {
  const iat=Math.floor(this.now()/1000);
  const jwt=await this.sign({iss:this.email,aud:'google',typ:'savetowallet',iat,exp:iat+300,origins:[origin],payload:{eventTicketObjects:[{id:objectId}]}});
  const url='https://pay.google.com/gp/v/save/'+jwt;
  if(url.length>1800)throw new Error('wallet_link_length');return url;
 }
}
let singleton:Promise<GoogleWallet>|undefined;
export function configuredGoogleWallet() {
 return singleton??=(async()=>{
  const credentials=JSON.parse(Deno.env.get('GOOGLE_WALLET_SERVICE_ACCOUNT')||'null') as GoogleCredentials;
  if(!credentials?.client_email||!credentials.private_key)throw new Error('wallet_credentials');
  return new GoogleWallet(credentials.client_email,await googleSigner(credentials));
 })().catch(error=>{singleton=undefined;throw error;});
}
