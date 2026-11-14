import { escapeTicketText } from './ticketDelivery.ts';
import { openEmail, sealEmail } from './emailPayload.ts';
import { walletHash } from './wallet/identity.ts';
import {walletEmailProviders} from './wallet/emailProviders.ts';
import type { WalletRpc } from './wallet/contracts.ts';
export function ticketWalletEnabled(feature:any):boolean {
 if(!Object.hasOwn(feature??{},'wallet_enabled'))return true;
 if(typeof feature.wallet_enabled!=='boolean')throw new Error('invalid_ticket_wallet_preference');
 return feature.wallet_enabled;
}
export const walletEmailCopy:Record<string,{title:string;help:string;ticket:string;fallback:string}>={
 cs:{title:'Vstupenky v telefonu',help:'Uložte si vstupenky do peněženky v telefonu. U vstupu pak stačí ukázat jejich QR kód.',ticket:'Vstupenka {n} z {count}',fallback:'Uložit vstupenku do telefonu'},
 sk:{title:'Vstupenky v telefóne',help:'Uložte si vstupenky do peňaženky v telefóne. Pri vstupe potom stačí ukázať ich QR kód.',ticket:'Vstupenka {n} z {count}',fallback:'Uložiť vstupenku do telefónu'},
 en:{title:'Tickets on your phone',help:'Save your tickets to your phone’s wallet. Show their QR code at the entrance.',ticket:'Ticket {n} of {count}',fallback:'Save ticket to your phone'},
 de:{title:'Tickets auf Ihrem Smartphone',help:'Speichern Sie Ihre Tickets in der Wallet auf Ihrem Smartphone. Zeigen Sie am Eingang den QR-Code vor.',ticket:'Ticket {n} von {count}',fallback:'Ticket auf dem Smartphone speichern'},
 pl:{title:'Bilety w telefonie',help:'Zapisz bilety w portfelu w telefonie. Przy wejściu wystarczy pokazać ich kod QR.',ticket:'Bilet {n} z {count}',fallback:'Zapisz bilet w telefonie'},
 uk:{title:'Квитки в телефоні',help:'Збережіть квитки в гаманці на телефоні. На вході достатньо показати їхній QR-код.',ticket:'Квиток {n} із {count}',fallback:'Зберегти квиток у телефоні'},
};
const walletEmailSingular:Record<string,{title:string;help:string}>={
 cs:{title:'Vstupenka v telefonu',help:'Uložte si vstupenku do peněženky v telefonu. U vstupu pak stačí ukázat její QR kód.'},
 sk:{title:'Vstupenka v telefóne',help:'Uložte si vstupenku do peňaženky v telefóne. Pri vstupe potom stačí ukázať jej QR kód.'},
 en:{title:'Ticket on your phone',help:'Save your ticket to your phone’s wallet. Show its QR code at the entrance.'},
 de:{title:'Ticket auf Ihrem Smartphone',help:'Speichern Sie Ihr Ticket in der Wallet auf Ihrem Smartphone. Zeigen Sie am Eingang den QR-Code vor.'},
 pl:{title:'Bilet w telefonie',help:'Zapisz bilet w portfelu w telefonie. Przy wejściu wystarczy pokazać jego kod QR.'},
 uk:{title:'Квиток у телефоні',help:'Збережіть квиток у гаманці на телефоні. На вході достатньо показати його QR-код.'},
};
export function walletTicketLabel(index:number,count:number,lang:string) {
 if(count===1)return ({cs:'Vstupenka',sk:'Vstupenka',en:'Ticket',de:'Ticket',pl:'Bilet',uk:'Квиток'} as Record<string,string>)[lang]??'Ticket';
 return (walletEmailCopy[lang]??walletEmailCopy.en).ticket.replace('{n}',String(index)).replace('{count}',String(count));
}
export function googleWalletBadgeUrl(lang:string) {
 return `https://img.festapp.net/assets/google-wallet/v1/${Object.hasOwn(walletEmailProviders.google.labels,lang)?lang:'en'}.png`;
}
export function walletEmailSection(rows:string[],lang:string,count=2) {
 if(!rows.length)return '';
 const copy=count===1?(walletEmailSingular[lang]??walletEmailSingular.en):(walletEmailCopy[lang]??walletEmailCopy.en);
 return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;table-layout:fixed;margin-top:24px;border-top:1px solid #e2e8f0"><tr><td style="padding-top:20px"><h2 style="margin:0 0 8px;font-size:20px;line-height:1.35;color:#19243b">${escapeTicketText(copy.title)}</h2><p style="margin:0 0 8px;font-size:14px;line-height:1.6;color:#334155">${escapeTicketText(copy.help)}</p>${rows.join('')}</td></tr></table>`;
}
export type WalletEmailAction={provider:string;url?:string;badge?:string};
/** One identity heading and one grouped action area per ticket, in live and inert previews. */
export function walletEmailTicket(label:string,actions:WalletEmailAction[],lang:string) {
 if(!actions.length)return '';
 const buttons=actions.map(({provider,url,badge})=>{
  const descriptor=walletEmailProviders[provider];if(!descriptor)throw new Error('wallet_connector_unavailable');
  if(url){
   const target=new URL(url);target.searchParams.delete('lang');target.searchParams.set('provider',provider);target.searchParams.set('lang',Object.hasOwn(walletEmailCopy,lang)?lang:'en');url=target.href;
  }
  const text=descriptor.labels[lang]??descriptor.labels.en;
  const artwork=descriptor.artwork(badge,lang);
  const width=artwork?.width??204;
  const content=artwork
   ? `<img src="${escapeTicketText(artwork.url)}" width="${Math.round(width)}" height="48" alt="${escapeTicketText(text)}" style="display:block;border:0;width:${width}px;height:auto;max-width:100%;font-size:14px;line-height:20px;font-weight:600;text-decoration:underline;color:#19243b" />`
   : `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:separate;border-spacing:0;border:1px solid #202124;border-radius:6px;background:#202124"><tr><td height="46" align="center" style="height:46px;padding:0 8px;color:#ffffff;font:600 14px/20px Arial,sans-serif;text-decoration:none">${escapeTicketText(text)}</td></tr></table>`;
  const open=url?`a href="${escapeTicketText(url)}" aria-label="${escapeTicketText(label+' - '+text)}"`:'span';const close=url?'a':'span';
  return `<span style="display:inline-block;vertical-align:middle;width:${width+16}px;max-width:100%;text-align:left"><${open} style="display:block;box-sizing:border-box;max-width:100%;padding:8px;color:#19243b;font:14px/20px Arial,sans-serif;text-decoration:${artwork?'underline':'none'}">${content}</${close}></span>`;
 }).join('');
 return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;table-layout:fixed;border-bottom:1px solid #e2e8f0"><tr><td style="padding:14px 0 12px"><p style="margin:0 0 4px;font:600 15px/22px Arial,sans-serif;color:#19243b;overflow-wrap:anywhere">${escapeTicketText(label)}</p><div style="font-size:0;line-height:0;text-align:left">${buttons}</div></td></tr></table>`;
}
const collectionCopy:Record<string,{all:string;individual:string}>={
 cs:{all:'Všechny vstupenky ({count})',individual:'Uložit jen tuto vstupenku'},
 sk:{all:'Všetky vstupenky ({count})',individual:'Uložiť len túto vstupenku'},
 en:{all:'All tickets ({count})',individual:'Save this ticket only'},
 de:{all:'Alle Tickets ({count})',individual:'Nur dieses Ticket speichern'},
 pl:{all:'Wszystkie bilety ({count})',individual:'Zapisz tylko ten bilet'},
 uk:{all:'Усі квитки ({count})',individual:'Зберегти лише цей квиток'},
};
/** Secondary individual links keep the email compact and can be forwarded independently. */
export function walletEmailIndividual(label:string,url:string|undefined,lang:string){
 const text=(collectionCopy[lang]??collectionCopy.en).individual;
 return `<p style="margin:12px 0;font:14px/22px Arial,sans-serif;color:#19243b">${escapeTicketText(label)}<br>${url?`<a href="${escapeTicketText(url)}"`:`<span`} style="color:#2259ad;text-decoration:underline">${escapeTicketText(text)}</${url?'a':'span'}></p>`;
}
export function walletCollectionLabel(count:number,lang:string){return (collectionCopy[lang]??collectionCopy.en).all.replace('{count}',String(count));}
function walletActions(context:any,url:string,lang:string,ready?:boolean|{google:boolean;apple:boolean}):WalletEmailAction[]{
 const actions:WalletEmailAction[]=[];
 for(const [provider,descriptor] of Object.entries(walletEmailProviders)){
  const available=typeof ready==='object'?ready[provider as keyof typeof ready]:context.providers?.[provider];
  if(available!==true||context.providers?.[provider]!==true)continue;
  const badge=descriptor.badge(context.badgeUrls,lang);
  if(!badge&&!descriptor.labelFallback)continue;
  actions.push({url,badge,provider});
 }
 return actions;
}
function walletEmailUrl(context:any,token:string,lang:string){
 const base=new URL(context.webOrigin);
 if(base.protocol!=='https:'||base.username||base.password||base.search||base.hash||base.pathname!=='/')throw new Error('wallet_origin');
 const url=new URL('/wallet',base);url.hash=token;if(context.ticketIds)url.searchParams.set('scope','collection');url.searchParams.set('lang',Object.hasOwn(walletEmailCopy,lang)?lang:'en');return url.href;
}
function walletToken(){return Array.from(crypto.getRandomValues(new Uint8Array(32)),b=>b.toString(16).padStart(2,'0')).join('');}
export async function prepareWalletEmail(row:any,tickets:any[],feature:any,rpc:WalletRpc,ready?:boolean|{google:boolean;apple:boolean}) {
 if(!feature?.is_enabled||!ticketWalletEnabled(feature)||ready===false)return '';
 const lang=row.data?.lang??'cs';
 const prepared:{ticketId:number;context:any;url:string;description:string;actions:WalletEmailAction[]}[]=[];
 for(const [index,ticket] of tickets.entries()) {
  let context=await rpc('prepare_ticket_wallet',{p_message:row.message_id,p_ticket:ticket.id});
  if(!context)continue;
  if(!context.source) {
   const token=walletToken();
   const sealed=await sealEmail({purpose:'ticket_wallet',token,ticketId:ticket.id,organization:context.organization,occasion:context.occasion});
   context=await rpc('prepare_ticket_wallet',{p_message:row.message_id,p_ticket:ticket.id,p_hash:await walletHash(token),p_sealed:sealed});
  }
  if(!context?.source)continue;
  const source=await openEmail<any>(context.source.sealed);
  if(source.purpose!=='ticket_wallet'||source.ticketId!==ticket.id||source.organization!==context.organization||source.occasion!==context.occasion||await walletHash(source.token)!==context.source.tokenHash)throw new Error('wallet_source');
  const url=walletEmailUrl(context,source.token,lang);
  const spot=ticket.order_product_ticket?.find((p:any)=>p.spot_title);
  const description=[walletTicketLabel(index+1,tickets.length,lang),spot?.spot_title,spot?.spot_group_title].filter(Boolean).join(' - ');
  const actions=walletActions(context,url,lang,ready);
  if(actions.length)prepared.push({ticketId:ticket.id,context,url,description,actions});
 }
 // A separate, frozen capability grants this delivered set. An individual link never expands to an order.
 if(prepared.length>=2&&prepared.length===tickets.length&&prepared.every(item=>item.context.collectionEnabled===true)){
  const ids=prepared.map(item=>item.ticketId).sort((a,b)=>a-b);
  const params={p_message:row.message_id,p_tickets:ids};
  let context=await rpc('prepare_ticket_wallet_collection',params);
  if(context&&!context.source){
   const token=walletToken();
   const sealed=await sealEmail({purpose:'ticket_wallet_collection',token,ticketIds:ids,organization:context.organization,occasion:context.occasion,orderId:context.orderId,fingerprint:context.fingerprint});
   context=await rpc('prepare_ticket_wallet_collection',{...params,p_hash:await walletHash(token),p_sealed:sealed});
  }
  if(context?.source){
   const source=await openEmail<any>(context.source.sealed);
   if(source.purpose!=='ticket_wallet_collection'||source.organization!==context.organization||source.occasion!==context.occasion||source.orderId!==context.orderId||source.fingerprint!==context.fingerprint||JSON.stringify(source.ticketIds)!==JSON.stringify(ids)||JSON.stringify(context.ticketIds)!==JSON.stringify(ids)||await walletHash(source.token)!==context.source.tokenHash)throw new Error('wallet_source');
   const actions=walletActions(context,walletEmailUrl(context,source.token,lang),lang,ready);
   if(actions.length)return walletEmailSection([walletEmailTicket(walletCollectionLabel(ids.length,lang),actions,lang),...prepared.map(item=>walletEmailIndividual(item.description,item.url,lang))],lang);
  }
 }
 return walletEmailSection(prepared.map(item=>walletEmailTicket(item.description,item.actions,lang)),lang,prepared.length);
}
