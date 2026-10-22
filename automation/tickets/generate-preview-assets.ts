// deno run --frozen --lock=supabase/functions/deno.lock --allow-read --allow-write automation/tickets/generate-preview-assets.ts [--check]
import {ticketGallery, galleryBackgrounds, backgroundFiles, galleryFontIds} from '../../supabase/functions/_shared/ticketGallery.ts';
import {fontCatalog, TicketFontResolver, digest} from '../../supabase/functions/_shared/ticketFonts.ts';
const root=new URL('../../supabase/functions/_shared/ticket-assets/',import.meta.url);
const output=new URL('preview-manifest.json',root);
const check=Deno.args.includes('--check');
const fonts:Record<string,unknown>={};
const resolver=new TicketFontResolver({store:{read:async()=>null,create:async()=>true},fetch:()=>{throw new Error('Build assets must be local');},bundled:a=>Deno.readFile(new URL(a.file??`gallery-fonts/${a.sha256}.ttf`,root))});
for(const asset of fontCatalog.filter(a=>a.file||galleryFontIds.includes(a.id))){
 const font=await resolver.resolve(asset.id);
 const metricsDigest=await digest(new TextEncoder().encode(JSON.stringify(font.metrics)));
 fonts[asset.id]={file:asset.file??`gallery-fonts/${asset.sha256}.ttf`,sha256:asset.sha256,byteLength:asset.byteLength,family:asset.family,weight:asset.weight,metrics:font.metrics,metricsDigest};
}
const artwork:Record<string,unknown>={};
for(const name of [...backgroundFiles].sort()){
 const bytes=await Deno.readFile(new URL(`backgrounds/${name}`,root));
 artwork[`https://img.festapp.net/ticket-presets/v1/${name}`]={file:`backgrounds/${name}`,sha256:await digest(bytes),byteLength:bytes.length};
}
const payload={schema:1,generator:1,fonts,artwork,presets:ticketGallery(),backgrounds:galleryBackgrounds};
const manifest={...payload,sha256:await digest(new TextEncoder().encode(JSON.stringify(payload)))};
const content=JSON.stringify(manifest)+'\n';
if(check){if(await Deno.readTextFile(output)!==content)throw new Error('Preview assets drift: run generate-preview-assets.ts');}
else await Deno.writeTextFile(output,content);
console.log(`preview assets ${check?'verified':'generated'}: ${Object.keys(fonts).length} fonts, ${Object.keys(artwork).length} artworks`);
