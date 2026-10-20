const admin=async()=> (await import('./supabaseUtil.ts')).supabaseAdmin;
import {TicketFontResolver,TicketFontError,fontCatalog,type FontAsset,type FontStore} from './ticketFonts.ts';
import {parseLayout,layoutFontIds} from './ticketLayout.ts';
import {createTicketFontR2Store} from './ticketFontR2.ts';
export async function ticketFontAsset(id:string):Promise<FontAsset|null>{
  const bundled=fontCatalog.find(a=>a.id===id);if(bundled)return bundled;
  const {data,error}=await (await admin()).from('ticket_font_assets').select('metadata').eq('id',id).maybeSingle();
  if(error)throw new TicketFontError('font_registry');
  const asset=data?.metadata;
  // Historical Google identities remain resolvable after a catalog refresh.
  if(!asset)return null;
  if(asset.id!==id||asset.source!=='google'||id!==`gf:${asset.sha256}`||! /^[a-f0-9]{64}$/.test(asset.sha256)||asset.extension!=='ttf')throw new TicketFontError('font_registry');
  return asset;
}
export async function parseRegisteredTicketLayout(value:unknown){
  const ids=layoutFontIds(value);const layout=parseLayout(value,ids);
  for(const id of ids)if(!await ticketFontAsset(id))throw new TicketFontError('font_unknown');
  return layout;
}
export const ticketFontStore:FontStore=createTicketFontR2Store(()=>Deno.env.get('TICKET_FONT_SERVICE_SECRET'),fetch,Deno.env.get('TICKET_FONT_SERVICE_URL'));
const resolver=new TicketFontResolver({store:ticketFontStore,fetch,
  bundled:async a=>{if(!a.file)return null;try{return await Deno.readFile(new URL(`./ticket-assets/${a.file}`,import.meta.url));}catch(e){if(e instanceof Deno.errors.NotFound)return null;throw e;}},
  lookup:ticketFontAsset,
  event:event=>console.info('ticket-font',JSON.stringify(event)),
});
export const resolveTicketFont=(id:string)=>resolver.resolve(id);
