import {walletPresentation} from '../../../supabase/functions/_shared/wallet/presentation.js';
/** Presentation composition root. Delivery capabilities, rather than provider branches, drive the page. */
export function googleWalletSaveUrl(value) {
 try {const url=new URL(value);return url.origin==='https://pay.google.com'&&/^\/gp\/v\/save\/[A-Za-z0-9_.-]+$/.test(url.pathname)&&!url.search&&!url.hash&&!url.username&&!url.password?url.href:null;}catch{return null;}
}
const {google,apple}=walletPresentation;
export const walletConnectors=Object.freeze([
 {id:'google',delivery:'redirect',matchesDevice:nav=>/Android|Windows|Linux|CrOS/.test(nav?.userAgent??''),validateUrl:googleWalletSaveUrl,label:locale=>google.labels[locale]??google.labels.en,badge:locale=>google.badges[locale]??google.badges.en},
 {id:'apple',delivery:'file',matchesDevice:nav=>/iPhone|iPad|iPod|Macintosh/.test(nav?.userAgent??''),label:locale=>apple.labels[locale]??apple.labels.en,badge:locale=>apple.badges[locale]?new URL('../../../assets/brand/apple-wallet/en.svg',import.meta.url).href:undefined},
]);
