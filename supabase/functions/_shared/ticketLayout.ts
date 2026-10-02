export const qrColors = ['000000','2A2A2A','17365D','123B20','401529'];
export function qrColorReadable(color:string):boolean {
  if(!/^[0-9a-fA-F]{6}$/.test(color))return false;
  const channels=[0,2,4].map(i=>{const c=parseInt(color.slice(i,i+2),16)/255;return c<=.04045?c/12.92:((c+.055)/1.055)**2.4;});
  return 1.05/(channels[0]*.2126+channels[1]*.7152+channels[2]*.0722+.05)>=4.5;
}
export const bindings = ['qr', 'ticketSymbol', 'spotGroup', 'food', 'note', 'price', 'occasionTitle', 'occasionDatePlace', 'orderName', 'logo', 'footer'] as const;
export type TicketType = 'wide' | 'named';
export type Binding = typeof bindings[number];
export interface Box { x: number; y: number; width: number; height: number }
export interface Element { id: string; binding: Binding; box: Box; visible: boolean; locked: boolean; style: { fontSize: number; minFontSize: number; maxLines: number; color: string; align: 'left' | 'center' | 'right'; bold?:boolean; italic?:boolean; underline?:boolean } }
export interface Template { pageFit?: 'ticket'; page: {width: number; height: number}; ticketArea: Box; elements: Element[] }
export interface TicketLayout { schemaVersion: 1; templates: { wide?: Template; named?: Template } }
export function validateLayout(value: unknown): asserts value is TicketLayout {
  const v = value as TicketLayout;
  const fail = () => { throw new Error('Invalid ticket layout'); };
  if (!v || JSON.stringify(v).length > 32768 || v.schemaVersion !== 1 || !v.templates || Array.isArray(v.templates) || !Object.keys(v.templates).length || Object.keys(v.templates).some(k => !['wide', 'named'].includes(k))) fail();
  for (const t of Object.values(v.templates)) {
    if (!t || (t.pageFit!==undefined && t.pageFit!=='ticket')) fail();
    if(t.pageFit==='ticket') {
      if(![t.page?.width,t.page?.height].every(v=>Number.isFinite(v)&&v>=60&&v<=842) ||
          t.ticketArea?.x!==0 || t.ticketArea?.y!==0 || t.ticketArea?.width!==t.page.width || t.ticketArea?.height!==t.page.height) fail();
    } else if(!((t.page?.width===595.28 && t.page?.height===841.89) || (t.page?.width===212.5 && t.page?.height===387.5))) fail();
    const checkBox = (b: Box, w: number, h: number) => {
      if (!b || ![b.x,b.y,b.width,b.height].every(Number.isFinite) || b.x < 0 || b.y < 0 || b.width < 1 || b.height < 1 || b.x+b.width > w+.001 || b.y+b.height > h+.001) fail();
    };
    checkBox(t.ticketArea,t.page.width,t.page.height);
    if (!Array.isArray(t.elements) || t.elements.length < 2 || t.elements.length > 11) fail();
    const ids = new Set(), seen = new Set();
    for (const e of t.elements) {
      if (!e || typeof e.id !== 'string' || !/^[a-zA-Z0-9_-]{1,40}$/.test(e.id) || ids.has(e.id) || seen.has(e.binding) || !bindings.includes(e.binding) || typeof e.visible !== 'boolean' || typeof e.locked !== 'boolean') fail();
      ids.add(e.id); seen.add(e.binding);
      checkBox(e.box,t.ticketArea.width,t.ticketArea.height);
      const s=e.style;
      if(s && ['bold','italic','underline'].some(key=>key in s && typeof (s as any)[key]!=='boolean')) fail();
      if (!s || !Number.isFinite(s.fontSize) || !Number.isFinite(s.minFontSize) || s.minFontSize < 6 || s.fontSize < s.minFontSize || s.fontSize > 72 || !Number.isInteger(s.maxLines) || s.maxLines < 1 || s.maxLines > 12 || !/^[0-9A-Fa-f]{6}$/.test(s.color) || !['left','center','right'].includes(s.align)) fail();
      if (['qr','ticketSymbol'].includes(e.binding) && !e.visible) fail();
      if (e.binding === 'qr' && (e.box.width !== e.box.height || e.box.width < 60 || !qrColorReadable(s.color))) fail();
    }
    if (!seen.has('qr') || !seen.has('ticketSymbol')) fail();
    const q=t.elements.find(e=>e.binding==='qr')!.box;
    for (const e of t.elements.filter(e=>e.visible && !['qr','logo'].includes(e.binding))) {
      const b=e.box;
      if (b.x < q.x+q.width && b.x+b.width > q.x && b.y < q.y+q.height && b.y+b.height > q.y) fail();
    }
  }
}
export function pdfBox(t: Template, b: Box): Box { return {...b,x:t.ticketArea.x+b.x,y:t.page.height-t.ticketArea.y-b.y-b.height}; }
export function preset(type: 'wide'|'named', imageWidth=1600, imageHeight=800): Template {
  const named=type==='named';
  const width=named?200:Math.max(240,Math.min(535.752,782.362*imageWidth/imageHeight));
  const height=named?375:Math.min(782.362, width*imageHeight/imageWidth);
  const area:Box={x:named?0:(595.28-width)/2,y:named?0:29.764,width,height};
  const element=(binding:Binding,x:number,y:number,w:number,h:number,size=12,lines=2):Element=>({id:binding,binding,box:{x,y,width:w,height:h},visible:true,locked:false,style:{fontSize:size,minFontSize:6,maxLines:lines,color:'2A2A2A',align:named||binding==='ticketSymbol'?'center':'left'}});
  let elements:Element[];
  if(named) elements=[element('logo',71.875,12.5,56.25,56.25),element('occasionTitle',6.25,77,187.5,32,12.5),element('occasionDatePlace',6.25,111,187.5,24,8.75),element('orderName',6.25,151,187.5,32,12.5),element('qr',50,206.25,100,100),element('ticketSymbol',10,313,180,20,8.75,1),element('footer',6.25,348,187.5,20,6.25)];
  else {
    // Preserve the historical image-relative placement when it fits; normalize
    // extreme aspect ratios into a printable area for the first explicit edit.
    const h=Math.max(140,height); area.height=h;
    const scale=width/imageWidth, q=Math.max(60,Math.min(100,240*scale,h-55));
    const qx=Math.max(width*.55,Math.min(width-q, width-(240+150)*scale));
    const qy=Math.max(8,Math.min(h-q-28,h-(240+140)*scale));
    const tx=Math.min(50,150*scale), tw=Math.min(width*.45,qx-tx-8);
    elements=[element('qr',qx,qy,q,q),element('ticketSymbol',qx,qy+q+4,q,22,Math.min(24,Math.max(8,28*scale)),1),...(['spotGroup','food','note','price'] as Binding[]).map((b,i)=>element(b,tx,Math.max(8,h-100)+i*22,tw,21,Math.min(24,Math.max(8,24*scale)),1))];
  }
  return {...(named?{pageFit:'ticket' as const}:{}),page:{width:named?200:595.28,height:named?375:841.89},ticketArea:area,elements};
}

