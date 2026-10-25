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
  } finally {
    Deno.readFileSync = readFileSync;
    fs.readFileSync = nodeReadFileSync;
  }
});
