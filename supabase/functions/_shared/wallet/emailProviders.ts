import {walletPresentation} from './presentation.js';
/** Email composition uses public metadata and independently verified published assets. */
type Presentation={labels:Record<string,string>;widths:Record<string,number>;badges:Record<string,string>;emailWidths?:Record<string,number>;emailBadges?:Record<string,string>};
const presentation:Record<string,Presentation>=walletPresentation;
const {google,apple}=presentation;
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
  const badge=urls?.apple?.[locale];
  return typeof badge==='string'&&badge===apple.badges[locale]?badge:undefined;
 },artwork:(badge,locale)=>{
  const width=apple.widths[locale];
  return badge&&badge===apple.badges[locale]&&width?{url:badge,width}:undefined;
 }},
};
