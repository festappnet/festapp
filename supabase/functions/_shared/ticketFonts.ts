import * as fontkit from 'npm:fontkit';
import { PDFDocument } from 'npm:pdf-lib';
import catalog from './ticket-assets/font-catalog.json' with {type:'json'};
import type {FontMetrics} from './ticketText.ts';
export interface FontAsset {id:string; family:string; weight:number; style:string; sha256:string; byteLength:number; source:string; extension:string; file?:string}
export interface TicketFont {id:string; bytes:Uint8Array; metrics:FontMetrics; family:string; weight:number}
export class TicketFontError extends Error {constructor(public code:string){super(code);}}
export const fontCatalog = catalog.fonts as FontAsset[];
export const futuraId=fontCatalog.find(f=>f.file==='font.ttf')!.id;
export const legacyWideId=fontCatalog.find(f=>f.file==='roboto-slab.ttf')!.id;
export const legacyNamedId=fontCatalog.find(f=>f.file==='roboto.ttf')!.id;
export const legacyRussoId=fontCatalog.find(f=>f.file==='russo-one.ttf')!.id;
export const legacyFontIds:Record<string,string>={futura:futuraId,robotoSlab:legacyWideId,roboto:legacyNamedId,russoOne:legacyRussoId};
const aliases:Record<string,string>={'https://fonts.cdnfonts.com/s/15876/RussoOne-Regular.woff':legacyRussoId,'https://fonts.cdnfonts.com/s/12165/Roboto-Regular.woff':legacyNamedId};
export function legacyNamedFontId(url:unknown):string {
  if(url==null||url==='')return legacyNamedId;
  if(typeof url!=='string')throw new TicketFontError('legacy_font_alias_unknown');
  if(!url.trim())return legacyNamedId;
  const id=aliases[url.trim()];if(!id)throw new TicketFontError('legacy_font_alias_unknown');return id;
}
export function knownFontId(id:unknown):boolean {return typeof id==='string'&&fontCatalog.some(f=>f.id===id);}
export async function digest(bytes:Uint8Array):Promise<string>{return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new Uint8Array(bytes).buffer))).map(b=>b.toString(16).padStart(2,'0')).join('');}
export function fontMetrics(bytes:Uint8Array):FontMetrics {
  const f=fontkit.create(bytes); if(f.characterSet.length>100000)throw new TicketFontError('font_metrics_limit');
  const advances:Record<string,number>={};
  for(const c of f.characterSet)advances[String.fromCodePoint(c)]=f.glyphForCodePoint(c).advanceWidth/f.unitsPerEm;
  if(!Number.isFinite(f.ascent/f.unitsPerEm)||!advances['?'])throw new TicketFontError('font_metrics_invalid');
  return Object.freeze({advances:Object.freeze(advances),ascent:f.ascent/f.unitsPerEm,descent:f.descent/f.unitsPerEm});
}
export interface FontStore {read(key:string):Promise<Uint8Array|null>; create(key:string,bytes:Uint8Array):Promise<boolean>}
export interface FontDependencies {
  store:FontStore; fetch:typeof fetch; bundled(asset:FontAsset):Promise<Uint8Array|null>;
  lookup?(id:string):Promise<FontAsset|null>; now?:()=>number;
  inspect?:(bytes:Uint8Array,asset:FontAsset)=>Promise<FontMetrics>;
  event?:(event:{id:string;source:string;bytes:number;duration:number})=>void;
}
export class TicketFontResolver {
  private cache=new Map<string,{font:TicketFont;size:number}>();private used=0;
  private inflight=new Map<string,Promise<TicketFont>>();private failures=new Map<string,number>();
  private active=0;private waiting:Array<()=>void>=[];
  constructor(private deps:FontDependencies,private limits={count:32,bytes:24*1024*1024,parallel:4,timeout:8000,cap:8*1024*1024}){}
  private async permit<T>(run:()=>Promise<T>):Promise<T>{
    if(this.active>=this.limits.parallel)await new Promise<void>(r=>this.waiting.push(r));else this.active++;
    try{return await run();}finally{const next=this.waiting.shift();if(next)next();else this.active--;}
  }
  async resolve(id:string):Promise<TicketFont>{
    const now=this.deps.now??Date.now;const hit=this.cache.get(id);
    if(hit){this.cache.delete(id);this.cache.set(id,hit);this.deps.event?.({id,source:'memory',bytes:hit.font.bytes.length,duration:0});return {...hit.font,bytes:hit.font.bytes.slice()};}
    let promise=this.inflight.get(id);
    if(!promise){
      if((this.failures.get(id)??0)>now())throw new TicketFontError('font_retry_backoff');
      promise=this.permit(()=>this.load(id)).then(font=>{
        const size=font.bytes.length+Object.keys(font.metrics.advances).length*64;
        while(this.cache.size&&(this.cache.size>=this.limits.count||this.used+size>this.limits.bytes)){const key=this.cache.keys().next().value!;this.used-=this.cache.get(key)!.size;this.cache.delete(key);}
        if(size<=this.limits.bytes){this.cache.set(id,{font,size});this.used+=size;}this.failures.delete(id);return font;
      }).catch(e=>{this.failures.set(id,now()+5000);while(this.failures.size>64)this.failures.delete(this.failures.keys().next().value!);throw e;}).finally(()=>this.inflight.delete(id));
      this.inflight.set(id,promise);
    }
    const font=await promise;return {...font,bytes:font.bytes.slice()};
  }
  private async validate(bytes:Uint8Array,a:FontAsset):Promise<FontMetrics>{
    if(bytes.length>this.limits.cap||bytes.length!==a.byteLength||await digest(bytes)!==a.sha256)throw new TicketFontError('font_integrity');
    const sig=String.fromCharCode(...bytes.slice(0,4));
    if(!(sig==='OTTO'||sig==='wOFF'||bytes[0]===0&&bytes[1]===1&&bytes[2]===0&&bytes[3]===0))throw new TicketFontError('font_format');
    if(this.deps.inspect)return this.deps.inspect(bytes,a);
    try{
      const parsed=fontkit.create(bytes);
      if(a.source!=='bundled'&&(Object.keys(parsed.variationAxes??{}).length||['COLR','CBDT','sbix','SVG '].some(tag=>parsed.directory?.tables?.[tag])))throw new Error('Unsupported font');
      const metrics=fontMetrics(bytes);const doc=await PDFDocument.create();doc.registerFontkit(fontkit);await doc.embedFont(bytes);await doc.save();return metrics;
    }catch{throw new TicketFontError('font_unsupported');}
  }
  private async load(id:string):Promise<TicketFont>{
    const now=this.deps.now??Date.now;const start=now();
    const a=fontCatalog.find(f=>f.id===id)??await this.deps.lookup?.(id);
    if(!a||a.id!==id||! /^[a-f0-9]{64}$/.test(a.sha256)||a.byteLength<1||a.byteLength>this.limits.cap||!['ttf','woff'].includes(a.extension))throw new TicketFontError('font_unknown');
    if(a.source==='google'&&(id!==`gf:${a.sha256}`||a.extension!=='ttf'))throw new TicketFontError('font_unknown');
    let source='bundled';let bytes=await this.deps.bundled(a);let metrics:FontMetrics;
    if(bytes){metrics=await this.validate(bytes,a);}else{
      const key=`sha256/${a.sha256}.${a.extension}`;bytes=await this.deps.store.read(key);source='storage';
      if(bytes){metrics=await this.validate(bytes,a);}else{
        if(a.source!=='google')throw new TicketFontError('font_asset_missing');source='provider';
        const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),this.limits.timeout);
        try{
          const response=await this.deps.fetch(`https://fonts.gstatic.com/s/a/${a.sha256}.ttf`,{redirect:'error',signal:controller.signal});
          if(!response.ok||response.redirected)throw new TicketFontError('font_provider');
          const reader=response.body?.getReader();if(!reader)throw new TicketFontError('font_empty');
          const chunks:Uint8Array[]=[];let size=0;
          while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>this.limits.cap){await reader.cancel();throw new TicketFontError('font_size');}chunks.push(value);}
          bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
        }catch(e){if(e instanceof TicketFontError)throw e;throw new TicketFontError(controller.signal.aborted?'font_timeout':'font_provider');}finally{clearTimeout(timer);}
        metrics=await this.validate(bytes,a);
        if(!await this.deps.store.create(key,bytes)){const winner=await this.deps.store.read(key);if(!winner)throw new TicketFontError('font_storage_conflict');metrics=await this.validate(winner,a);bytes=winner;}
      }
    }
    this.deps.event?.({id,source,bytes:bytes.length,duration:now()-start});
    return Object.freeze({id,bytes,metrics,family:a.family,weight:a.weight});
  }
}
