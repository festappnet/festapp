export const qrColors = ['000000','2A2A2A','17365D','123B20','401529'];
export const bindings = ['qr', 'ticketSymbol', 'spotGroup', 'food', 'note', 'price', 'occasionTitle', 'occasionDatePlace', 'orderName', 'logo', 'footer'] as const;
export type TicketType = 'wide' | 'named';
export type Binding = typeof bindings[number];
export interface Box { x: number; y: number; width: number; height: number }
export interface Element { id: string; binding: Binding; box: Box; visible: boolean; locked: boolean; style: { fontSize: number; minFontSize: number; maxLines: number; color: string; align: 'left' | 'center' | 'right' } }
export interface Template { pageFit?: 'ticket'; page: {width: number; height: number}; ticketArea: Box; elements: Element[] }
export interface TicketLayout { schemaVersion: 1; templates: { wide?: Template; named?: Template } }
export function validateLayout(value: unknown): asserts value is TicketLayout {
  const v = value as TicketLayout;
  const fail = () => { throw new Error('Invalid ticket layout'); };
  if (!v || JSON.stringify(v).length > 32768 || v.schemaVersion !== 1 || !v.templates || Array.isArray(v.templates) || !Object.keys(v.templates).length || Object.keys(v.templates).some(k => !['wide', 'named'].includes(k))) fail();
  for (const [type, t] of Object.entries(v.templates)) {
    if (!t || (t.pageFit!==undefined && t.pageFit!=='ticket')) fail();
    if(t.pageFit==='ticket') {
      if(![t.page?.width,t.page?.height].every(v=>Number.isFinite(v)&&v>=60&&v<=842) ||
          t.ticketArea?.x!==0 || t.ticketArea?.y!==0 || t.ticketArea?.width!==t.page.width || t.ticketArea?.height!==t.page.height) fail();
    } else if(t.page?.width !== (type === 'wide' ? 595.28 : 212.5) || t.page?.height !== (type === 'wide' ? 841.89 : 387.5)) fail();
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
      if (!s || !Number.isFinite(s.fontSize) || !Number.isFinite(s.minFontSize) || s.minFontSize < 6 || s.fontSize < s.minFontSize || s.fontSize > 72 || !Number.isInteger(s.maxLines) || s.maxLines < 1 || s.maxLines > 12 || !/^[0-9A-Fa-f]{6}$/.test(s.color) || !['left','center','right'].includes(s.align)) fail();
      if (['qr','ticketSymbol'].includes(e.binding) && !e.visible) fail();
      if (e.binding === 'qr' && (e.box.width !== e.box.height || e.box.width < 60 || !qrColors.includes(s.color.toUpperCase()))) fail();
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
  const element=(binding:Binding,x:number,y:number,w:number,h:number,size=12,lines=2):Element=>({id:binding,binding,box:{x,y,width:w,height:h},visible:true,locked:false,style:{fontSize:size,minFontSize:6,maxLines:lines,color:'2A2A2A',align:named?'center':'left'}});
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

// Named/mobile and image-backed layouts share the original generators' pages.
// Selecting a style copies ordinary geometry; no second template/render contract.
export function ticketPresets(type: TicketType, imageWidth=1600, imageHeight=800): Record<string,Template> {
  const classic=preset(type,imageWidth,imageHeight);
  const make=(binding:Binding,x:number,y:number,width:number,height:number,fontSize=12,maxLines=2,align:'left'|'center'='left'):Element=>({id:binding,binding,box:{x,y,width,height},visible:true,locked:false,style:{fontSize,minFontSize:6,maxLines,color:'2A2A2A',align}});
  const compact=structuredClone(classic), event=structuredClone(classic);
  if(type==='named') {
    compact.elements=[make('logo',8,8,32,32),make('occasionTitle',50,8,142,40,15),make('occasionDatePlace',8,56,184,30,9),make('orderName',8,102,184,42,16,2,'center'),make('qr',60,178,80,80),make('ticketSymbol',8,265,184,22,10,1,'center'),make('footer',8,341,184,24,7,2,'center')];
    event.elements=[make('logo',79,12,42,42),make('occasionTitle',12,70,176,58,20,2,'center'),make('occasionDatePlace',12,132,176,28,10,2,'center'),make('orderName',12,170,176,32,14,2,'center'),make('qr',52,215,96,96),make('ticketSymbol',10,317,180,20,10,1,'center'),make('footer',6,351,187,18,6,2,'center')];
  } else {
    for(const [id,t] of [['compact',compact],['event',event]] as const) {
      t.ticketArea.height=Math.max(id==='event'?280:240,t.ticketArea.height);
      const w=t.ticketArea.width,h=t.ticketArea.height,left=w-160;
      const qr=id==='compact'?make('qr',w-100,20,80,80):make('qr',w-116,h-130,96,96);
      t.elements=[make('occasionTitle',20,12,id==='compact'?left:w-40,42,id==='compact'?18:24),make('occasionDatePlace',20,58,id==='compact'?left:w-40,24,11),make('orderName',20,90,left,32,14),qr,make('ticketSymbol',qr.box.x-4,qr.box.y+qr.box.height+4,qr.box.width+8,22,9,1,'center'),...(['spotGroup','food','note','price'] as Binding[]).map((binding,i)=>make(binding,20,h-108+i*22,left,21,11,1)),make('footer',20,h-18,left,16,7,1)];
    }
  }
  const result:Record<string,Template>={classic,compact,event,...(type==='wide'?{portrait:portraitPreset()}: {})};
  for(const t of Object.values(result))validateLayout({schemaVersion:1,templates:{[type]:t}});
  return result;
}
