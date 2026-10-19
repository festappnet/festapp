import * as fontkit from 'npm:fontkit';
import {digest,TicketFontError,type TicketFont} from './ticketFonts.ts';

/** A derived view of the existing immutable ticket font, never a second catalog. */
export async function layoutFontOutline(font:TicketFont,characters:string) {
  if(typeof characters!=='string'||[...characters].length>4096)throw new TicketFontError('font_characters_limit');
  const hash=await digest(font.bytes);
  if(!font.id.endsWith(`:${hash}`))throw new TicketFontError('font_integrity');
  const parsed=fontkit.create(font.bytes);
  const points=new Set([...Array.from({length:560},(_,i)=>String.fromCodePoint(i+32)),...characters,'?']);
  const glyphs:Record<string,{advance:number,path:(string|number)[][]}>={};
  const commands:Record<string,string>={moveTo:'M',lineTo:'L',quadraticCurveTo:'Q',bezierCurveTo:'C',closePath:'Z'};
  let totalCommands=0;
  for(const character of points){
    const cp=character.codePointAt(0)!;
    if(!parsed.hasGlyphForCodePoint(cp))continue;
    const glyph=parsed.glyphForCodePoint(cp);
    const path=glyph.path.commands.map((c:{command:string,args:number[]})=>{
      const op=commands[c.command];
      if(!op||c.args.some(v=>!Number.isFinite(v)))throw new TicketFontError('font_outline_invalid');
      return [op,...c.args.map(v=>Math.round(v*100000)/100000)];
    });
    totalCommands+=path.length;
    if(totalCommands>200000)throw new TicketFontError('font_outline_limit');
    glyphs[character]={advance:glyph.advanceWidth,path};
  }
  return {id:font.id,hash,family:font.family,unitsPerEm:parsed.unitsPerEm,ascent:parsed.ascent,descent:parsed.descent,glyphs};
}
