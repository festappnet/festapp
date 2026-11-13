/** Email composition descriptors are public configuration, isolated from signing credentials. */
const appleLabels:Record<string,string>={cs:'Přidat do Apple Peněženky',sk:'Pridať do Apple Wallet',en:'Add to Apple Wallet',de:'Zu Apple Wallet hinzufügen',pl:'Dodaj do Apple Wallet',uk:'Додати в Apple Wallet'};
const googleLabels:Record<string,string>={cs:'Přidat do Peněženky Google',sk:'Pridať do Peňaženky Google',en:'Add to Google Wallet',de:'Zu Google Wallet hinzufügen',pl:'Dodaj do Portfela Google',uk:'Додати в Google Гаманець'};
const widths:Record<string,number>={cs:333.12,sk:394.56,en:271.68,de:339.84,pl:307.2,uk:325.44};
export const walletEmailProviders:Record<string,{labels:Record<string,string>;width:(locale:string)=>number;badge:(urls:any,locale:string)=>string|undefined;labelFallback:boolean}>={
 google:{labels:googleLabels,width:locale=>widths[locale]??widths.en,labelFallback:true,badge:(urls,locale)=>{
  const badge=urls?.[locale];
  return typeof badge==='string'&&badge===`https://img.festapp.net/assets/google-wallet/v1/${locale}.png`?badge:undefined;
 }},
 apple:{labels:appleLabels,width:()=>166,labelFallback:true,badge:(urls,locale)=>{
  const badge=urls?.apple?.[locale];
  return locale==='en'&&badge==='https://img.festapp.net/assets/apple-wallet/v1/en.svg'?badge:undefined;
 }},
};
