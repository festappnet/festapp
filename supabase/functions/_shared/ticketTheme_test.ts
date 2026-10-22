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
