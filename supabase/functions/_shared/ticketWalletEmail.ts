import { escapeTicketText } from './ticketDelivery.ts';
import { openEmail, sealEmail } from './emailPayload.ts';
import { configuredGoogleWallet, walletHash } from './googleWallet.ts';
import type { WalletRpc } from './ticketWallet.ts';
export function ticketWalletEnabled(feature:any):boolean {
 if(!Object.hasOwn(feature??{},'wallet_enabled'))return true;
 if(typeof feature.wallet_enabled!=='boolean')throw new Error('invalid_ticket_wallet_preference');
 return feature.wallet_enabled;
}
const labels:Record<string,string>={cs:'Přidat do Peněženky Google',sk:'Pridať do Peňaženky Google',en:'Add to Google Wallet',de:'Zu Google Wallet hinzufügen',pl:'Dodaj do Portfela Google',uk:'Додати в Google Гаманець'};
export function walletEmailLink(url:string,badge:string|undefined,label:string,lang:string) {
 const text=labels[lang]??labels.en;
 const image=badge?`<img src="${escapeTicketText(badge)}" height="48" alt="${escapeTicketText(text)}" style="height:48px;width:auto;margin:8px 0" />`:'';
 return `<div style="margin:24px 0"><p>${escapeTicketText(label)}</p><a href="${escapeTicketText(url)}">${image}<span style="display:block">${escapeTicketText(text)}</span></a></div>`;
}
export async function prepareWalletEmail(row:any,tickets:any[],feature:any,rpc:WalletRpc,ready?:boolean) {
 if(!feature?.is_enabled||!ticketWalletEnabled(feature)||ready===false)return '';
 if(ready===undefined){try{await configuredGoogleWallet();}catch{return '';}}
 let html='';
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
  const description=[`${index+1}/${tickets.length}`,ticket.ticket_symbol,spot?.spot_title,spot?.spot_group_title].filter(Boolean).join(' - ');
  const badge=context.badgeUrls?.[lang]??context.badgeUrls?.en;
  // Published badges must be immutable public canonical asset URLs configured by operations.
  if(!badge||!/^https:\/\/img\.festapp\.net\/assets\/google-wallet\/v1\/(cs|sk|en|de|pl|uk)\.png$/.test(badge))continue;
  html+=walletEmailLink(url.href,badge,description,lang);
 }
 return html;
}
