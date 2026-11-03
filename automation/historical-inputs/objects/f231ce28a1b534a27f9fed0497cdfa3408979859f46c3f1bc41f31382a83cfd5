import {assertEquals,assert,assertThrows} from 'jsr:@std/assert@1';
import {fontFamilyCatalog,fontCatalog,resolveFontFamilyFace,TicketFontError,digest} from './ticketFonts.ts';
import {canonicalLayoutResourceJson} from './layoutTextPreparation.ts';
Deno.test('real family manifests bind every supported combination without synthetic styles',async()=>{
 const roboto=fontFamilyCatalog.find(f=>f.family==='Roboto')!;
 const ids=[];
 for(const weight of [400,700] as const)for(const italic of [false,true]){
  const face=resolveFontFamilyFace(roboto.id,weight,italic);ids.push(face.id);
  assertEquals(face.weight,weight);assertEquals(face.style,italic?'italic':'normal');assert(face.id.endsWith(face.sha256));
 }
 assertEquals(new Set(ids).size,4);
 for(const family of fontFamilyCatalog){
  const payload={faces:family.faces,family:family.family,version:family.version};
  assertEquals(family.id,`font-family:${await digest(new TextEncoder().encode(canonicalLayoutResourceJson(payload)))}`);
  for(const id of Object.values(family.faces))assert(fontCatalog.some(f=>f.id===id));
 }
});
Deno.test('missing bold/italic faces and unknown families fail explicitly',()=>{
 const tiro=fontFamilyCatalog.find(f=>f.family==='Tiro Devanagari Hindi')!;
 assertThrows(()=>resolveFontFamilyFace(tiro.id,700,false),TicketFontError,'font_face_unavailable');
 assertThrows(()=>resolveFontFamilyFace('unknown',400,false),TicketFontError,'font_family_unknown');
});
