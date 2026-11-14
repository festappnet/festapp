/** Signed Apple event tickets. SQL remains the admission and capability authority. */
import { Buffer } from 'node:buffer';
import forge from 'npm:node-forge@1.4.3';
import { PKPass } from 'npm:passkit-generator@3.7.0';
import {parseOrganizationBranding} from './organizationBranding.ts';
import { googleWalletAppearance, walletPublicImage } from './googleWalletAppearance.ts';
import {walletHash} from './wallet/identity.ts';
import type {WalletProjection} from './wallet/contracts.ts';
import { normalizeTicketData } from './ticketRenderData.ts';

export type AppleWalletCredentials = {
 passTypeIdentifier: string; teamIdentifier: string;
 signerCert: string; signerKey: string; wwdr: string; signerKeyPassphrase?: string;
};
export const APPLE_PASS_MIME = 'application/vnd.apple.pkpass';

function applePrivateKey(credentials:AppleWalletCredentials) {
 const key=credentials.signerKeyPassphrase?forge.pki.decryptRsaPrivateKey(credentials.signerKey,credentials.signerKeyPassphrase):forge.pki.privateKeyFromPem(credentials.signerKey);
 if(!key)throw new Error('wallet_apple_credentials');return key;
}
export function validateAppleCredentials(credentials:AppleWalletCredentials,now=Date.now()) {
 if(!credentials||!/^pass\.[A-Za-z0-9.-]+$/.test(credentials.passTypeIdentifier)||!/^[A-Z0-9]{10}$/.test(credentials.teamIdentifier))throw new Error('wallet_apple_credentials');
 try {
  // Use the same maintained crypto implementation as PKPass. The production
  // Edge Runtime does not implement Node X509Certificate.verify/checkPrivateKey.
  const cert=forge.pki.certificateFromPem(credentials.signerCert),wwdr=forge.pki.certificateFromPem(credentials.wwdr);
  const key=applePrivateKey(credentials);
  if(cert.subject.getField({type:'0.9.2342.19200300.100.1.1'})?.value!==credentials.passTypeIdentifier||cert.subject.getField('OU')?.value!==credentials.teamIdentifier||
   [cert,wwdr].some(c=>c.validity.notBefore.getTime()>now||c.validity.notAfter.getTime()<=now)||!wwdr.verify(cert)||
   cert.publicKey.n.compareTo(key.n)!==0||cert.publicKey.e.compareTo(key.e)!==0)throw new Error();
 }catch{throw new Error('wallet_apple_credentials');}
}

export async function appleWalletSerial(identity: {environment:string;organization:number;occasion:number;ticketId:number}) {
 const {environment,organization,occasion,ticketId}=identity;
 if (!/^[A-Za-z0-9_-]{1,40}$/.test(environment) || ![organization,occasion,ticketId].every(n=>Number.isSafeInteger(n)&&n>0)) throw new Error('wallet_identity');
 return 'festapp_'+await walletHash(JSON.stringify([environment,organization,occasion,ticketId]));
}

export function appleWalletDocument(serialNumber:string, projection:WalletProjection, credentials:AppleWalletCredentials) {
 const {ticket,occasion,state}=projection;
 if (!['ACTIVE','COMPLETED','INACTIVE','EXPIRED'].includes(state) || !ticket?.ticket_symbol || !occasion?.title ||
  !Number.isFinite(Date.parse(occasion.start_time)) || !Number.isFinite(Date.parse(occasion.end_time))) throw new Error('wallet_metadata');
 const branding=parseOrganizationBranding(projection.branding);
 const normalized=normalizeTicketData(ticket,occasion,{});
 const appearance=googleWalletAppearance(occasion.ticketFeature,occasion.data);
 const products=ticket.order_product_ticket??[];
 const seat=products.find((p:any)=>p.spot_title);
 const types=[...new Set(products.map((p:any)=>p.product?.title).filter(Boolean))].join(', ');
 const zone=occasion.data?.timezone||'Europe/Prague';
 const date=new Intl.DateTimeFormat('cs-CZ',{timeZone:zone,dateStyle:'medium',timeStyle:'short'}).format(new Date(occasion.start_time));
 const color=appearance.backgroundColor??'#ffffff';
 const rgb=[1,3,5].map(i=>parseInt(color.slice(i,i+2),16));
 const foreground=rgb.reduce((sum,v,i)=>sum+v*[0.2126,0.7152,0.0722][i],0)>145?'rgb(0, 0, 0)':'rgb(255, 255, 255)';
 const field=(key:string,label:string,value:string)=>({key,label,value});
 return {
  formatVersion:1,passTypeIdentifier:credentials.passTypeIdentifier,teamIdentifier:credentials.teamIdentifier,serialNumber,
  organizationName:branding.appName,description:occasion.title,logoText:branding.appName,
  backgroundColor:`rgb(${rgb.join(', ')})`,foregroundColor:foreground,labelColor:foreground,
  relevantDate:new Date(occasion.start_time).toISOString(),expirationDate:new Date(occasion.end_time).toISOString(),
  voided:state!=='ACTIVE',
  barcodes:[{format:'PKBarcodeFormatQR',message:ticket.ticket_symbol,messageEncoding:'utf-8',altText:ticket.ticket_symbol}],
  eventTicket:{
   primaryFields:[field('event','Akce / Event',occasion.title)],
   secondaryFields:[field('date','Datum / Date',date),...(normalized.occasionPlace?[field('venue','Místo / Venue',normalized.occasionPlace)]:[])],
   auxiliaryFields:[...(seat?.spot_group_title?[field('table','Stůl / Table',seat.spot_group_title)]:[]),...(seat?.spot_title?[field('seat','Místo / Seat',seat.spot_title)]:[]),...(types?[field('admission','Vstup / Admission',types)]:[])],
   backFields:[field('number','Vstupenka / Ticket',ticket.ticket_symbol),...(state==='COMPLETED'?[field('status','Stav / Status','Vstupenka již byla použita. / This ticket has already been used.')]:[])],
  },
 };
}

