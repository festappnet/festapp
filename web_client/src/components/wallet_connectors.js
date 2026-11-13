/** Presentation composition root. Delivery capabilities, rather than provider branches, drive the page. */
export function googleWalletSaveUrl(value) {
 try {const url=new URL(value);return url.origin==='https://pay.google.com'&&/^\/gp\/v\/save\/[A-Za-z0-9_.-]+$/.test(url.pathname)&&!url.search&&!url.hash&&!url.username&&!url.password?url.href:null;}catch{return null;}
}
const googleLabels={cs:'Uložit do Google Wallet',sk:'Uložiť do Google Wallet',en:'Add to Google Wallet',de:'Zu Google Wallet hinzufügen',pl:'Dodaj do Portfela Google',uk:'Додати в Google Гаманець'};
const appleLabels={cs:'Přidat do Apple Peněženky',sk:'Pridať do Apple Wallet',en:'Add to Apple Wallet',de:'Zu Apple Wallet hinzufügen',pl:'Dodaj do Apple Wallet',uk:'Додати в Apple Wallet'};
export const walletConnectors=Object.freeze([
 {id:'google',delivery:'redirect',matchesDevice:nav=>/Android|Windows|Linux|CrOS/.test(nav?.userAgent??''),validateUrl:googleWalletSaveUrl,label:locale=>googleLabels[locale]??googleLabels.en,badge:locale=>'https://img.festapp.net/assets/google-wallet/v1/'+locale+'.png'},
 {id:'apple',delivery:'file',matchesDevice:nav=>/iPhone|iPad|iPod|Macintosh/.test(nav?.userAgent??''),label:locale=>appleLabels[locale]??appleLabels.en,badge:locale=>locale==='en'?new URL('../../../assets/brand/apple-wallet/en.svg',import.meta.url).href:undefined},
]);
