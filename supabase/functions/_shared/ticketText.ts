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
    const lines:string[]=[], paragraphs=text.split('\n');
    for(let i=0;i<paragraphs.length;i++) {
      let line='';
      for(const token of paragraphs[i].match(/[^ ]+| +/g)??[]) {
        if(token.startsWith(' ')){line+=token;continue;}
        if(line.trim() && width(line+token,size)>e.box.width) {
          lines.push(line.trimEnd());line=token;
        } else line+=token;
      }
      if(line||i<paragraphs.length-1)lines.push(line.trimEnd());
    }
    return lines;
  };
  let size=e.style.fontSize, lines=wrap(size);
  const fits=()=>lines.length<=e.style.maxLines && (!lines.length || ((lines.length-1)*1.2+m.ascent-m.descent)*size<=e.box.height) && lines.every(l=>width(l,size)<=e.box.width+.001);
  // A title's minimum is a preferred size, never a reason to cut its words.
  const minimum=e.binding==='occasionTitle'?Math.min(e.style.minFontSize,.1):e.style.minFontSize;
  while(!fits() && size>minimum) {size=Math.max(minimum,size-.5);lines=wrap(size);}
  const overflow=!fits();
  if(overflow && e.binding==='ticketSymbol') throw new Error('Ticket symbol does not fit');
  if(overflow) {
    lines=lines.slice(0,Math.max(0,Math.min(e.style.maxLines,Math.floor((e.box.height/size-m.ascent+m.descent)/1.2)+1)));
    if(lines.length && width('…',size)<=e.box.width) {lines=lines.map((line,i)=>{if(i<lines.length-1&&width(line,size)<=e.box.width)return line;while(line&&width(line+'…',size)>e.box.width)line=Array.from(line).slice(0,-1).join('');return line+'…';});} else lines=[];
  }
  return {size,lines,overflow,replaced,widths:lines.map(l=>width(l,size))};
}
