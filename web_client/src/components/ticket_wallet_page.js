import {Component} from './base/component.js';
import {walletConnectors} from './wallet_connectors.js';
import {WalletLinkSession} from './wallet_link.js';
const copy = {
 "cs": {
  "title": "Uložení vstupenky",
  "intro": "Vyberte peněženku pro uložení vstupenky. Pro Apple Peněženku otevřete tuto stránku na iPhonu nebo Macu.",
  "preparing": "Připravuji vstupenku…",
  "missing": "Odkaz znovu otevřete z e-mailu se vstupenkami.",
  "unavailable": "Vstupenka není dostupná. Použijte původní vstupenku nebo kontaktujte pořadatele.",
  "retry": "Peněženka je dočasně nedostupná. Zkuste to prosím znovu.",
  "used": "Vstupenka již byla použita.",
  "tryAgain": "Zkusit znovu"
 },
 "sk": {
  "title": "Uloženie vstupenky",
  "intro": "Vyberte peňaženku pre uloženie vstupenky. Pre Apple Wallet otvorte túto stránku na iPhone alebo Macu.",
  "preparing": "Pripravujem vstupenku…",
  "missing": "Odkaz znovu otvorte z e-mailu so vstupenkami.",
  "unavailable": "Vstupenka nie je dostupná. Kontaktujte organizátora.",
  "retry": "Peňaženka je dočasne nedostupná. Skúste to znova.",
  "used": "Vstupenka už bola použitá.",
  "tryAgain": "Skúsiť znova"
 },
 "en": {
  "title": "Save your ticket",
  "intro": "Choose a wallet for your ticket. For Apple Wallet, open this page on your iPhone or Mac.",
  "preparing": "Preparing your ticket…",
  "missing": "Open the link again from your ticket email.",
  "unavailable": "This ticket is unavailable. Use your original ticket or contact the organizer.",
  "retry": "The wallet is temporarily unavailable. Please try again.",
  "used": "This ticket has already been used.",
  "tryAgain": "Try again"
 },
 "de": {
  "title": "Ticket speichern",
  "intro": "Wählen Sie eine Wallet für Ihr Ticket. Öffnen Sie diese Seite für Apple Wallet auf Ihrem iPhone oder Mac.",
  "preparing": "Ticket wird vorbereitet…",
  "missing": "Öffnen Sie den Link erneut aus Ihrer Ticket-E-Mail.",
  "unavailable": "Dieses Ticket ist nicht verfügbar. Wenden Sie sich an den Veranstalter.",
  "retry": "Die Wallet ist vorübergehend nicht verfügbar. Versuchen Sie es erneut.",
  "used": "Dieses Ticket wurde bereits verwendet.",
  "tryAgain": "Erneut versuchen"
 },
 "pl": {
  "title": "Zapisz bilet",
  "intro": "Wybierz portfel dla swojego biletu. Aby użyć Apple Wallet, otwórz tę stronę na iPhonie lub Macu.",
  "preparing": "Przygotowywanie biletu…",
  "missing": "Otwórz link ponownie z wiadomości z biletami.",
  "unavailable": "Bilet jest niedostępny. Skontaktuj się z organizatorem.",
  "retry": "Portfel jest chwilowo niedostępny. Spróbuj ponownie.",
  "used": "Bilet został już wykorzystany.",
  "tryAgain": "Spróbuj ponownie"
 },
 "uk": {
  "title": "Збереження квитка",
  "intro": "Виберіть гаманець для квитка. Для Apple Wallet відкрийте цю сторінку на iPhone або Mac.",
  "preparing": "Підготовка квитка…",
  "missing": "Знову відкрийте посилання з листа з квитками.",
  "unavailable": "Квиток недоступний. Зверніться до організатора.",
  "retry": "Гаманець тимчасово недоступний. Спробуйте ще раз.",
  "used": "Цей квиток уже використано.",
  "tryAgain": "Спробувати ще раз"
 }
};
export class TicketWalletPage extends Component {
 constructor(host,{invoke,win=window,locale='cs',walletEndpoint=null,connectors=walletConnectors}) {super(host);Object.assign(this,{invoke,win,walletEndpoint,connectors});this.text=copy[locale]??copy.en;this.locale=Object.hasOwn(copy,locale)?locale:'en';}
 async init() {
  this.session?.dispose();
  this.session=new WalletLinkSession(this.win);
  return this.session.start(link=>this.#renderLink(link));
 }
 async #renderLink(link) {
  this.link=link;this.token=link.token;this.busy=false;
  if(Object.hasOwn(copy,link.lang)){this.locale=link.lang;this.text=copy[this.locale];}
  // Native cross-origin POST needs Origin. strict-origin never sends the private URL.
  for(const meta of this.win.document.querySelectorAll('meta[name="referrer"]'))meta.setAttribute('content','strict-origin');
  this.win.document.documentElement.lang=this.locale;
  this.host.style.display='block';
  const main=this.win.document.createElement('main'); main.className='wallet-page';
  const title=this.win.document.createElement('h1');title.textContent=this.text.title;
  this.status=this.win.document.createElement('p');this.status.setAttribute('role','status');this.status.setAttribute('aria-live','polite');
  this.actions=new Map();
  main.append(title,this.status);
  for(const connector of this.connectors){
   const button=this.win.document.createElement('button');button.type='button';button.className='wallet-save';
   const badgeUrl=connector.badge(this.locale);
   if(badgeUrl){const badge=this.win.document.createElement('img');badge.src=badgeUrl;badge.alt='';badge.height=48;button.append(badge);}
   const label=this.win.document.createElement('span');label.textContent=connector.label(this.locale);button.append(label);
   button.addEventListener('click',()=>this.save(connector));
   button.hidden=!this.token||(connector.delivery==='file'&&!this.walletEndpoint);
   this.actions.set(connector.id,{button,label,connector});main.append(button);
  }
  this.host.replaceChildren(main);
  this.status.textContent=this.token?this.text.intro:this.text.missing;
  const connector=link.provider?this.connectors.find(item=>item.id===link.provider):this.connectors.find(item=>item.matchesDevice?.(this.win.navigator));
  if(this.token&&connector)await this.save(connector);
 }
 #submitFile(connector) {
  if(this.link?.signal.aborted||this.busy||!this.token||!this.walletEndpoint)return;
  try {
   const endpoint=new URL(this.walletEndpoint);
   if(endpoint.protocol!=='https:'||endpoint.username||endpoint.password||endpoint.search||endpoint.hash||!endpoint.pathname.endsWith('/functions/v1/ticket-wallet'))throw new Error('wallet_endpoint');
   // Native form navigation preserves the pkpass MIME type for Safari/Wallet.
   // The capability stays in the POST body, never a URL, history or local storage.
   const form=this.win.document.createElement('form');form.method='POST';form.action=endpoint.href;form.hidden=true;
   for(const [name,value] of Object.entries({token:this.token,provider:connector.id})){
    const input=this.win.document.createElement('input');input.type='hidden';input.name=name;input.value=value;form.append(input);
   }
   this.status.textContent=this.text.preparing;
   this.host.append(form);
   try{form.submit();}finally{form.remove();}
  }catch{this.status.textContent=this.text.retry;}
 }
 async save(connector=this.connectors.find(item=>item.delivery==='redirect')) {
  if(!connector)return;
  const action=this.actions.get(connector.id);if(!action)return;
  const {button,label}=action;
  const link=this.link;
  if(!link||link.signal.aborted||this.busy||!this.token)return;
  if(connector.delivery==='file'){this.#submitFile(connector);return;}
  if(action.url){this.win.location.assign(action.url);return;}
  this.busy=true;button.disabled=true;this.status.textContent=this.text.preparing;
  try {
   const result=await this.invoke({token:this.token,provider:connector.id},{signal:link.signal});
   if(link.signal.aborted)return;
   if(result?.error==='wallet_unavailable'){this.status.textContent=this.text.unavailable;for(const action of this.actions.values())action.button.hidden=true;return;}
   const url=connector.validateUrl(result?.url);if(!url)throw new Error('wallet_retry');
   if(result.state==='COMPLETED'){
    this.status.textContent=this.text.used;label.textContent=connector.label(this.locale);
    // Retain the shared capability for the independent Apple action.
    action.url=url;
   }else this.win.location.assign(url);
  }catch{if(!link.signal.aborted){this.status.textContent=this.text.retry;label.textContent=this.text.tryAgain;}}
  finally{if(!link.signal.aborted){this.busy=false;button.disabled=false;}}
 }
 clear(){this.session?.dispose();this.link=null;this.token=null;this.actions?.clear();this.walletEndpoint=null;this.host.replaceChildren();}
}
