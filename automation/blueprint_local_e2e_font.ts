// Local fixture resource generation from the same immutable registered ticket bytes.
import {layoutFontOutline} from '../supabase/functions/_shared/layoutFontOutline.ts';
import {fontCatalog,fontMetrics} from '../supabase/functions/_shared/ticketFonts.ts';
const asset=fontCatalog.find(font=>font.file==='font.ttf');
if(!asset)throw new Error('Registered bundled fixture font missing');
const bytes=await Deno.readFile(new URL('../supabase/functions/_shared/ticket-assets/font.ttf',import.meta.url));
const outline=await layoutFontOutline({id:asset.id,bytes,family:asset.family,weight:asset.weight,metrics:fontMetrics(bytes)},'Židle Stání Mixed table Atomic couch Free Used Foreign Own Empty €');
console.log(JSON.stringify(outline));