// Portrait is a ticket-sized PDF, independently of the selected template slot.
export function portraitPreset(): Template { return preset('named'); }

export function parseLayout(value: unknown): TicketLayout { validateLayout(value); return structuredClone(value); }

// Gallery presets establish a clear hierarchy while leaving saved layouts and
// the historical first-edit fallback untouched.
function styleVariants(type: TicketType): Record<string,Template> {
  const base=preset(type);
  const make=(binding:Binding,x:number,y:number,width:number,height:number,fontSize=12,maxLines=2,align:'left'|'center'='left'):Element=>({id:binding,binding,box:{x,y,width,height},visible:true,locked:false,style:{fontSize,minFontSize:6,maxLines,color:'202020',align}});
  const classic=structuredClone(base),compact=structuredClone(base),event=structuredClone(base);
  if(type==='named') {
    classic.elements=[make('occasionTitle',12,18,176,58,22,2,'center'),make('logo',80,86,40,40),make('occasionDatePlace',12,136,176,30,10,2,'center'),make('orderName',12,180,176,36,18,2,'center'),make('qr',52,228,96,96),make('ticketSymbol',12,330,176,20,11,1,'center'),make('footer',12,356,176,14,7,1,'center')];
    compact.elements=[make('logo',12,20,56,56),make('qr',112,16,72,72),make('ticketSymbol',100,93,96,18,9,1,'center'),make('occasionTitle',12,120,176,54,20),make('occasionDatePlace',12,188,176,32,10),make('orderName',12,250,176,60,26),make('footer',12,342,176,24,8)];
    event.elements=[make('occasionTitle',12,20,176,76,28,2,'center'),make('logo',84,106,32,32),make('occasionDatePlace',12,146,176,28,10,2,'center'),make('orderName',12,186,176,30,17,2,'center'),make('qr',52,228,96,96),make('ticketSymbol',12,330,176,20,11,1,'center'),make('footer',12,356,176,14,7,1,'center')];
  } else {
    for(const [id,t] of [['classic',classic],['compact',compact],['event',event]] as const) {
      t.ticketArea.height=Math.max(id==='compact'?260:320,t.ticketArea.height);
      const w=t.ticketArea.width,h=t.ticketArea.height,left=w-156;
      const qr=id==='compact'?make('qr',w-100,20,80,80):make('qr',w-116,id==='classic'?Math.round((h-96)/2):h-130,96,96);
      const title=make('occasionTitle',20,18,id==='event'?w-40:left,id==='event'?64:54,id==='event'?32:id==='classic'?24:20);
      const details=(['spotGroup','food','note','price'] as Binding[]).map((binding,i)=>make(binding,20,h-108+i*21,left,20,binding==='spotGroup'||binding==='price'?12:10,1));
      t.elements=[title,make('occasionDatePlace',20,id==='event'?90:80,id==='event'?w-40:left,28,11),make('orderName',20,id==='event'?128:118,left,30,16),qr,make('ticketSymbol',qr.box.x-4,qr.box.y+qr.box.height+5,qr.box.width+8,22,10,1,'center'),...details,make('footer',20,h-18,left,16,7,1)];
    }
  }
  for(const t of [classic,compact,event]) {
    for(const e of t.elements) {
      if(['occasionTitle','orderName','ticketSymbol','spotGroup','price'].includes(e.binding))e.style.bold=true;
      if(e.binding==='footer')e.style.italic=true;
    }
    validateLayout({schemaVersion:1,templates:{[type]:t}});
  }
  return {classic,compact,event};
}

// The storage slot does not determine the PDF format: ordinary templates stay
// on A4, while named templates use the physical ticket size. Gallery geometry
// is independent of artwork; renderers contain the image within the ticket.
export function ticketPresets(): Record<string,Template> {
  const wide=styleVariants('wide');
  const named=styleVariants('named');
  return {classic:wide.classic,compact:wide.compact,event:wide.event,portrait:named.classic,portrait_compact:named.compact,portrait_event:named.event};
}
