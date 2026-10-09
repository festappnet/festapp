import { validateLayout, backgroundBox, croppedBackgroundBox, pdfBox, positionedElements, effectiveFontId, type Template } from './ticketLayout.ts';
import { fitText, textInsets } from './ticketText.ts';
import type { RenderData } from './ticketRenderData.ts';
import type { Resources } from './ticketGeneration.ts';
import QRCode from "npm:qrcode";
import { PDFDocument, type PDFPage, rgb, degrees, pushGraphicsState, popGraphicsState, rectangle, clip, endPath, setLineWidth, setTextRenderingMode, TextRenderingMode, setStrokingRgbColor } from "npm:pdf-lib";
// Import all exports from fontkit (do not try to import a default)
import * as fontkit from "npm:fontkit";

/** A batch owns one decoded/compressed image; each output PDF gets its own copy. */
export interface PreparedTicketBackground {
  width: number;
  height: number;
  draw(document: PDFDocument, page: PDFPage, box: ReturnType<typeof pdfBox>): Promise<void>;
}
export async function prepareTicketBackground(bytes: Uint8Array): Promise<PreparedTicketBackground> {
  const source = await PDFDocument.create();
  const image = bytes[0] === 137 ? await source.embedPng(bytes) : await source.embedJpg(bytes);
  const page = source.addPage([image.width, image.height]);
  page.drawImage(image, { x: 0, y: 0, width: image.width, height: image.height });
  // Flush once so destination documents copy the encoded image stream instead
  // of decoding PNG pixels and compressing them again for every attachment.
  await source.flush();
  return {
    width: image.width, height: image.height,
    async draw(document, destination, box) {
      destination.drawPage(await document.embedPage(page), box);
    },
  };
}

export async function drawLayoutTicket(data:RenderData,r:Resources,t:Template,_type:'wide'|'named'=t.page.width===595.28?'wide':'named',_sample=false) {
  validateLayout({schemaVersion:t.fontId||t.elements.some(e=>e.style.fontId)?2:1,templates:{[_type]:t}},new Set([...Object.keys(r.fonts??{}),...(r.registeredIds??[])]));
  const doc=await PDFDocument.create();doc.registerFontkit(fontkit);
  const embedded=new Map<string,any>();const page=doc.addPage([t.page.width,t.page.height]);const warnings:string[]=[];
  const color=(hex:string)=>rgb(...([0,2,4].map(i=>parseInt(hex.slice(i,i+2),16)/255) as [number,number,number]));
  const image=async(bytes:Uint8Array,b:any)=>{
    const img=bytes[0]===137?await doc.embedPng(bytes):await doc.embedJpg(bytes);
    const scale=Math.min(b.width/img.width,b.height/img.height);
    page.drawImage(img,{x:b.x+(b.width-img.width*scale)/2,y:b.y+(b.height-img.height*scale)/2,width:img.width*scale,height:img.height*scale});
  };
  const area=pdfBox(t,{x:0,y:0,width:t.ticketArea.width,height:t.ticketArea.height});
  if(t.canvasColor!=='transparent'&&(t.canvasOpacity??1)>0)page.drawRectangle({...area,color:t.canvasColor?color(t.canvasColor):rgb(.9,.9,.9),opacity:t.canvasOpacity??1});
  if(r.background) {
    const prepared=r.preparedBackground;
    const img=prepared?null:r.background[0]===137?await doc.embedPng(r.background):await doc.embedJpg(r.background);
    const width=prepared?.width??img!.width;const height=prepared?.height??img!.height;
    page.pushOperators(pushGraphicsState(),rectangle(area.x,area.y,area.width,area.height),clip(),endPath());
    const crop=pdfBox(t,croppedBackgroundBox(t,width,height));
    page.pushOperators(rectangle(crop.x,crop.y,crop.width,crop.height),clip(),endPath());
    const box=pdfBox(t,backgroundBox(t,width,height));
    if(prepared)await prepared.draw(doc,page,box);else page.drawImage(img!,box);
    page.pushOperators(popGraphicsState());
  }
  if(t.border)page.drawRectangle({...area,borderColor:rgb(224/255,224/255,224/255),borderWidth:1,borderDashArray:[3.75,1.25]});
  for(const e of positionedElements(t,data).filter(e=>e.visible && e.binding!=='qr')) {
    const b=pdfBox(t,e.box);
    if(e.binding==='logo') {if(r.logo)await image(r.logo,b);continue;}
    const text=data[e.binding];if(!text)continue;
    const id=effectiveFontId(t,e);const resource=r.fonts?.[id]??(!t.fontId&&!e.style.fontId?{bytes:r.font,metrics:r.metrics}:undefined);
    if(!resource)throw new Error('font_resource_missing');let font=embedded.get(id);if(!font){font=await doc.embedFont(resource.bytes);embedded.set(id,font);}const metrics=resource.metrics;
    const fit=fitText(text,e,metrics);if(fit.overflow||fit.replaced)warnings.push(e.binding);
    page.pushOperators(pushGraphicsState(),rectangle(b.x,b.y,b.width,b.height),clip(),endPath());
    fit.lines.forEach((line,i)=>{
      let x=b.x+(e.style.align==='center'?(b.width-fit.widths[i])/2:e.style.align==='right'?b.width-fit.widths[i]:0);
      x+=textInsets(e,metrics).left*fit.size;
      const start=x;
      const y=t.page.height-t.ticketArea.y-e.box.y-metrics.ascent*fit.size-i*fit.size*1.2;
      const ink=color(e.style.color);
      page.pushOperators(pushGraphicsState(),setLineWidth(fit.size*.04),
        setStrokingRgbColor(ink.red,ink.green,ink.blue),
        setTextRenderingMode(e.style.bold?TextRenderingMode.FillAndOutline:TextRenderingMode.Fill));
      for(const c of Array.from(line)) {page.drawText(c,{x,y,size:fit.size,font,color:ink,ySkew:degrees(e.style.italic?12:0)});x+=(metrics.advances[c]??metrics.advances['?'])*fit.size;}
      page.pushOperators(popGraphicsState());
      if(e.style.underline)page.drawLine({start:{x:start,y:y-fit.size*.1},end:{x,y:y-fit.size*.1},thickness:fit.size*.05,color:ink});
    });
    page.pushOperators(popGraphicsState());
  }
  const q=t.elements.find(e=>e.binding==='qr')!;const b=pdfBox(t,q.box);
  const qr=QRCode.create(data.qr!,{errorCorrectionLevel:'M'}).modules;
  const margin=t.qrAppearance?.margin??4;
  const module=b.width/(qr.size+2*margin);if(module<1.2)throw new Error('QR modules are too small for print');
  page.drawRectangle({...b,color:color(t.qrAppearance?.background??'FFFFFF'),opacity:t.qrAppearance?.opacity??1});
  for(let y=0;y<qr.size;y++)for(let x=0;x<qr.size;x++)if(qr.get(y,x))page.drawRectangle({x:b.x+(x+margin)*module,y:b.y+b.height-(y+margin+1)*module,width:module,height:module,color:color(q.style.color)});
  // Preview status belongs to the editor chrome, not the printed artwork.
  return {bytes:await doc.save(),warnings};
}
