import {assertEquals,assert,assertRejects} from 'jsr:@std/assert@1';
import {layoutFontOutline} from './layoutFontOutline.ts';
import {fontCatalog,fontMetrics,TicketFontError} from './ticketFonts.ts';
Deno.test('layout outlines use exact registered ticket bytes and portable path commands',async()=>{
  const asset=fontCatalog.find(f=>f.file==='font.ttf')!;
  const bytes=await Deno.readFile(new URL('./ticket-assets/font.ttf',import.meta.url));
  const font={id:asset.id,bytes,metrics:fontMetrics(bytes),family:asset.family,weight:asset.weight};
  const outline=await layoutFontOutline(font,'Židle €');
  assertEquals(outline.hash,asset.sha256);
  assertEquals(outline.id,asset.id);
  assert(outline.glyphs['Ž'].path.length>0);
  assert(outline.glyphs['?'].advance>0);
  for(const glyph of Object.values(outline.glyphs))for(const cmd of glyph.path)assert(['M','L','Q','C','Z'].includes(cmd[0] as string));
  await assertRejects(()=>layoutFontOutline({...font,id:'gf:'+'a'.repeat(64)},''),TicketFontError,'font_integrity');
  await assertRejects(()=>layoutFontOutline(font,'x'.repeat(4097)),TicketFontError,'font_characters_limit');
});
