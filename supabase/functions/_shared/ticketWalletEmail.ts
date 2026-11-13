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
export function walletTicketLabel(index:number,count:number,lang:string) {
 return (walletEmailCopy[lang]??walletEmailCopy.en).ticket.replace('{n}',String(index)).replace('{count}',String(count));
}
export function googleWalletBadgeUrl(lang:string) {
 return `https://img.festapp.net/assets/google-wallet/v1/${Object.hasOwn(walletEmailProviders.google.labels,lang)?lang:'en'}.png`;
}
export function walletEmailSection(rows:string[],lang:string) {
 if(!rows.length)return '';
 const copy=walletEmailCopy[lang]??walletEmailCopy.en;
 return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;table-layout:fixed;margin-top:24px;border-top:1px solid #e2e8f0"><tr><td style="padding-top:24px"><h2 style="margin:0 0 8px;font-size:20px;line-height:1.35;color:#19243b">${escapeTicketText(copy.title)}</h2><p style="margin:0 0 20px;font-size:14px;line-height:1.6;color:#334155">${escapeTicketText(copy.help)}</p>${rows.join('')}</td></tr></table>`;
}
/** One ticket's action area; previews omit href rather than inventing a pass. */
export function walletEmailLink(url:string|undefined,badge:string|undefined,label:string,lang:string,provider='google') {
 const descriptor=walletEmailProviders[provider];if(!descriptor)throw new Error('wallet_connector_unavailable');
 if(url){
  const target=new URL(url);target.searchParams.set('provider',provider);target.searchParams.set('lang',Object.hasOwn(walletEmailCopy,lang)?lang:'en');url=target.href;
 }
 const translated=descriptor.labels;
 const text=translated[lang]??translated.en;
 const badgeWidth=descriptor.width(lang);
 const copy=walletEmailCopy[lang]??walletEmailCopy.en;
 const image=badge?`<img src="${escapeTicketText(badge)}" height="48" alt="${escapeTicketText(text)}" style="display:block;border:0;width:${badgeWidth}px;height:auto;max-width:100%" />`:escapeTicketText(text);
 const open=url?`a href="${escapeTicketText(url)}"`:'span';
 const close=url?'a':'span';
 // A contained action area leaves space for another supported Wallet without overflow.
 return `<div style="margin:0 0 20px"><p style="margin:0 0 4px;font-size:14px;line-height:1.5;font-weight:600;color:#19243b">${escapeTicketText(label)}</p><div style="text-align:center"><${open} style="display:block;box-sizing:border-box;width:100%;max-width:${badgeWidth+16}px;margin:0 auto;padding:8px;color:#334155;text-decoration:none;text-align:center">${image}<span style="display:block;margin-top:8px;font-size:12px;line-height:1.5;text-decoration:underline">${escapeTicketText(descriptor.labelFallback?text:copy.fallback)}</span></${close}></div></div>`;
}
export async function prepareWalletEmail(row:any,tickets:any[],feature:any,rpc:WalletRpc,ready?:boolean|{google:boolean;apple:boolean}) {
 if(!feature?.is_enabled||!ticketWalletEnabled(feature)||ready===false)return '';
 // SQL checks publishing readiness. Email only creates an encrypted capability;
 // the isolated Wallet workers own signing credentials and Google API calls.
 const rows:string[]=[];
 for(const [index,ticket] of tickets.entries()) {
  let context=await rpc('prepare_ticket_wallet',{p_message:row.message_id,p_ticket:ticket.id});
  if(!context)continue;
  if(!context.source) {
   const token=Array.from(crypto.getRandomValues(new Uint8Array(32)),b=>b.toString(16).padStart(2,'0')).join('');
   const sealed=await sealEmail({purpose:'ticket_wallet',token,ticketId:ticket.id,organization:context.organization,occasion:context.occasion});
   context=await rpc('prepare_ticket_wallet',{p_message:row.message_id,p_ticket:ticket.id,p_hash:await walletHash(token),p_sealed:sealed});
  }
  if(!context?.source)continue;
  const source=await openEmail<any>(context.source.sealed);
  if(source.purpose!=='ticket_wallet'||source.ticketId!==ticket.id||source.organization!==context.organization||source.occasion!==context.occasion||await walletHash(source.token)!==context.source.tokenHash)throw new Error('wallet_source');
  const base=new URL(context.webOrigin);
  if(base.protocol!=='https:'||base.username||base.password||base.search||base.hash||base.pathname!=='/')throw new Error('wallet_origin');
  const url=new URL('/wallet',base);url.hash=source.token;
  const lang=row.data?.lang??'cs';
  const spot=ticket.order_product_ticket?.find((p:any)=>p.spot_title);
  const description=[walletTicketLabel(index+1,tickets.length,lang),spot?.spot_title,spot?.spot_group_title].filter(Boolean).join(' - ');
  // Only explicitly installed and ready providers can offer this shared capability.
  for(const [provider,descriptor] of Object.entries(walletEmailProviders)){
   const available=typeof ready==='object'?ready[provider as keyof typeof ready]:context.providers?.[provider];
   if(available!==true||context.providers?.[provider]!==true)continue;
   const badge=descriptor.badge(context.badgeUrls,lang);
   if(!badge&&!descriptor.labelFallback)continue;
   rows.push(walletEmailLink(url.href,badge,description,lang,provider));
  }
 }
 return walletEmailSection(rows,row.data?.lang??'cs');
}
