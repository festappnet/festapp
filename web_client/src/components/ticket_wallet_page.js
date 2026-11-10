import {Component} from './base/component.js';
const copy = {
 cs: ['Uložení vstupenky','Vstupenku můžete uložit do svého účtu Google Wallet.','Uložit do Google Wallet','Připravuji vstupenku…','Odkaz znovu otevřete z e-mailu se vstupenkami.','Vstupenka není dostupná. Použijte původní vstupenku nebo kontaktujte pořadatele.','Google Wallet je dočasně nedostupná. Zkuste to prosím znovu.','Vstupenka již byla použita.','Zkusit znovu'],
 sk: ['Uloženie vstupenky','Vstupenku si môžete uložiť do účtu Google Wallet.','Uložiť do Google Wallet','Pripravujem vstupenku…','Odkaz znovu otvorte z e-mailu so vstupenkami.','Vstupenka nie je dostupná. Kontaktujte organizátora.','Google Wallet je dočasne nedostupná. Skúste to znova.','Vstupenka už bola použitá.','Skúsiť znova'],
 en: ['Save your ticket','Save your ticket to your Google Wallet account.','Add to Google Wallet','Preparing your ticket…','Open the link again from your ticket email.','This ticket is unavailable. Use your original ticket or contact the organizer.','Google Wallet is temporarily unavailable. Please try again.','This ticket has already been used.','Try again'],
 de: ['Ticket speichern','Speichern Sie Ihr Ticket in Google Wallet.','Zu Google Wallet hinzufügen','Ticket wird vorbereitet…','Öffnen Sie den Link erneut aus Ihrer Ticket-E-Mail.','Dieses Ticket ist nicht verfügbar. Wenden Sie sich an den Veranstalter.','Google Wallet ist vorübergehend nicht verfügbar. Versuchen Sie es erneut.','Dieses Ticket wurde bereits verwendet.','Erneut versuchen'],
 pl: ['Zapisz bilet','Zapisz bilet na swoim koncie Portfela Google.','Dodaj do Portfela Google','Przygotowywanie biletu…','Otwórz link ponownie z wiadomości z biletami.','Bilet jest niedostępny. Skontaktuj się z organizatorem.','Portfel Google jest chwilowo niedostępny. Spróbuj ponownie.','Bilet został już wykorzystany.','Spróbuj ponownie'],
 uk: ['Збереження квитка','Збережіть квиток у своєму Google Гаманці.','Додати в Google Гаманець','Підготовка квитка…','Знову відкрийте посилання з листа з квитками.','Квиток недоступний. Зверніться до організатора.','Google Гаманець тимчасово недоступний. Спробуйте ще раз.','Цей квиток уже використано.','Спробувати ще раз'],
};
export function takeWalletToken(win=window) {
 const captured=win.__festappWalletToken;
 delete win.__festappWalletToken;
 const token=captured??win.location.hash.slice(1);
 if(win.location.hash)win.history.replaceState(win.history.state,'',win.location.pathname);
 return /^[a-f0-9]{64}$/.test(token||'')?token:null;
}
export function googleWalletSaveUrl(value) {
 try {const url=new URL(value);return url.origin==='https://pay.google.com'&&/^\/gp\/v\/save\/[A-Za-z0-9_.-]+$/.test(url.pathname)&&!url.search&&!url.hash&&!url.username&&!url.password?url.href:null;}catch{return null;}
}
export class TicketWalletPage extends Component {
 constructor(host,{invoke,win=window,locale='cs'}) {super(host);Object.assign(this,{invoke,win});this.text=copy[locale]??copy.en;this.locale=Object.hasOwn(copy,locale)?locale:'en';}
 async init() {
  this.token=takeWalletToken(this.win);
  this.win.document.querySelector('meta[name="referrer"]')?.setAttribute('content','no-referrer');
  this.host.style.display='block';
  const main=this.win.document.createElement('main'); main.className='wallet-page';
  const title=this.win.document.createElement('h1');title.textContent=this.text[0];
  this.status=this.win.document.createElement('p');this.status.setAttribute('role','status');this.status.setAttribute('aria-live','polite');
  this.button=this.win.document.createElement('button');this.button.type='button';this.button.className='wallet-save';
  const badge=this.win.document.createElement('img');badge.src='https://img.festapp.net/assets/google-wallet/v1/'+this.locale+'.png';badge.alt=this.text[2];badge.height=48;
  const fallback=this.label=this.win.document.createElement('span');fallback.textContent=this.text[2];this.button.append(badge,fallback);
  this.button.addEventListener('click',()=>this.save());
  main.append(title,this.status,this.button);this.host.replaceChildren(main);
  this.status.textContent=this.text[this.token?1:4];this.button.hidden=!this.token;
 }
 async save() {
  if(this.busy||!this.token)return;
  this.busy=true;this.button.disabled=true;this.status.textContent=this.text[3];
  try {
   const result=await this.invoke({token:this.token});
   if(result?.error==='wallet_unavailable'){this.status.textContent=this.text[5];this.button.hidden=true;return;}
   const url=googleWalletSaveUrl(result?.url);if(!url)throw new Error('wallet_retry');
   if(result.state==='COMPLETED'){
    this.status.textContent=this.text[7];this.label.textContent=this.text[2];
    this.button.onclick=()=>this.win.location.assign(url);
    // A used pass is accurately marked; it does not grant another admission.
    this.token=null;
   }else this.win.location.assign(url);
  }catch{this.status.textContent=this.text[6];this.label.textContent=this.text[8];}
  finally{this.busy=false;this.button.disabled=false;}
 }
 clear(){this.token=null;this.host.replaceChildren();}
}