export class AppleWallet {
 private pushClient?:Deno.HttpClient;
 constructor(readonly credentials:AppleWalletCredentials,readonly icons:Record<string,Uint8Array>,readonly http:typeof fetch=fetch,readonly webServiceURL?:string) {}
 async issue(identity:{environment:string;organization:number;occasion:number;ticketId:number},projection:WalletProjection,options?:{authenticationToken:string}) {
  validateAppleCredentials(this.credentials);
  const document=appleWalletDocument(await appleWalletSerial(identity),projection,this.credentials);
  if(options){
   if(!this.webServiceURL||!/^https:\/\/[^?#]+\/functions\/v1\/apple-wallet$/.test(this.webServiceURL)||!/^([a-f0-9]{64})$/.test(options.authenticationToken))throw new Error('wallet_apple_web_service');
   Object.assign(document,{webServiceURL:this.webServiceURL,authenticationToken:options.authenticationToken});
  }
  const files:Record<string,Buffer>={'pass.json':Buffer.from(JSON.stringify(document))};
  for(const [name,bytes] of Object.entries(this.icons)) files[name]=Buffer.from(bytes);
  // Reuse the existing canonical public image policy; redirects and unbounded downloads are forbidden.
  const appearance=googleWalletAppearance(projection.occasion.ticketFeature,projection.occasion.data);
  const overrides=projection.occasion.ticketFeature?.wallet_appearance??{};
  const logo=Object.hasOwn(overrides,'logo')?appearance.logo:walletPublicImage(projection.branding?.WALLET_LOGO_URL)??appearance.logo;
  for(const [name,url] of [['logo.png',logo],['strip.png',appearance.heroImage]] as const) {
   if(!url)continue;
   try {
    const res=await this.http(url,{redirect:'error',signal:AbortSignal.timeout(5000)});
    if(!res.ok || !res.headers.get('content-type')?.startsWith('image/png'))continue;
    const reader=res.body?.getReader();if(!reader)continue;
    const chunks:Uint8Array[]=[];let size=0;
    try {
     while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>2*1024*1024){await reader.cancel();throw new Error('wallet_image_size');}chunks.push(value);}
    }finally{reader.releaseLock();}
    const bytes=Buffer.concat(chunks.map(chunk=>Buffer.from(chunk)));
    if(bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])))files[name]=bytes;
   }catch{/* Optional artwork must not prevent the original QR from being issued. */}
  }
  const {signerCert,signerKey,wwdr,signerKeyPassphrase}=this.credentials;
  return new Uint8Array(new PKPass(files,{signerCert,signerKey,wwdr,...(signerKeyPassphrase?{signerKeyPassphrase}:{})}).getAsBuffer());
 }
 async push(pushToken:string):Promise<'sent'|'invalid'> {
  validateAppleCredentials(this.credentials);
  if(!/^[a-fA-F0-9]{32,512}$/.test(pushToken))throw new Error('wallet_apple_push_token');
  // Wallet APNs uses the same Pass Type ID certificate, with HTTP/2 mutual TLS.
  this.pushClient??=Deno.createHttpClient({http1:false,http2:true,cert:this.credentials.signerCert+'\n'+this.credentials.wwdr,
   key:forge.pki.privateKeyToPem(applePrivateKey(this.credentials))});
  const res=await this.http('https://api.push.apple.com/3/device/'+pushToken,{method:'POST',client:this.pushClient,signal:AbortSignal.timeout(7000),
   headers:{'apns-topic':this.credentials.passTypeIdentifier,'apns-priority':'5','apns-push-type':'background','Content-Type':'application/json'},body:'{}'});
  if(res.ok){await res.arrayBuffer();return 'sent';}
  const data=await res.json().catch(()=>null);
  if(res.status===410||(res.status===400&&['BadDeviceToken','DeviceTokenNotForTopic'].includes(data?.reason)))return 'invalid';
  throw new Error('wallet_apple_push_unavailable');
 }
 close(){this.pushClient?.close();this.pushClient=undefined;}
}
let singleton:Promise<AppleWallet>|undefined;
export function configuredAppleWallet() {
 return singleton??=(async()=>{
  const credentials=JSON.parse(Deno.env.get('APPLE_WALLET_CREDENTIALS')||'null') as AppleWalletCredentials;
  validateAppleCredentials(credentials);
  const icons:Record<string,Uint8Array>={};
  for(const name of ['icon.png','icon@2x.png','icon@3x.png'])icons[name]=await Deno.readFile(new URL('./ticket-assets/apple-wallet/'+name,import.meta.url));
  const webServiceURL=Deno.env.get('APPLE_WALLET_WEB_SERVICE_URL');
  if(!webServiceURL||!/^https:\/\/[^?#]+\/functions\/v1\/apple-wallet$/.test(webServiceURL))throw new Error('wallet_apple_web_service');
  return new AppleWallet(credentials,icons,fetch,webServiceURL);
 })().catch(error=>{singleton=undefined;throw error;});
}
