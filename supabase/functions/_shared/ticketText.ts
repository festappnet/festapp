import type { Element } from './ticketLayout.ts';
export interface FontMetrics { advances: Record<string,number>; ascent:number; descent:number }
// Match the Canvas outline width and 12-degree shear using the bundled font.
export function textInsets(e:Element,m:FontMetrics) {
  return {left:(e.style.bold? .02:0)+(e.style.italic?-m.descent*.2125565616700221:0),
    right:(e.style.bold? .02:0)+(e.style.italic?m.ascent*.2125565616700221:0)};
}
export function fitText(text:string,e:Element,m:FontMetrics) {
  const replaced=Array.from(text).some(c=>c!=='\n' && m.advances[c]===undefined);
  text=Array.from(text).map(c=>c==='\n'||m.advances[c]!==undefined?c:'?').join('');
  const inset=textInsets(e,m);
  const width=(s:string,size:number)=> (s.length?(inset.left+inset.right)*size:0)+Array.from(s).reduce((n,c)=>n+(m.advances[c]??m.advances['?'])*size,0);
  const wrap=(size:number)=>{
    const lines:string[]=[];let line='';
    for(const c of Array.from(text)) {
      if(c==='\n') { lines.push(line);line='';continue; }
      if(width(line+c,size)>e.box.width && line) {
        const split=line.lastIndexOf(' ');
        if(split>0) {lines.push(line.slice(0,split));line=line.slice(split+1)+c;}
        else {lines.push(line);line=c;}
      } else line+=c;
    }
    if(line)lines.push(line.trimEnd());return lines;
  };
  let size=e.style.fontSize, lines=wrap(size);
  const fits=()=>lines.length<=e.style.maxLines && (!lines.length || ((lines.length-1)*1.2+m.ascent-m.descent)*size<=e.box.height) && lines.every(l=>width(l,size)<=e.box.width+.001);
  while(!fits() && size>e.style.minFontSize) {size=Math.max(e.style.minFontSize,size-.5);lines=wrap(size);}
  const overflow=!fits();
  if(overflow && e.binding==='ticketSymbol') throw new Error('Ticket symbol does not fit');
  if(overflow) {
    lines=lines.slice(0,Math.max(0,Math.min(e.style.maxLines,Math.floor((e.box.height/size-m.ascent+m.descent)/1.2)+1)));
    if(lines.length && width('…',size)<=e.box.width) {let last=lines.pop()||'';while(last && width(last+'…',size)>e.box.width)last=Array.from(last).slice(0,-1).join('');lines.push(last+'…');} else lines=[];
  }
  return {size,lines,overflow,replaced,widths:lines.map(l=>width(l,size))};
}
