import policy from './layout-text-policy.json' with {type:'json'};
import bidiFactory from 'npm:bidi-js@1.1.0/dist/bidi.mjs';
import LineBreaker from 'npm:linebreak@1.1.0';
import {graphemeSegments} from 'npm:unicode-segmenter@0.17.3/grapheme';
import * as unicode from 'npm:unicode-properties@2.0.1';
import aliases from 'npm:unicode-match-property-value-ecmascript@2.2.1/data/mappings.js';
import {LayoutTextFace,layoutTextEngine,layoutTextOffsets,type LayoutGlyphPath} from './layoutTextShaper.ts';
import {digest,TicketFontError} from './ticketFonts.ts';

export const layoutResourceProtocol=2;
export const layoutTextPreparationPolicy=Object.freeze(policy);

export interface LayoutTextRequest {
  text:string; role:'text'|'label'; fontFamilyId:string; fontFaceId:string;
  size:number; language:string; direction:'auto'|'ltr'|'rtl';
  lineHeight:number; align:'left'|'center'|'right';
  box:{x:number;y:number;width:number;height:number}; fit:'wrap'|'shrink';
}
const bidi=bidiFactory();
const scriptTags=new Map<string,string>([...aliases.get('Script')].filter(([tag]:[string,string])=>tag.length===4).map(([tag,name]:[string,string])=>[name.replaceAll('_',''),tag]));
const neutral=new Set(['Common','Inherited']);
const keys=['text','role','fontFamilyId','fontFaceId','size','language','direction','lineHeight','align','box','fit'];
function invalid(code='layout_text_request'):never {throw new TicketFontError(code);}
export function canonicalLayoutResourceJson(value:unknown):string {
 function encode(v:unknown):string {
  if(Array.isArray(v))return '['+v.map(encode).join(',')+']';
  if(v&&typeof v==='object')return '{'+Object.entries(v).sort(([a],[b])=>a<b?-1:a>b?1:0).map(([k,x])=>JSON.stringify(k)+':'+encode(x)).join(',')+'}';
  if(typeof v==='number'){
   if(!Number.isFinite(v))invalid();if(v===0)return '0';
   const source=v.toString().toLowerCase();if(!source.includes('e'))return source;
   const [raw,exp]=source.split('e'),exponent=Number(exp),sign=raw.startsWith('-')?'-':'',mantissa=sign?raw.slice(1):raw;
   const dot=mantissa.indexOf('.'),digits=mantissa.replace('.',''),at=(dot<0?mantissa.length:dot)+exponent;
   let text=at<=0?'0.'+'0'.repeat(-at)+digits:at>=digits.length?digits+'0'.repeat(at-digits.length):digits.slice(0,at)+'.'+digits.slice(at);
   if(text.includes('.'))text=text.replace(/0+$/,'').replace(/\.$/,'');return sign+text;
  }
  if(v===null||typeof v==='string'||typeof v==='boolean')return JSON.stringify(v);
  return invalid('layout_resource_non_json');
 }
 return encode(value);
}

function validate(request:LayoutTextRequest,face:LayoutTextFace) {
  if(!request||Object.keys(request).some(k=>!keys.includes(k))||keys.some(k=>!(k in request)))invalid();
  if(typeof request.text!=='string'||[...request.text].length>4096||request.fontFaceId!==face.id||typeof request.fontFamilyId!=='string'||!request.fontFamilyId)invalid();
  layoutTextOffsets(request.text);
  if(!['text','label'].includes(request.role)||!['auto','ltr','rtl'].includes(request.direction)||!['wrap','shrink'].includes(request.fit)||!['left','center','right'].includes(request.align))invalid();
  if(!Number.isFinite(request.size)||request.size<1||request.size>4096||!Number.isFinite(request.lineHeight)||request.lineHeight<.8||request.lineHeight>3)invalid();
  if(typeof request.language!=='string'||!/^([A-Za-z]{2,8})(-[A-Za-z0-9]{1,8})*$/.test(request.language))invalid();
  if(!request.box||Object.keys(request.box).sort().join(',')!=='height,width,x,y'||Object.values(request.box).some(v=>!Number.isFinite(v)||Math.abs(v)>1e9)||request.box.width<=0||request.box.height<=0)invalid();
}

