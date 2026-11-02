import fs from 'node:fs';
import {assertEquals, assert} from 'jsr:@std/assert@1';

Deno.test('layout text shapes in Edge workers where synchronous file reads are blocked', async () => {
  const readFileSync = Deno.readFileSync;
  const nodeReadFileSync = fs.readFileSync;
  Deno.readFileSync = () => {throw new Error('Deno.readFileSync is blocklisted on the current context');};
  fs.readFileSync = () => {throw new Error('Deno.readFileSync is blocklisted on the current context');};
  try {
    const {LayoutTextFace} = await import('./layoutTextShaper.ts');
    const {fontCatalog, fontMetrics} = await import('./ticketFonts.ts');
    const bytes = await Deno.readFile(new URL('./ticket-assets/font.ttf', import.meta.url));
    const entry = fontCatalog.find(f => f.family === 'Futura PT')!;
    const face = await LayoutTextFace.fromTicketFont({...entry, bytes, metrics: fontMetrics(bytes)});
    const result = face.vector('Pódium Židle 123', {direction: 'ltr', script: 'latn', language: 'cs'});
    assert(result.path.length > 0);
    assertEquals(result.glyphs.length, 16);
    // Saving a blueprint prepares whole labels, not only HarfBuzz glyphs.
    // Import after blocking sync reads to exercise the cold Edge worker path.
    const {prepareLayoutTextResources} = await import('./layoutTextResources.ts');
    const {fontFamilyCatalog} = await import('./ticketFonts.ts');
    const family = fontFamilyCatalog.find(f => Object.values(f.faces).includes(entry.id))!;
    const prepared = await prepareLayoutTextResources({requests:[{
      text:'Autobus Řidič', role:'text', fontFamilyId:family.id,
      fontFaceId:entry.id, size:24, language:'und', direction:'auto',
      lineHeight:1.2, align:'center', box:{x:0,y:0,width:240,height:100}, fit:'wrap',
    }],numericFaces:[]}, async () => ({...entry,bytes,metrics:fontMetrics(bytes)}));
    assertEquals(Object.keys(prepared.textLayouts).length,1);
    assert(Object.values(prepared.textLayouts)[0].path.length > 0);
  } finally {
    Deno.readFileSync = readFileSync;
    fs.readFileSync = nodeReadFileSync;
  }
});
