import policy from './layout-text-policy.json' with {type:'json'};
// @ts-types="./vendor/harfbuzzjs/index.d.mts"
import * as hb from './vendor/harfbuzzjs/index.mjs';
import {digest,TicketFontError,type TicketFont} from './ticketFonts.ts';

/** Immutable preparation identity. Never choose an engine from request data. */
export const layoutTextEngine = Object.freeze(policy.engine);

export interface LayoutRunPolicy {
  direction:'ltr'|'rtl'; script:string; language:string;
  /** Numeric notation is the only role disabling contextual font features. */
  numeric?:boolean;
}
export interface LayoutGlyph {
  glyphId:number; cluster:number; xAdvance:number; yAdvance:number;
  xOffset:number; yOffset:number;
}
export type LayoutGlyphPath = Array<Array<string|number>>;

/** UTF-16 native input indices to original UTF-8 byte offsets; no normalization.
 * Surrogate interiors are absent. Offsets cannot point inside a code point.
 */
export function layoutTextOffsets(text:string):Map<number,number> {
  const result=new Map<number,number>();let u16=0,u8=0;
  for(const cp of text){
    const scalar=cp.codePointAt(0)!;
    if(scalar>=0xd800&&scalar<=0xdfff)throw new TicketFontError('layout_text_invalid_unicode');
    result.set(u16,u8);u16+=cp.length;u8+=scalar<0x80?1:scalar<0x800?2:scalar<0x10000?3:4;
  }
  result.set(u16,u8);return result;
}

/** The sole Blueprint shaping backend. Font bytes come from the existing
 * authorized TicketFontResolver; callers never fetch a system/CDN substitute.
 * One face instance is reused within a bounded preparation batch.
 */
export class LayoutTextFace {
  private constructor(readonly id:string,private font:hb.Font,readonly unitsPerEm:number,
    readonly ascent:number,readonly descent:number) {}
  static async fromTicketFont(font:TicketFont):Promise<LayoutTextFace> {
    if(await digest(font.bytes)!==font.id.split(':').at(-1))throw new TicketFontError('font_integrity');
    if(hb.versionString()!==layoutTextEngine.version)throw new TicketFontError('layout_engine_version');
    const blob=new hb.Blob(font.bytes.slice().buffer),face=new hb.Face(blob),parsed=new hb.Font(face);
    if(['fvar','COLR','CBDT','sbix','SVG '].some(tag=>face.referenceTable(tag)!==undefined))throw new TicketFontError('font_unsupported');
    const extents=parsed.hExtents();
    if(!Number.isFinite(face.upem)||face.upem<=0||!extents||![extents.ascender,extents.descender].every(Number.isFinite))throw new TicketFontError('font_metrics_invalid');
    return new LayoutTextFace(font.id,parsed,face.upem,extents.ascender,extents.descender);
  }
  shape(text:string,policy:LayoutRunPolicy):LayoutGlyph[] {
    if(typeof text!=='string'||[...text].length>4096)throw new TicketFontError('font_characters_limit');
    if(!['ltr','rtl'].includes(policy.direction)||!/^[A-Za-z]{4}$/.test(policy.script)||!/^([A-Za-z]{2,8})(-[A-Za-z0-9]{1,8})*$/.test(policy.language))throw new TicketFontError('layout_text_policy');
    if(policy.numeric&&!/^[×0-9]*$/.test(text))throw new TicketFontError('layout_numeric_text');
    const offsets=layoutTextOffsets(text),buffer=new hb.Buffer();
    buffer.addText(text);buffer.setDirection(policy.direction==='rtl'?hb.Direction.RTL:hb.Direction.LTR);
    buffer.setScript(policy.script);buffer.setLanguage(policy.language);buffer.setClusterLevel(hb.ClusterLevel.MONOTONE_GRAPHEMES);
    hb.shape(this.font,buffer,policy.numeric?['kern=0','liga=0','clig=0','calt=0'].map(s=>hb.Feature.fromString(s)!):undefined);
    const positions=buffer.getGlyphPositions();
    return buffer.getGlyphInfos().map((g,i)=>{
      if(g.codepoint===0)throw new TicketFontError('layout_glyph_unavailable');
      const cluster=offsets.get(g.cluster),p=positions[i];
      if(cluster===undefined||[p.xAdvance,p.yAdvance,p.xOffset,p.yOffset].some(v=>!Number.isFinite(v)))throw new TicketFontError('layout_shaping_invalid');
      return {glyphId:g.codepoint,cluster,xAdvance:p.xAdvance,yAdvance:p.yAdvance,xOffset:p.xOffset,yOffset:p.yOffset};
    });
  }
  /** A whole logical run becomes one vector path. Glyph cache saves outlines;
   * advances and offsets still come exclusively from contextual shaping.
   * Coordinates are font units, y-down, with the baseline at (0, 0).
   */
  vector(text:string,policy:LayoutRunPolicy) {
    const glyphs=this.shape(text,policy),out:LayoutGlyphPath=[],paths=new Map<number,LayoutGlyphPath>();
    let x=0,y=0,left=Infinity,top=Infinity,right=-Infinity,bottom=-Infinity;
    for(const g of glyphs){
      let path=paths.get(g.glyphId);
      if(!path){path=this.path(g.glyphId);paths.set(g.glyphId,path);}
      const gx=x+g.xOffset,gy=y+g.yOffset;
      for(const command of path){
        const placed:Array<string|number>=[command[0]];
        for(let i=1;i<command.length;i+=2)placed.push(gx+(command[i] as number),-gy-(command[i+1] as number));
        out.push(placed);
      }
      if(path.length){
        const b=this.bounds(g.glyphId);
        left=Math.min(left,gx+b.x);top=Math.min(top,-gy-b.y);
        right=Math.max(right,gx+b.x+b.width);bottom=Math.max(bottom,-gy-b.y-b.height);
      }
      x+=g.xAdvance;y+=g.yAdvance;
    }
    return {glyphs,path:out,advance:{x,y:-y},inkBounds:Number.isFinite(left)?{x:left,y:top,width:right-left,height:bottom-top}:{x:0,y:0,width:0,height:0}};
  }
  path(glyphId:number):LayoutGlyphPath {
    if(!Number.isInteger(glyphId)||glyphId<1)throw new TicketFontError('layout_glyph_unavailable');
    return this.font.glyphToJson(glyphId).map(c=>{
      if(!['M','L','Q','C','Z'].includes(c.type)||c.values.some(v=>!Number.isFinite(v)))throw new TicketFontError('font_outline_invalid');
      return [c.type,...c.values];
    });
  }
  bounds(glyphId:number) {
    const extents=this.font.glyphExtents(glyphId);
    if(!extents)throw new TicketFontError('font_outline_invalid');
    return {x:extents.xBearing,y:extents.yBearing,width:extents.width,height:extents.height};
  }
}
