interface FontMetrics {advances:Readonly<Record<string,number>>;ascent:number;descent:number}
export const PREPARED_FONT_VERSION=1;
export interface PreparedFont {schema:1;generator:1;fontHash:string;metricsDigest:string;metrics:FontMetrics}
export async function resourceDigest(bytes:Uint8Array):Promise<string>{return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new Uint8Array(bytes).buffer)),b=>b.toString(16).padStart(2,'0')).join('');}
export async function preparedFont(hash:string,metrics:FontMetrics):Promise<PreparedFont>{
 return {schema:1,generator:1,fontHash:hash,metricsDigest:await resourceDigest(new TextEncoder().encode(JSON.stringify(metrics))),metrics};
}
export async function readPreparedFont(bytes:Uint8Array,hash:string):Promise<PreparedFont>{
 if(bytes.length>8*1024*1024)throw new Error('font_prepared_integrity');
 const v=JSON.parse(new TextDecoder('utf-8',{fatal:true,ignoreBOM:false}).decode(bytes));
 const m=v?.metrics;
 if(v?.schema!==1||v.generator!==PREPARED_FONT_VERSION||v.fontHash!==hash||!m||!Number.isFinite(m.ascent)||!Number.isFinite(m.descent)||!m.advances||Array.isArray(m.advances)||typeof m.advances!=='object'||!m.advances['?']||Object.keys(m.advances).length>100000||Object.entries(m.advances).some(([k,n])=>Array.from(k).length!==1||typeof n!=='number'||!Number.isFinite(n)||n<0)||v.metricsDigest!==await resourceDigest(new TextEncoder().encode(JSON.stringify(m))))throw new Error('font_prepared_integrity');
 return v;
}
