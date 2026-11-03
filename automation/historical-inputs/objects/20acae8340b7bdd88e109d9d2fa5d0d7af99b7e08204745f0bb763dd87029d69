import { ticketPresets, validateLayout, type Template, type Element, type Binding } from './ticketLayout.ts';
import { fontCatalog } from './ticketFonts.ts';

// Immutable sources are resolved from the Function bundle, never a remote image.
const root = 'https://img.festapp.net/ticket-presets/v1/';
export const galleryBackgrounds: Record<string, string | null> = {
  concert_stub: `${root}concert-stub-v3.png`, ball_silk: `${root}silk-ivory-v1.jpg`,
  festival_poster: `${root}festival-poster-v3.png`, club_panorama: `${root}club-panorama-v3.png`,
  theatre_program: `${root}theatre-program-v3.png`, gallery_square: `${root}gallery-square-v3.png`,
  gala_invitation: `${root}gala-invitation-v3.png`, boarding_pass: `${root}boarding-pass-v3.png`,
  cinema_strip: `${root}cinema-strip-v3.png`, sports_arena: `${root}sports-arena-v3.png`,
  festival_badge: `${root}festival-badge-v3.png`, workshop_card: `${root}workshop-card-v3.png`,
};
// Retain already selected v1 sources when a draft is reopened.
export const backgroundFiles = new Set(['silk-ivory-v1.jpg','aurora-v1.png','midnight-v1.png','coral-v1.png',
  ...['concert-stub','festival-poster','club-panorama','theatre-program','gallery-square','boarding-pass'].map(name=>`${name}-v2.png`),
  ...Object.values(galleryBackgrounds).filter((url):url is string=>url!==null).map(url=>url.slice(root.length))]);
