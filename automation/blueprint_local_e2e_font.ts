// Synthetic local fixture; uses the same immutable face and whole-text owner.
import {fontCatalog,fontFamilyCatalog,fontMetrics} from '../supabase/functions/_shared/ticketFonts.ts';
import {prepareLayoutTextResources} from '../supabase/functions/_shared/layoutTextResources.ts';
const asset=fontCatalog.find(font=>font.file==='font.ttf')!;
const family=fontFamilyCatalog.find(f=>f.faces['400:normal']===asset.id)!;
const bytes=await Deno.readFile(new URL('../supabase/functions/_shared/ticket-assets/font.ttf',import.meta.url));
const requests=[['Mixed table',220,100],['Standing',260,160]].map(([text,width,height])=>({text,role:'label',fontFamilyId:family.id,fontFaceId:asset.id,size:24,language:'und',direction:'auto',lineHeight:1.2,align:'center',box:{x:-Number(width)/2,y:-Number(height)/2,width,height},fit:'shrink'}));
const resources=await prepareLayoutTextResources({requests,numericFaces:[{fontFamilyId:family.id,fontFaceId:asset.id}]},async()=>({...asset,bytes,metrics:fontMetrics(bytes)}));
console.log(JSON.stringify({fontId:asset.id,resources}));
