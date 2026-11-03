import {assert, assertEquals} from 'jsr:@std/assert@1';
import {PDFDocument} from 'npm:pdf-lib';
import {galleryBackgrounds, galleryBackground, galleryFontIds, ticketGallery} from './ticketGallery.ts';
import {fontCatalog, fontMetrics, digest, type TicketFont} from './ticketFonts.ts';
import {loadLayoutResources, generateTicketPdf} from './ticketGeneration.ts';
import {parseLayout,qrColorReadable} from './ticketLayout.ts';
import {sampleData} from './ticketRenderData.ts';

Deno.test('gallery resources round trip and render all designs in both storage slots', async () => {
  const fonts:Record<string,TicketFont>={};
  for(const id of galleryFontIds) {
    const asset=fontCatalog.find(f=>f.id===id)!;
    const bytes=await Deno.readFile(new URL(`./ticket-assets/${asset.file??`gallery-fonts/${asset.sha256}.ttf`}`,import.meta.url));
    assertEquals(await digest(bytes),asset.sha256);
    fonts[id]={id,bytes,metrics:fontMetrics(bytes),family:asset.family,weight:asset.weight};
  }
  const templates=ticketGallery();
  const sizes=new Set<string>();
  const qrInks=new Set<string>();
  for(const [key,backgroundUrl] of Object.entries(galleryBackgrounds)) {
    const t=templates[key];
    sizes.add(`${t.page.width}:${t.page.height}`);
    assertEquals(t.pageFit,'ticket');
    const ink=t.elements.find(e=>e.binding==='qr')!.style.color;
    qrInks.add(ink);
    assert(qrColorReadable(ink,t.qrAppearance!.background),`${key}: QR contrast`);
    assert(t.qrAppearance!.margin>=4,`${key}: quiet zone`);
    for(const type of ['wide','named'] as const) {
      const layout={schemaVersion:3,templates:{[type]:t}};
      assertEquals(parseLayout(layout),layout);
      // Exercise the saved-background loader and prove built-in assets need no HTTP request.
      const resources=await loadLayoutResources({features:[]},{ticket_type:type,layout,background:backgroundUrl},{},()=>{throw new Error('Unexpected network image read');});
      for(const scenario of ['normal','long']) {
        const data=scenario==='normal'?{...sampleData(),occasionTitle:'Večer pod hvězdami',orderName:'Kateřina Nováková'}:sampleData('long');
        const result=await generateTicketPdf(data,{...resources,fonts},t,type);
        const pdf=await PDFDocument.load(result.bytes);
        assertEquals(pdf.getPage(0).getSize(),t.page);
        assert(!result.warnings.includes('ticketSymbol'),`${key}:${scenario}`);
        assertEquals(t.qrAppearance?.opacity,1);
      }
    }
  }
  assertEquals(sizes.size,12,'Event types must have distinct physical formats');
  assert(qrInks.size>=6,'QR palettes must vary with the designs');
  assert((await galleryBackground('https://img.festapp.net/ticket-presets/v1/aurora-v1.png'))!.length>0,'Older selected artwork remains resolvable');
  assertEquals(await galleryBackground('https://img.festapp.net/ticket-presets/v1/../../private'),undefined);
  assertEquals(await galleryBackground('https://other.invalid/silk-ivory-v1.jpg'),undefined);
});
