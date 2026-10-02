import { validateLayout, pdfBox, positionedElements, type Template } from './ticketLayout.ts';
import { fitText, textInsets } from './ticketText.ts';
import type { RenderData } from './ticketRenderData.ts';
import type { Resources } from './ticketGeneration.ts';
import QRCode from "npm:qrcode";
import { PDFDocument, rgb, degrees, pushGraphicsState, popGraphicsState, rectangle, clip, endPath, setLineWidth, setTextRenderingMode, TextRenderingMode, setStrokingRgbColor } from "npm:pdf-lib";
// Import all exports from fontkit (do not try to import a default)
import * as fontkit from "npm:fontkit";

export async function drawLayoutTicket(data:RenderData,r:Resources,t:Template,_type:'wide'|'named'=t.page.width===595.28?'wide':'named',_sample=false) {
  validateLayout({schemaVersion:1,templates:{[_type]:t}});
  const doc=await PDFDocument.create();doc.registerFontkit(fontkit);
  const font=await doc.embedFont(r.font);const page=doc.addPage([t.page.width,t.page.height]);const warnings:string[]=[];
  const color=(hex:string)=>rgb(...([0,2,4].map(i=>parseInt(hex.slice(i,i+2),16)/255) as [number,number,number]));
  const image=async(bytes:Uint8Array,b:any)=>{
    const img=bytes[0]===137?await doc.embedPng(bytes):await doc.embedJpg(bytes);
    const scale=Math.min(b.width/img.width,b.height/img.height);
    page.drawImage(img,{x:b.x+(b.width-img.width*scale)/2,y:b.y+(b.height-img.height*scale)/2,width:img.width*scale,height:img.height*scale});
  };
  const area=pdfBox(t,{x:0,y:0,width:t.ticketArea.width,height:t.ticketArea.height});
  page.drawRectangle({...area,color:rgb(.9,.9,.9)});
  if(r.background)await image(r.background,area);
  if(t.border)page.drawRectangle({...area,borderColor:rgb(224/255,224/255,224/255),borderWidth:1,borderDashArray:[3.75,1.25]});
  for(const e of positionedElements(t,data).filter(e=>e.visible && e.binding!=='qr')) {
    const b=pdfBox(t,e.box);
    if(e.binding==='logo') {if(r.logo)await image(r.logo,b);continue;}
    const text=data[e.binding];if(!text)continue;
    const fit=fitText(text,e,r.metrics);if(fit.overflow||fit.replaced)warnings.push(e.binding);
    page.pushOperators(pushGraphicsState(),rectangle(b.x,b.y,b.width,b.height),clip(),endPath());
    fit.lines.forEach((line,i)=>{
      let x=b.x+(e.style.align==='center'?(b.width-fit.widths[i])/2:e.style.align==='right'?b.width-fit.widths[i]:0);
      x+=textInsets(e,r.metrics).left*fit.size;
      const start=x;
      const y=t.page.height-t.ticketArea.y-e.box.y-r.metrics.ascent*fit.size-i*fit.size*1.2;
      const ink=color(e.style.color);
      page.pushOperators(pushGraphicsState(),setLineWidth(fit.size*.04),
        setStrokingRgbColor(ink.red,ink.green,ink.blue),
        setTextRenderingMode(e.style.bold?TextRenderingMode.FillAndOutline:TextRenderingMode.Fill));
      for(const c of Array.from(line)) {page.drawText(c,{x,y,size:fit.size,font,color:ink,ySkew:degrees(e.style.italic?12:0)});x+=(r.metrics.advances[c]??r.metrics.advances['?'])*fit.size;}
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
