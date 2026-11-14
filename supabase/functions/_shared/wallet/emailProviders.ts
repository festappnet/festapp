import {walletPresentation} from './presentation.js';
/** Email composition uses public metadata and independently verified published assets. */
type Presentation={labels:Record<string,string>;widths:Record<string,number>;badges:Record<string,string>;emailWidths?:Record<string,number>;emailBadges?:Record<string,string>};
const presentation:Record<string,Presentation>=walletPresentation;
const {google,apple}=presentation;
/** Draft previews use the same installed public artwork, without customer capabilities. */
export function walletPreviewBadge(provider:string,locale:string){
 const descriptor=presentation[provider];return descriptor?.badges[locale]??descriptor?.badges.en;
}
type Artwork={url:string;width:number};
export const walletEmailProviders:Record<string,{labels:Record<string,string>;artwork:(badge:string|undefined,locale:string)=>Artwork|undefined;badge:(urls:any,locale:string)=>string|undefined;labelFallback:boolean}>={
 google:{labels:google.labels,labelFallback:true,badge:(urls,locale)=>{
  const badge=urls?.[locale];
  return typeof badge==='string'&&badge===google.badges[locale]?badge:undefined;
 },artwork:(badge,locale)=>{
  const url=google.emailBadges?.[locale],width=google.emailWidths?.[locale];
  return badge===google.badges[locale]&&url&&width?{url,width}:undefined;
 }},
 apple:{labels:apple.labels,labelFallback:true,badge:(urls,locale)=>{
  const installed=Object.hasOwn(apple.badges,locale)?locale:'en';
  const badge=urls?.apple?.[installed];
  return typeof badge==='string'&&badge===apple.badges[installed]?badge:undefined;
 },artwork:(badge,locale)=>{
  const installed=Object.hasOwn(apple.badges,locale)?locale:'en';
  const width=apple.widths[installed];
  return badge&&badge===apple.badges[installed]&&width?{url:badge,width}:undefined;
 }},
};
