import {assert,assertEquals} from 'jsr:@std/assert@1';
import {ticketGallery} from './ticketGallery.ts';
import {themeTicketTemplate,ticketThemeFonts,ticketThemePalettes} from './ticketTheme.ts';
Deno.test('retired blank layouts are absent while named designs stay available',()=>{
 const catalog=ticketGallery();for(const key of ['classic','compact','event','portrait_compact','portrait_event'])assert(!(key in catalog));
 for(const key of ['portrait'])assert(key in catalog);
 assertEquals(Object.keys(catalog).length,15);
});
Deno.test('ticket text is neutral and QR black on white in every theme, including silk',()=>{
 for(const [style,[primary,secondary]] of Object.entries(ticketThemePalettes)) {
  for(const [key,raw] of Object.entries(ticketGallery())) {
   const t=themeTicketTemplate(raw,primary,secondary,ticketThemeFonts[style],key);
   for(const e of t.elements) {
    const c=e.style.color;assert(c.slice(0,2)===c.slice(2,4)&&c.slice(2,4)===c.slice(4,6),`${key}/${style}: colored ${e.binding}`);
    if(e.binding==='qr')assertEquals(c,'000000');
   }
   assertEquals(t.qrAppearance?.background,'FFFFFF');
  }
 }
});

Deno.test('preset and custom palettes share one persistent artwork path and renderer', async () => {
 const {galleryBackground,galleryBackgrounds}=await import('./ticketGallery.ts');
 const {themedTicketBackground,ticketThemeColor}=await import('./ticketTheme.ts');
 const {PNG}=await import('npm:pngjs@5.0.0');
 const {Buffer}=await import('node:buffer');
 const {ticketArtworkColor,ticketArtworkRoles}=await import('./ticketThemePalette.js');
 const proofs=[];
 for(const [primary,secondary] of [['14284B','A87F28'],['198A61','DE5734']]) {
  for(const key of ['concert_stub','club_panorama','cinema_strip','gala_invitation','theatre_program','boarding_pass']) {
   const url=themedTicketBackground(key,primary,secondary,galleryBackgrounds[key])!;
   assert(url.includes(`/palette-${primary}-${secondary}-${key}-v2.png`));
   const bytes=(await galleryBackground(url))!;
   const png=PNG.sync.read(Buffer.from(bytes));
   const original=PNG.sync.read(Buffer.from((await galleryBackground(galleryBackgrounds[key]!))!));
   assertEquals([png.width,png.height],[original.width,original.height]);
   const checked=new Set<number>();
   for(let i=0;i<original.data.length;i+=4){
    const rgb=(original.data[i]<<16)|(original.data[i+1]<<8)|original.data[i+2];
    if(checked.has(rgb))continue;checked.add(rgb);
    assertEquals(Buffer.from(png.data.subarray(i,i+3)).toString('hex').toUpperCase(),ticketArtworkColor(rgb.toString(16).padStart(6,'0'),primary,secondary,ticketArtworkRoles[key]));
   }
   const rgbaSha=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',png.data))).map(x=>x.toString(16).padStart(2,'0')).join('');
   proofs.push({key,primary,secondary,url,width:png.width,height:png.height,rgbaSha});
  }
 }
 const out=Deno.env.get('TICKET_CUSTOM_ARTWORK_EVIDENCE');
 if(out)await Deno.writeTextFile(out,JSON.stringify(proofs));
 for(const bad of ['https://img.festapp.net/ticket-presets/v1/palette-198A61-DE5734-unknown-v1.png','https://img.festapp.net/ticket-presets/v1/palette-not-a-palette.png']) {
  let denied=false;try{await galleryBackground(bad);}catch{denied=true;}assert(denied);
 }
});

Deno.test('cinema dominant panel follows primary ink instead of its original warm hue', async () => {
 const {galleryBackground}=await import('./ticketGallery.ts');
 const {PNG}=await import('npm:pngjs@5.0.0');
 const {Buffer}=await import('node:buffer');
 const {ticketThemeColor}=await import('./ticketTheme.ts');
 const png=PNG.sync.read(Buffer.from((await galleryBackground('https://img.festapp.net/ticket-presets/v1/palette-198A61-DE5734-cinema_strip-v2.png'))!));
 const offset=(Math.round(25*8)*png.width+Math.round(80*8))*4;
 assertEquals(Buffer.from(png.data.subarray(offset,offset+3)).toString('hex').toUpperCase(),ticketThemeColor('211F1A','198A61','198A61'));
});