/** Ordinary editable source text -> contextually shaped lines -> one vector.
 * Paragraph bidi, graphemes and break opportunities use pinned libraries; no
 * native browser/Flutter text measurement can affect this immutable result.
 */
export async function prepareLayoutText(face:LayoutTextFace,request:LayoutTextRequest) {
  validate(request,face);
  // Capture before any await. Neither caller mutation nor camera enters identity.
  request=JSON.parse(canonicalLayoutResourceJson(request));
  const sourceOffsets=layoutTextOffsets(request.text),scale=request.size/face.unitsPerEm;
  const lines:Array<{start:number;end:number;path:LayoutGlyphPath;advance:number;glyphs:Array<Record<string,number|string>>;ink:{left:number;top:number;right:number;bottom:number}}>=[];
  let paragraphStart=0;
  const separators=[...request.text.matchAll(/\r\n|[\n\r\u0085\u2028\u2029]/g)];
  const paragraphs=separators.map(s=>{const p={start:paragraphStart,end:s.index!};paragraphStart=s.index!+s[0].length;return p;});
  paragraphs.push({start:paragraphStart,end:request.text.length});
  for(const paragraph of paragraphs){
    const text=request.text.slice(paragraph.start,paragraph.end);
    const embedding=bidi.getEmbeddingLevels(text,request.direction==='auto'?undefined:request.direction);
    const clusters=[...graphemeSegments(text)].map(g=>({start:g.index,end:g.index+g.segment.length,script:unicode.getScript(g.segment.codePointAt(0)!)}));
    // Neutral/inherited graphemes adopt their adjacent script without splitting
    // combining clusters or shaping separate Unicode characters.
    let previous='';
    for(const g of clusters){if(!neutral.has(g.script)&&g.script!=='Unknown')previous=g.script;else if(previous)g.script=previous;}
    let next='Common';
    for(let i=clusters.length-1;i>=0;i--){if(!neutral.has(clusters[i].script)&&clusters[i].script!=='Unknown')next=clusters[i].script;else clusters[i].script=next;}
    function shapeLine(start:number,end:number) {
      const runs:Array<{start:number;end:number;level:number;script:string}>=[];
      for(const g of clusters){
        if(g.start<start||g.start>=end)continue;
        const level=embedding.levels[g.start],script=scriptTags.get(g.script.replaceAll('_',''));
        if(!script||g.script==='Unknown')invalid('layout_script_unsupported');
        const prior=runs.at(-1);
        if(prior&&prior.level===level&&prior.script===script)prior.end=g.end;
        else runs.push({start:g.start,end:g.end,level,script});
      }
      const byOffset=new Map<number,number>();runs.forEach((r,i)=>{for(let p=r.start;p<r.end;p++)byOffset.set(p,i);});
      const order:number[]=[];
      if(start<end)for(const offset of bidi.getReorderedIndices(text,embedding,start,end-1)){
        const i=byOffset.get(offset);if(i!==undefined&&order.at(-1)!==i)order.push(i);
      }
      const path:LayoutGlyphPath=[],glyphs:Array<Record<string,number|string>>=[];
      let advance=0,left=0,top=0,right=0,bottom=0;
      for(const index of order){
        const run=runs[index],direction=run.level%2?'rtl':'ltr';
        const shaped=face.vector(text.slice(run.start,run.end),{direction,script:run.script,language:request.language});
        for(const command of shaped.path){const placed:Array<string|number>=[command[0]];for(let k=1;k<command.length;k+=2)placed.push(advance+(command[k] as number),command[k+1] as number);path.push(placed);}
        const b=shaped.inkBounds;
        if(shaped.path.length){left=Math.min(left,advance+b.x);top=Math.min(top,b.y);right=Math.max(right,advance+b.x+b.width);bottom=Math.max(bottom,b.y+b.height);}
        const base=sourceOffsets.get(paragraph.start+run.start)!;
        for(const g of shaped.glyphs)glyphs.push({...g,cluster:g.cluster+base,runX:advance,direction,script:run.script,runStart:base,runEnd:sourceOffsets.get(paragraph.start+run.end)!});
        advance+=shaped.advance.x;
      }
      return {start:paragraph.start+start,end:paragraph.start+end,path,glyphs,advance,ink:{left,top,right:Math.max(right,advance),bottom}};
    }
    if(request.fit==='shrink'||!text.length){lines.push(shapeLine(0,text.length));continue;}
    const breaker=new LineBreaker(text),breaks:number[]=[];let b;
    while((b=breaker.nextBreak()))breaks.push(b.position);
    if(breaks.at(-1)!==text.length)breaks.push(text.length);
    let start=0,lastFit:ReturnType<typeof shapeLine>|undefined;
    for(let i=0;i<breaks.length;i++){
      const candidate=shapeLine(start,breaks[i]);
      if((candidate.ink.right-candidate.ink.left)*scale<=request.box.width){lastFit=candidate;continue;}
      if(lastFit){lines.push(lastFit);start=lastFit.end-paragraph.start;lastFit=undefined;i--;}
      else {lines.push(candidate);start=breaks[i];}
    }
    if(lastFit)lines.push(lastFit);
  }
  const lineStep=request.size*request.lineHeight;
  const baseline=Math.max(face.ascent,...lines.map(l=>-l.ink.top))*scale;
  const naturalWidth=Math.max(0,...lines.map(l=>(l.ink.right-l.ink.left)*scale));
  const naturalHeight=Math.max(lineStep*lines.length,baseline+(lines.length-1)*lineStep+Math.max(0,...lines.map(l=>l.ink.bottom))*scale);
  const fitScale=request.fit==='shrink'?Math.min(1,request.box.width/Math.max(naturalWidth,1),request.box.height/Math.max(naturalHeight,1)):1;
  const path:LayoutGlyphPath=[],positionedLines=[];
  for(let i=0;i<lines.length;i++){
    const line=lines[i],width=(line.ink.right-line.ink.left)*scale*fitScale;
    const x=request.box.x-line.ink.left*scale*fitScale+(request.align==='center'?(request.box.width-width)/2:request.align==='right'?request.box.width-width:0);
    const y=request.box.y+(request.fit==='shrink'?(request.box.height-naturalHeight*fitScale)/2:0)+(baseline+i*lineStep)*fitScale;
    for(const command of line.path){const placed:Array<string|number>=[command[0]];for(let k=1;k<command.length;k+=2)placed.push(x+(command[k] as number)*scale*fitScale,y+(command[k+1] as number)*scale*fitScale);path.push(placed);}
    positionedLines.push({start:sourceOffsets.get(line.start),end:sourceOffsets.get(line.end),x,baseline:y,advance:line.advance*scale*fitScale,glyphs:line.glyphs});
  }
  if(path.length>200000)invalid('font_outline_limit');
  const descriptor={layoutResourceProtocol,policy:layoutTextPreparationPolicy,request};
  const id='layout-text:'+await digest(new TextEncoder().encode(canonicalLayoutResourceJson(descriptor)));
  return {id,descriptor,lines:positionedLines,path,fitScale,clip:request.box,advanceBounds:{width:naturalWidth*fitScale,height:naturalHeight*fitScale}};
}

/** A count uses a fixed closed alphabet. Authored text always uses full paragraph
 * shaping above; numeric symbols alone disable contextual features. */
export async function prepareLayoutNumberSymbols(face:LayoutTextFace){
 const tokens:Record<string,{path:LayoutGlyphPath;advance:number}>={};
 for(const char of '×0123456789'){
  const vector=face.vector(char,{direction:'ltr',script:'Latn',language:'und',numeric:true});
  tokens[char]={path:vector.path,advance:vector.advance.x};
 }
 const descriptor={layoutResourceProtocol,policy:layoutTextPreparationPolicy,role:'number',fontFaceId:face.id};
 const id='layout-number:'+await digest(new TextEncoder().encode(canonicalLayoutResourceJson(descriptor)));
 return {id,descriptor,fontFaceId:face.id,unitsPerEm:face.unitsPerEm,tokens};
}
