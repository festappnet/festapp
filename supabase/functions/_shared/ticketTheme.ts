import {ticketThemeColor,themedTicketArtwork,ticketThemePalettes} from './ticketThemePalette.js';
import {legacyFontIds} from './ticketFonts.ts';
import type {Template} from './ticketLayout.ts';
export {ticketThemeColor,ticketThemePalettes};
const root='https://img.festapp.net/ticket-presets/v1/';
export function themedTicketBackground(key:string,primary:string,secondary:string,original:string|null):string|null {
 return themedTicketArtwork.includes(key.replaceAll('_','-'))
  ? `${root}palette-${primary}-${secondary}-${key}-v1.png`:original;
}
export function themeTicketTemplate(raw:Template,primary:string,secondary:string,fontId:string,key:string):Template {
 const t=structuredClone(raw), color=(hex:string)=>ticketThemeColor(hex,primary,secondary);
 t.fontId=fontId;
 if(t.canvasColor&&t.canvasColor!=='transparent')t.canvasColor=color(t.canvasColor);
 if(t.canvasGradient)t.canvasGradient=t.canvasGradient.map(color);
 t.qrAppearance={background:'FFFFFF',opacity:1,margin:4};
 for(const e of t.elements) {
  delete e.style.fontId;
  e.style.color=e.binding==='qr'?'000000':ticketThemeColor(e.style.color,'222222','222222');
  if(['silk_light','ball_silk'].includes(key)&&e.binding!=='qr')e.style.color='222222';
  if(key==='silk_dark'&&e.binding!=='qr')e.style.color='F5F5F5';
 }
 return t;
}
export const ticketThemeFonts:Record<string,string>={clean:legacyFontIds.roboto,gala:legacyFontIds.robotoSlab,energy:legacyFontIds.russoOne,nature:legacyFontIds.roboto,soft:legacyFontIds.robotoSlab,contrast:legacyFontIds.roboto};
