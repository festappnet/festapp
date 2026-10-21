import {assertEquals,assert,assertThrows,assertRejects} from 'jsr:@std/assert@1';
import {LayoutTextFace,layoutTextOffsets,layoutTextEngine} from './layoutTextShaper.ts';
import {fontCatalog,fontMetrics,TicketFontError} from './ticketFonts.ts';
import oracle from './testdata/layout-shaping-oracle.json' with {type:'json'};
const asset=fontCatalog.find(f=>f.id===oracle.fontId)!;
async function registeredFace(){
 const bytes=await Deno.readFile(new URL('./ticket-assets/font.ttf',import.meta.url));
 return {id:asset.id,bytes,family:asset.family,weight:asset.weight,metrics:fontMetrics(bytes)};
}
Deno.test('sole layout shaper preserves exact oracle glyph IDs, UTF-8 clusters and positions',async()=>{
 const face=await LayoutTextFace.fromTicketFont(await registeredFace());
 assertEquals(layoutTextEngine.version,'14.6.0');
 for(const c of oracle.cases){
  if(c.glyphs.some(g=>g.g===0)){
   assertThrows(()=>face.shape(c.text,{direction:'ltr',script:'latn',language:'und'}),TicketFontError,'layout_glyph_unavailable');
   continue;
  }
  const glyphs=face.shape(c.text,{direction:'ltr',script:'latn',language:'und',numeric:c.numeric});
  assertEquals(glyphs.map(g=>({g:g.glyphId,cl:g.cluster,dx:g.xOffset,dy:g.yOffset,ax:g.xAdvance,ay:g.yAdvance})),c.glyphs,c.text);
  for(const g of glyphs){assert(face.path(g.glyphId).every(c=>['M','L','Q','C','Z'].includes(c[0] as string)));assert(Number.isFinite(face.bounds(g.glyphId).x));}
 }
});
Deno.test('native offsets preserve original NFD, CRLF and astral byte indices',()=>{
 assertEquals([...layoutTextOffsets('Á\r\n😀x')],[[0,0],[1,1],[2,3],[3,4],[4,5],[6,9],[7,10]]);
 assertThrows(()=>layoutTextOffsets('\ud800'),TicketFontError,'layout_text_invalid_unicode');
});
Deno.test('missing glyphs, non-numeric symbols and mismatched immutable bytes fail closed',async()=>{
 const font=await registeredFace(),face=await LayoutTextFace.fromTicketFont(font);
 assertThrows(()=>face.shape('😀',{direction:'ltr',script:'latn',language:'und'}),TicketFontError,'layout_glyph_unavailable');
 assertThrows(()=>face.shape('office',{direction:'ltr',script:'latn',language:'und',numeric:true}),TicketFontError,'layout_numeric_text');
 assertThrows(()=>face.shape('x'.repeat(4097),{direction:'ltr',script:'latn',language:'und'}),TicketFontError,'font_characters_limit');
 await assertRejects(()=>LayoutTextFace.fromTicketFont({...font,id:'gf:'+'0'.repeat(64)}),TicketFontError,'font_integrity');
 assertThrows(()=>face.path(0),TicketFontError,'layout_glyph_unavailable');
});

Deno.test('whole labels become a single vector path preserving contextual positions and empty ink',async()=>{
 const face=await LayoutTextFace.fromTicketFont(await registeredFace());
 const result=face.vector('AV Židle',{direction:'ltr',script:'latn',language:'und'});
 assertEquals(result.advance.x,result.glyphs.reduce((x,g)=>x+g.xAdvance,0));
 assert(result.path.length>0);assert(result.inkBounds.width>0);assert(result.inkBounds.height>0);
 const first=face.path(result.glyphs[0].glyphId)[0],placed=result.path[0];
 assertEquals(placed,[first[0],(first[1] as number)+result.glyphs[0].xOffset,-(first[2] as number)-result.glyphs[0].yOffset]);
 assertEquals(face.vector('',{direction:'ltr',script:'latn',language:'und'}),{glyphs:[],path:[],advance:{x:0,y:-0},inkBounds:{x:0,y:0,width:0,height:0}});
 for(const text of ['×0','×1','×2','×10','×5000','×20000'])assert(face.vector(text,{direction:'ltr',script:'latn',language:'und',numeric:true}).path.length>0);
});
