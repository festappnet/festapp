import {Component} from './base/component.js';
import {walletConnectors} from './wallet_connectors.js';
const copy = {
 cs: ['Uložení vstupenky','Vyberte peněženku pro uložení vstupenky. Pro Apple Peněženku otevřete tuto stránku na iPhonu nebo Macu.','Uložit do Google Wallet','Připravuji vstupenku…','Odkaz znovu otevřete z e-mailu se vstupenkami.','Vstupenka není dostupná. Použijte původní vstupenku nebo kontaktujte pořadatele.','Peněženka je dočasně nedostupná. Zkuste to prosím znovu.','Vstupenka již byla použita.','Zkusit znovu'],
 sk: ['Uloženie vstupenky','Vyberte peňaženku pre uloženie vstupenky. Pre Apple Wallet otvorte túto stránku na iPhone alebo Macu.','Uložiť do Google Wallet','Pripravujem vstupenku…','Odkaz znovu otvorte z e-mailu so vstupenkami.','Vstupenka nie je dostupná. Kontaktujte organizátora.','Peňaženka je dočasne nedostupná. Skúste to znova.','Vstupenka už bola použitá.','Skúsiť znova'],
 en: ['Save your ticket','Choose a wallet for your ticket. For Apple Wallet, open this page on your iPhone or Mac.','Add to Google Wallet','Preparing your ticket…','Open the link again from your ticket email.','This ticket is unavailable. Use your original ticket or contact the organizer.','The wallet is temporarily unavailable. Please try again.','This ticket has already been used.','Try again'],
 de: ['Ticket speichern','Wählen Sie eine Wallet für Ihr Ticket. Öffnen Sie diese Seite für Apple Wallet auf Ihrem iPhone oder Mac.','Zu Google Wallet hinzufügen','Ticket wird vorbereitet…','Öffnen Sie den Link erneut aus Ihrer Ticket-E-Mail.','Dieses Ticket ist nicht verfügbar. Wenden Sie sich an den Veranstalter.','Die Wallet ist vorübergehend nicht verfügbar. Versuchen Sie es erneut.','Dieses Ticket wurde bereits verwendet.','Erneut versuchen'],
 pl: ['Zapisz bilet','Wybierz portfel dla swojego biletu. Aby użyć Apple Wallet, otwórz tę stronę na iPhonie lub Macu.','Dodaj do Portfela Google','Przygotowywanie biletu…','Otwórz link ponownie z wiadomości z biletami.','Bilet jest niedostępny. Skontaktuj się z organizatorem.','Portfel jest chwilowo niedostępny. Spróbuj ponownie.','Bilet został już wykorzystany.','Spróbuj ponownie'],
 uk: ['Збереження квитка','Виберіть гаманець для квитка. Для Apple Wallet відкрийте цю сторінку на iPhone або Mac.','Додати в Google Гаманець','Підготовка квитка…','Знову відкрийте посилання з листа з квитками.','Квиток недоступний. Зверніться до організатора.','Гаманець тимчасово недоступний. Спробуйте ще раз.','Цей квиток уже використано.','Спробувати ще раз'],
};
export function takeWalletToken(win=window) {
 const captured=win.__festappWalletToken;
 delete win.__festappWalletToken;
 const token=captured??win.location.hash.slice(1);
 if(win.location.hash)win.history.replaceState(win.history.state,'',win.location.pathname);
 return /^[a-f0-9]{64}$/.test(token||'')?token:null;
}
export class TicketWalletPage extends Component {
 constructor(host,{invoke,win=window,locale='cs',walletEndpoint=null,connectors=walletConnectors}) {super(host);Object.assign(this,{invoke,win,walletEndpoint,connectors});this.text=copy[locale]??copy.en;this.locale=Object.hasOwn(copy,locale)?locale:'en';}
 async init() {
  this.token=takeWalletToken(this.win);
  this.win.document.querySelector('meta[name="referrer"]')?.setAttribute('content','no-referrer');
  this.host.style.display='block';
  const main=this.win.document.createElement('main'); main.className='wallet-page';
  const title=this.win.document.createElement('h1');title.textContent=this.text[0];
  this.status=this.win.document.createElement('p');this.status.setAttribute('role','status');this.status.setAttribute('aria-live','polite');
  this.actions=new Map();
  main.append(title,this.status);
  for(const connector of this.connectors){
   const button=this.win.document.createElement('button');button.type='button';button.className='wallet-save';
   const badge=this.win.document.createElement('img');badge.src=connector.badge(this.locale);badge.alt='';badge.height=48;
   const label=this.win.document.createElement('span');label.textContent=connector.label(this.locale);button.append(badge,label);
   button.addEventListener('click',()=>connector.delivery==='file'?this.saveFile(connector):this.save(connector));
   button.hidden=!this.token||(connector.delivery==='file'&&!this.walletEndpoint);
   this.actions.set(connector.id,{button,label,connector});main.append(button);
  }
  this.host.replaceChildren(main);
  this.status.textContent=this.text[this.token?1:4];
 }
 saveFile(connector) {
  if(this.busy||!this.token||!this.walletEndpoint)return;
  try {
   const endpoint=new URL(this.walletEndpoint);
   if(endpoint.protocol!=='https:'||endpoint.username||endpoint.password||endpoint.search||endpoint.hash||!endpoint.pathname.endsWith('/functions/v1/ticket-wallet'))throw new Error('wallet_endpoint');
   // Native form navigation preserves the pkpass MIME type for Safari/Wallet.
   // The capability stays in the POST body, never a URL, history or local storage.
   const form=this.win.document.createElement('form');form.method='POST';form.action=endpoint.href;form.hidden=true;
   for(const [name,value] of Object.entries({token:this.token,provider:connector.id})){
    const input=this.win.document.createElement('input');input.type='hidden';input.name=name;input.value=value;form.append(input);
   }
   this.host.append(form);
   try{form.submit();}finally{form.remove();}
  }catch{this.status.textContent=this.text[6];}
 }
 async save(connector=this.connectors.find(item=>item.delivery==='redirect')) {
  if(!connector)return;
  const action=this.actions.get(connector.id);if(!action)return;
  const {button,label}=action;
  if(this.busy||!this.token)return;
  if(action.url){this.win.location.assign(action.url);return;}
  this.busy=true;button.disabled=true;this.status.textContent=this.text[3];
  try {
   const result=await this.invoke({token:this.token,provider:connector.id});
   if(result?.error==='wallet_unavailable'){this.status.textContent=this.text[5];for(const action of this.actions.values())action.button.hidden=true;return;}
   const url=connector.validateUrl(result?.url);if(!url)throw new Error('wallet_retry');
   if(result.state==='COMPLETED'){
    this.status.textContent=this.text[7];label.textContent=connector.label(this.locale);
    // Retain the shared capability for the independent Apple action.
    action.url=url;
   }else this.win.location.assign(url);
  }catch{this.status.textContent=this.text[6];label.textContent=this.text[8];}
  finally{this.busy=false;button.disabled=false;}
 }
 clear(){this.token=null;this.actions?.clear();this.walletEndpoint=null;this.host.replaceChildren();}
}
