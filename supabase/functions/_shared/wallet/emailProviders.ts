import {walletPresentation} from './presentation.js';
/** Email composition uses public metadata and independently verified published assets. */
const presentation:Record<string,{labels:Record<string,string>;widths:Record<string,number>;badges:Record<string,string>}>=walletPresentation;
const {google,apple}=presentation;
export const walletEmailProviders:Record<string,{labels:Record<string,string>;width:(locale:string)=>number;badge:(urls:any,locale:string)=>string|undefined;labelFallback:boolean}>={
 google:{labels:google.labels,width:locale=>google.widths[locale]??google.widths.en,labelFallback:true,badge:(urls,locale)=>{
  const badge=urls?.[locale];
  return typeof badge==='string'&&badge===google.badges[locale]?badge:undefined;
 }},
 apple:{labels:apple.labels,width:locale=>apple.widths[locale]??apple.widths.en,labelFallback:true,badge:(urls,locale)=>{
  const badge=urls?.apple?.[locale];
  return typeof badge==='string'&&badge===apple.badges[locale]?badge:undefined;
 }},
};
