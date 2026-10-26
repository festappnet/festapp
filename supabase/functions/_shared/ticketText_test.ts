import {assert,assertEquals} from 'jsr:@std/assert@1';
import {fitText} from './ticketText.ts';
import type {Element} from './ticketLayout.ts';
const metrics={ascent:.8,descent:-.2,advances:Object.fromEntries(Array.from('Slavnostnívečer PřílišDlouhéBezMez…?').map(c=>[c,.5]))};
const title:Element={id:'title',binding:'occasionTitle',box:{x:0,y:0,width:90,height:180},visible:true,locked:false,style:{fontSize:32,minFontSize:6,maxLines:4,color:'222222',align:'left'}};
Deno.test('long title words shrink instead of breaking across lines',()=>{
 const fit=fitText('Slavnostní večer',title,metrics);
 assert(fit.size<32,'The long word must reduce the font before wrapping');
 assertEquals(fit.lines,['Slavnostní','večer']);
 assertEquals(fit.overflow,false);
});
Deno.test('title auto fit preserves the whole title beyond its preferred minimum',()=>{
 const text='PřílišDlouhéSlovoBezMezer';
 const fit=fitText(text,{...title,box:{...title.box,width:50,height:20},style:{...title.style,minFontSize:18,maxLines:1}},metrics);
 assertEquals(fit.lines,[text]);assert(fit.size<18);assertEquals(fit.overflow,false);
});
Deno.test('explicit title newlines remain line boundaries',()=>{
 assertEquals(fitText('Slavnostní\nvečer',title,metrics).lines,['Slavnostní','večer']);
});
