const admin=async()=> (await import('./supabaseUtil.ts')).supabaseAdmin;
import {TicketFontResolver,TicketFontError,fontCatalog,type FontAsset,type FontStore} from './ticketFonts.ts';
import {parseLayout,layoutFontIds} from './ticketLayout.ts';
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
// Self-hosted Storage reports a missing object as HTTP 400 with a 404 JSON
// code. Some SDK builds preserve that response as StorageUnknownError.
export async function isMissingTicketFontObject(error:unknown):Promise<boolean>{
  if(!error||typeof error!=='object')return false;
  const value=error as {statusCode?:unknown;originalError?:Response};
  if(String(value.statusCode)==='404')return true;
  const response=value.originalError;
  if(!response||![400,404].includes(response.status)||typeof response.clone!=='function')return false;
  try {
    const body=await response.clone().json();
    return String(body.statusCode)==='404'&&body.error==='not_found'&&body.message==='Object not found';
  } catch {return false;}
}
export const ticketFontStore:FontStore={
  async read(key){const {data,error}=await (await admin()).storage.from('ticket-fonts').download(key);if(error){if(await isMissingTicketFontObject(error))return null;throw new TicketFontError('font_storage_read');}if(data!.size>8388608)throw new TicketFontError('font_size');return new Uint8Array(await data!.arrayBuffer());},
  async create(key,bytes){const {error}=await (await admin()).storage.from('ticket-fonts').upload(key,bytes,{upsert:false,contentType:'application/octet-stream'});if(error){if(['409','400'].includes(String((error as any).statusCode))&& /duplicate|already exists/i.test(error.message))return false;throw new TicketFontError('font_storage_write');}return true;}
};
const resolver=new TicketFontResolver({store:ticketFontStore,fetch,
  bundled:async a=>{if(!a.file)return null;try{return await Deno.readFile(new URL(`./ticket-assets/${a.file}`,import.meta.url));}catch(e){if(e instanceof Deno.errors.NotFound)return null;throw e;}},
  lookup:ticketFontAsset,
  event:event=>console.info('ticket-font',JSON.stringify(event)),
});
export const resolveTicketFont=(id:string)=>resolver.resolve(id);
