// One-way import of the pre-editor feature contract. This module builds data,
// never PDFs. Saved editable templates always take precedence over import.
import { PDFDocument } from 'npm:pdf-lib';
import { type Binding, type Element, type Template, validateLayout, preset } from './ticketLayout.ts';
import type { Resources } from './ticketGeneration.ts';
export async function importTicketTemplate(occasion:any,r:Resources):Promise<Template> {
  const feature=occasion.features?.find((f:any)=>f.code==='ticket')??{};
  const named=feature.ticket_type==='named';
  const make=(binding:Binding,x:number,y:number,width:number,height:number,size:number,color:string,align:'left'|'center'='left',maxLines=1):Element=>({id:binding,binding,visible:true,locked:false,box:{x,y,width,height},style:{fontSize:size,minFontSize:Math.min(6,size),maxLines,color,align}});
  let t:Template;
  if(named) {
    const text=(b:Binding,baseline:number,size:number,height:number,color='2A2A2A',lines=1)=>make(b,6.25,baseline-r.metrics.ascent*size,187.5,height,size,color,'center',lines);
    t={font:occasion.data?.font?.includes('RussoOne-Regular')?'russoOne':'roboto',page:{width:212.5,height:387.5},ticketArea:{x:6.25,y:6.25,width:200,height:375},border:true,qrAppearance:{background:'FFFFFF',opacity:1,margin:1.875},elements:[
      make('logo',71.875,12.5,56.25,56.25,12,'2A2A2A'),
      text('occasionTitle',87.5,12.5,32,'2A2A2A',2),
      text('occasionDatePlace',115.625,8.75,24,'666666',2),
      text('orderName',168.75,12.5,24),
      make('qr',50,206.25,100,100,12,'2A2A2A'),
      text('ticketSymbol',318.75,8.75,18,'666666'),
      text('footer',371.875,6.25,3.125+r.metrics.ascent*6.25,'999999')
    ]};
  } else {
    if(!feature.background) return {...preset('wide',1600,900),font:'futura'};
    let width=1600,height=900;
    if(r.background){const doc=await PDFDocument.create();const image=r.background[0]===137?await doc.embedPng(r.background):await doc.embedJpg(r.background);width=image.width;height=image.height;}
    const scale=535.752/width,h=height*scale;
    const color=/^[a-fA-F0-9]{6}$/.test(feature.darkColor??'')?feature.darkColor:'000000';
    const background=/^[a-fA-F0-9]{6}$/.test(feature.lightColor??'')?feature.lightColor:'FFFFFF';
    const q=240*scale,qx=(width-390)*scale,qy=h-380*scale;
    const details:Binding[]=['spotGroup','food','note','price'];
    const fs=40*scale;
    t={font:'robotoSlab',page:{width:595.28,height:841.89},ticketArea:{x:29.764,y:29.764,width:535.752,height:h},flow:details,flowStep:50*scale,qrAppearance:{background,opacity:192/255,margin:1.6},elements:[
      make('qr',qx,qy,q,q,12,color),
      make('ticketSymbol',qx,h-102*scale-r.metrics.ascent*28*scale,q,38*scale,28*scale,color,'center'),
      ...details.map((b,i)=>make(b,150*scale,h-(280-i*50)*scale-r.metrics.ascent*fs,(width-570)*scale,Math.max(50*scale,(r.metrics.ascent-r.metrics.descent)*fs+.001),fs,color))
    ]};
  }
  const qr=t.elements.find(e=>e.binding==='qr')!;
  const fixed=(v:number)=>Math.round(v*1024)/1024;
  qr.box={x:fixed(qr.box.x),y:fixed(qr.box.y),width:fixed(qr.box.width),height:fixed(qr.box.width)};
  validateLayout({schemaVersion:1,templates:{[named?'named':'wide']:t}});
  return t;
}