const font = (family: string) => {
  const entry = fontCatalog.find(f => f.family === family && f.weight === 400 && f.style === 'normal');
  if (!entry) throw new Error(`Missing gallery font: ${family}`);
  return entry.id;
};
export const galleryFontIds = [font('Playfair Display'), font('Manrope'),font('Russo One (legacy)'),font('Roboto Slab (legacy)')];
export async function galleryBackground(url: string): Promise<Uint8Array | undefined> {
  if (!url.startsWith(root) || !backgroundFiles.has(url.slice(root.length))) return undefined;
  return await Deno.readFile(new URL(`./ticket-assets/backgrounds/${url.slice(root.length)}`, import.meta.url));
}
const pt = (mm:number) => mm*72/25.4;
// Geometry is in millimetres here, converted once into the shared PDF-point contract.
const element = (binding:Binding,x:number,y:number,width:number,height:number,size:number,lines=1,align:'left'|'center'|'right'='left',color='222A31'):Element => ({
  id:binding,binding,box:{x:pt(x),y:pt(y),width:pt(width),height:pt(height)},visible:true,locked:false,
  style:{fontSize:size,minFontSize:6,maxLines:lines,color,align},
});
function design(width:number,height:number,elements:Element[],serif=false,color='FFFFFF'):Template {
  for(const e of elements) {
    if(e.binding==='occasionTitle') {e.style.fontId=galleryFontIds[serif?0:1];e.style.bold=!serif;}
  }
  return {pageFit:'ticket',pageMargin:0,page:{width:pt(width),height:pt(height)},
    ticketArea:{x:0,y:0,width:pt(width),height:pt(height)},fontId:galleryFontIds[1],canvasColor:color,
    qrAppearance:{background:'FFFFFF',opacity:1,margin:4},elements};
}
export function ticketGallery(): Record<string, Template> {
  const e=element;
  const styles:Record<string,Template>={
    // Traditional landscape admission: event body plus a separate control panel.
    concert_stub:design(180,65,[
      e('occasionDatePlace',23,6,101,10,9,2),e('occasionTitle',23,19,101,22,32,2),
      e('orderName',23,44,101,6,11),e('spotGroup',23,55,73,5,9),e('price',99,55,25,5,9,1,'right'),
      e('qr',140,15,26,26,9),e('ticketSymbol',133,45,40,6,9,1,'center'),
    ]),
    // Formal ball: centered invitation hierarchy, a small QR anchored at the foot.
    ball_silk:design(180,90,[
      e('occasionTitle',12,15,156,23,32,2,'center'),e('occasionDatePlace',30,43,120,13,11,2,'center'),
      e('orderName',18,68,100,7,14),e('spotGroup',18,79,78,5,9),e('price',99,79,22,5,9),
      e('qr',141,59,24,24,9),e('ticketSymbol',131,84,44,5,8,1,'center'),
    ],true),
    // Festival: a small poster, oversized type, contrasting admission band.
    festival_poster:design(90,140,[
      e('occasionTitle',8,10,74,62,47,4),e('occasionDatePlace',8,79,74,17,11,3),
      e('qr',8,110,22,22,9),e('ticketSymbol',4,134,30,4,6.5,1,'center','FFFFFF'),
      e('orderName',38,110,45,9,11,2,'left','FFFFFF'),e('spotGroup',38,123,45,6,8,1,'left','FFFFFF'),
      e('price',38,132,45,5,10,1,'left','FFFFFF'),
    ],false,'E4F359'),
    // Long club ticket: title / prominent start time / independent scanning panel.
    club_panorama:design(210,70,[
      e('occasionTitle',10,13,110,29,34,2,'left','F5F4EF'),
      e('occasionDatePlace',10,49,105,13,9,2,'left','F5F4EF'),
      e('occasionStartTime',125,14,39,14,26,1,'center','D8C5FF'),
      e('price',125,39,39,7,12,1,'center','F5F4EF'),e('spotGroup',125,52,39,7,9,1,'center','F5F4EF'),
      e('qr',175,17,25,25,9),e('ticketSymbol',171,46,33,6,8,1,'center','F5F4EF'),
    ],false,'19152B'),
    // A6 theatre programme: centered serif cover, fine rules, quiet admission block.
    theatre_program:design(105,148,[
      e('occasionPlace',12,10,81,8,10,1,'center','6A2635'),
      e('occasionTitle',10,32,85,38,33,3,'center','6A2635'),
      e('occasionDatePlace',14,78,77,14,10,2,'center'),e('orderName',12,98,81,7,12,1,'center'),
      e('qr',40,111,25,25,9),e('ticketSymbol',27,138,51,5,8,1,'center'),
    ],true,'F5F0E6'),
    // Square art admission: an asymmetric editorial grid, QR at the lower left.
    gallery_square:design(100,100,[
      e('occasionTitle',8,8,84,36,32,3,'left','BD342B'),
      e('qr',8,62,26,26,9),e('ticketSymbol',5,91,32,5,7,1,'center'),
      e('occasionDatePlace',44,61,48,15,9,3),e('orderName',44,79,48,7,10),e('price',44,90,48,5,9),
    ]),
    // Long invitation: a portrait silhouette and generous, centered vertical rhythm.
    gala_invitation:design(70,160,[
      e('occasionPlace',8,12,54,9,9,2,'center'),e('occasionTitle',7,35,56,44,28,4,'center'),
      e('occasionDatePlace',9,86,52,17,10,3,'center'),e('orderName',8,110,54,8,12,1,'center'),
      e('qr',23,125,24,24,9),e('ticketSymbol',10,152,50,5,8,1,'center'),
    ],true,'102F2B'),
    // Cinema roll: the scan panel leads, film title and screening details follow.
    cinema_strip:design(160,60,[
      e('qr',8,13,25,25,9),e('ticketSymbol',4,41,33,6,8,1,'center'),
      e('occasionTitle',47,9,105,21,25,2,'left','F3CF70'),
      e('occasionDatePlace',47,35,105,11,10,2,'left','F6F0DC'),
      e('spotGroup',47,50,75,5,9,1,'left','F6F0DC'),e('price',128,50,24,5,9,1,'right','F3CF70'),
    ],false,'211F1A'),
    // Sports admission: strong team/event typography above a full-width control row.
    sports_arena:design(190,80,[
      e('occasionTitle',10,10,124,28,32,2,'left','FFFFFF'),
      e('occasionStartTime',145,12,34,13,26,1,'center','FFC47B'),
      e('occasionDatePlace',10,40,124,11,9,2,'left','FFFFFF'),
      e('qr',146,44,26,26,9),e('ticketSymbol',140,72,39,5,8,1,'center'),
      e('orderName',10,61,65,7,12),e('spotGroup',79,62,56,6,10),e('price',145,30,34,6,10,1,'center','FFFFFF'),
    ],false,'102C4A'),
    // Lanyard credential: the attendee, not the event title, owns the hierarchy.
    festival_badge:design(80,120,[
      e('occasionTitle',8,11,64,17,16,2,'center','FFFFFF'),
      e('orderName',8,39,64,22,26,2,'center'),e('spotGroup',8,65,64,6,10,1,'center'),
      e('qr',27,78,26,26,9),e('ticketSymbol',12,107,56,5,8,1,'center'),
    ],false,'F5F0FC'),
    // Landscape workshop card: a calm left-aligned brief and a contrasting right rail.
    workshop_card:design(148,105,[
      e('occasionDatePlace',10,9,84,17,9,3),e('occasionTitle',10,36,83,30,28,3),
      e('orderName',10,80,83,8,12),e('price',10,94,83,5,9),
      e('occasionStartTime',103,13,36,12,22,1,'center'),
      e('qr',108,58,26,26,9),e('ticketSymbol',101,88,40,6,8,1,'center'),
    ],false,'FCFBF5'),
    // Boarding-pass idiom: colored event header, a structured lower information grid.
    boarding_pass:design(200,90,[
      e('occasionTitle',10,8,130,19,27,2,'left','FFFFFF'),
      e('occasionDatePlace',153,8,38,18,8,3,'left','FFFFFF'),
      e('occasionPlace',10,36,63,12,13,2),e('occasionStartTime',83,36,49,12,25),
      e('orderName',10,57,120,9,15),e('spotGroup',10,76,86,6,10),e('price',105,76,31,6,10),
      e('qr',157,42,28,28,9),e('ticketSymbol',150,74,42,6,9,1,'center'),
    ]),
  };
  const palettes:Record<string,[string,string]>={
    concert_stub:['7F281F','EDE8DE'],ball_silk:['5B4330','F8F1E5'],
    festival_poster:['203B2F','E4F359'],club_panorama:['38234F','E9DFFF'],
    theatre_program:['6A2635','F5F0E6'],gallery_square:['B1362C','FFFFFF'],
    gala_invitation:['193E33','F4EAD2'],boarding_pass:['164D49','DAE9E2'],
    cinema_strip:['322A18','F3CF70'],sports_arena:['102C4A','F2F5F7'],
    festival_badge:['3A2857','EEE7FC'],workshop_card:['294D3B','E2EBDD'],
  };
  for(const [key,t] of Object.entries(styles)) {
    const [ink,paper]=palettes[key];
    t.elements.find(e=>e.binding==='qr')!.style.color=ink;
    t.qrAppearance={background:paper,opacity:1,margin:4};
    if(['concert_stub','festival_poster','club_panorama','sports_arena','cinema_strip'].includes(key))
      t.elements.find(e=>e.binding==='occasionTitle')!.style.fontId=galleryFontIds[2];
    if(key==='gallery_square')t.elements.find(e=>e.binding==='occasionTitle')!.style.fontId=galleryFontIds[3];
    if(key==='gala_invitation')for(const e of t.elements)if(e.binding!=='qr')e.style.color='F4EAD2';
    if(['ball_silk','theatre_program'].includes(key))t.elements.find(e=>e.binding==='occasionTitle')!.style.italic=true;
    validateLayout({schemaVersion:3,templates:{wide:t}});
  }
  return {...ticketPresets(),...Object.fromEntries(Object.keys(galleryBackgrounds).map(key=>[key,styles[key]]))};
}
