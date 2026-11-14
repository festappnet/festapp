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
const collectionCopy={
 cs:{title:'Uložení vstupenek',count:'Dostupných vstupenek: {count}.',partial:'Některé vstupenky již nejsou dostupné. Zkontrolujte počet a pokračujte tlačítkem peněženky.',parts:'Peněženka nabídne vstupenky v {parts} skupinách. Každou potvrďte samostatně.',part:'Otevřít skupinu {n} z {parts} ({count})',offered:'Skupina {n} byla nabídnuta peněžence. Dokončete uložení v jejím dialogu.'},
 sk:{title:'Uloženie vstupeniek',count:'Dostupných vstupeniek: {count}.',partial:'Niektoré vstupenky už nie sú dostupné. Skontrolujte počet a pokračujte tlačidlom peňaženky.',parts:'Peňaženka ponúkne vstupenky v {parts} skupinách. Každú potvrďte samostatne.',part:'Otvoriť skupinu {n} z {parts} ({count})',offered:'Skupina {n} bola ponúknutá peňaženke. Dokončite uloženie v jej dialógu.'},
 en:{title:'Save your tickets',count:'Available tickets: {count}.',partial:'Some tickets are no longer available. Check the count and use the wallet button to continue.',parts:'Your wallet will offer tickets in {parts} groups. Confirm each group separately.',part:'Open group {n} of {parts} ({count})',offered:'Group {n} was offered to your wallet. Finish saving in its dialog.'},
 de:{title:'Tickets speichern',count:'Verfügbare Tickets: {count}.',partial:'Einige Tickets sind nicht mehr verfügbar. Prüfen Sie die Anzahl und fahren Sie über die Wallet-Schaltfläche fort.',parts:'Die Wallet bietet die Tickets in {parts} Gruppen an. Bestätigen Sie jede Gruppe einzeln.',part:'Gruppe {n} von {parts} öffnen ({count})',offered:'Gruppe {n} wurde der Wallet angeboten. Schließen Sie das Speichern in deren Dialog ab.'},
 pl:{title:'Zapisz bilety',count:'Dostępne bilety: {count}.',partial:'Niektóre bilety nie są już dostępne. Sprawdź liczbę i wybierz przycisk portfela, aby kontynuować.',parts:'Portfel zaproponuje bilety w {parts} grupach. Potwierdź każdą grupę osobno.',part:'Otwórz grupę {n} z {parts} ({count})',offered:'Grupa {n} została przekazana do portfela. Dokończ zapis w jego oknie.'},
 uk:{title:'Збереження квитків',count:'Доступні квитки: {count}.',partial:'Деякі квитки вже недоступні. Перевірте кількість і натисніть кнопку гаманця, щоб продовжити.',parts:'Гаманець запропонує квитки в {parts} групах. Підтвердьте кожну групу окремо.',part:'Відкрити групу {n} з {parts} ({count})',offered:'Групу {n} передано до гаманця. Завершіть збереження в його вікні.'},
};
const pluralCopy={
 cs:{intro:'Vyberte peněženku pro uložení vstupenek. Pro Apple Peněženku otevřete tuto stránku na iPhonu nebo Macu.',preparing:'Připravuji vstupenky…',unavailable:'Vstupenky nejsou dostupné nebo se jejich stav změnil. Odkaz znovu otevřete z e-mailu.'},
 sk:{intro:'Vyberte peňaženku pre uloženie vstupeniek. Pre Apple Wallet otvorte túto stránku na iPhone alebo Macu.',preparing:'Pripravujem vstupenky…',unavailable:'Vstupenky nie sú dostupné alebo sa ich stav zmenil. Odkaz znovu otvorte z e-mailu.'},
 en:{intro:'Choose a wallet for your tickets. For Apple Wallet, open this page on your iPhone or Mac.',preparing:'Preparing your tickets…',unavailable:'These tickets are unavailable or have changed. Open the link again from your ticket email.'},
 de:{intro:'Wählen Sie eine Wallet für Ihre Tickets. Öffnen Sie diese Seite für Apple Wallet auf Ihrem iPhone oder Mac.',preparing:'Tickets werden vorbereitet…',unavailable:'Die Tickets sind nicht verfügbar oder wurden geändert. Öffnen Sie den Link erneut aus Ihrer Ticket-E-Mail.'},
 pl:{intro:'Wybierz portfel dla swoich biletów. Aby użyć Apple Wallet, otwórz tę stronę na iPhonie lub Macu.',preparing:'Przygotowywanie biletów…',unavailable:'Bilety są niedostępne lub ich stan się zmienił. Otwórz link ponownie z wiadomości z biletami.'},
 uk:{intro:'Виберіть гаманець для своїх квитків. Для Apple Wallet відкрийте цю сторінку на iPhone або Mac.',preparing:'Підготовка квитків…',unavailable:'Квитки недоступні або їхній стан змінився. Знову відкрийте посилання з листа з квитками.'},
};
function format(text,values){return text.replace(/\{(\w+)\}/g,(_,key)=>String(values[key]));}
function validPlan(plan){return plan?.kind==='collection'&&/^[a-f0-9]{64}$/.test(plan.revision)&&Number.isInteger(plan.ticketCount)&&plan.ticketCount>0&&Number.isInteger(plan.originalCount)&&plan.originalCount>=plan.ticketCount&&Array.isArray(plan.parts)&&plan.parts.length>0&&plan.parts.every(n=>Number.isInteger(n)&&n>=1&&n<=10)&&plan.parts.reduce((a,b)=>a+b,0)===plan.ticketCount;}
export class TicketWalletPage extends Component {
 constructor(host,{invoke,win=window,locale='cs',walletEndpoint=null,connectors=walletConnectors}) {super(host);Object.assign(this,{invoke,win,walletEndpoint,connectors});this.text=copy[locale]??copy.en;this.locale=Object.hasOwn(copy,locale)?locale:'en';}
 async init() {
  this.session?.dispose();
  this.session=new WalletLinkSession(this.win);
  return this.session.start(link=>this.#renderLink(link));
 }
 async #renderLink(link) {
  this.link=link;this.token=link.token;this.busy=false;
  if(Object.hasOwn(copy,link.lang))this.locale=link.lang;
  this.text=link.scope==='collection'?{...copy[this.locale],...pluralCopy[this.locale]}:copy[this.locale];
  // Native cross-origin POST needs Origin. strict-origin never sends the private URL.
  for(const meta of this.win.document.querySelectorAll('meta[name="referrer"]'))meta.setAttribute('content','strict-origin');
  this.win.document.documentElement.lang=this.locale;
  this.host.style.display='block';
  const main=this.win.document.createElement('main'); main.className='wallet-page';
  const title=this.win.document.createElement('h1');title.textContent=link.scope==='collection'?collectionCopy[this.locale].title:this.text.title;
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
   const parts=this.win.document.createElement('div');parts.hidden=true;
   this.actions.set(connector.id,{button,label,connector,parts});main.append(button,parts);
  }
  this.host.replaceChildren(main);
  this.status.textContent=this.token?this.text.intro:this.text.missing;
  const connector=link.provider?this.connectors.find(item=>item.id===link.provider):this.connectors.find(item=>item.matchesDevice?.(this.win.navigator));
  if(this.token&&connector)await this.save(connector);
 }
 #submitFile(connector,plan,part=0) {
  if(this.link?.signal.aborted||!this.token||!this.walletEndpoint)return;
  try {
   const endpoint=new URL(this.walletEndpoint);
   if(endpoint.protocol!=='https:'||endpoint.username||endpoint.password||endpoint.search||endpoint.hash||!endpoint.pathname.endsWith('/functions/v1/ticket-wallet'))throw new Error('wallet_endpoint');
   // Native form navigation preserves the pkpass MIME type for Safari/Wallet.
   // The capability stays in the POST body, never a URL, history or local storage.
   const form=this.win.document.createElement('form');form.method='POST';form.action=endpoint.href;form.hidden=true;
   for(const [name,value] of Object.entries({token:this.token,provider:connector.id,...(plan?{revision:plan.revision,part:String(part)}:{})})){
    const input=this.win.document.createElement('input');input.type='hidden';input.name=name;input.value=value;form.append(input);
   }
   this.status.textContent=this.text.preparing;
   this.host.append(form);
   try{form.submit();}finally{form.remove();}
  }catch{this.status.textContent=this.text.retry;}
 }
 #showParts(action,plan){
  const text=collectionCopy[this.locale];
  for(const item of this.actions.values())item.parts.hidden=item!==action;
  action.parts.replaceChildren();action.parts.hidden=false;
  const summary=this.win.document.createElement('p');
  summary.textContent=format(text.count,{count:plan.ticketCount})+(plan.parts.length>1?' '+format(text.parts,{parts:plan.parts.length}):'');
  action.parts.append(summary);
  if(plan.parts.length>1)plan.parts.forEach((count,index)=>{
   const button=this.win.document.createElement('button');button.type='button';button.className='wallet-save';
   button.textContent=format(text.part,{n:index+1,parts:plan.parts.length,count});
   button.addEventListener('click',()=>this.save(action.connector,index));action.parts.append(button);
  });
 }
 async save(connector=this.connectors.find(item=>item.delivery==='redirect'),part=0) {
  if(!connector)return;
  const action=this.actions.get(connector.id);if(!action)return;
  const {button,label}=action;
  const link=this.link;
  if(!link||link.signal.aborted||this.busy||!this.token)return;
  // Existing single-ticket links retain their direct native delivery and need no preflight.
  if(link.scope!=='collection'&&connector.delivery==='file'){this.#submitFile(connector);return;}
  if(action.url){this.win.location.assign(action.url);return;}
  this.busy=true;button.disabled=true;this.status.textContent=this.text.preparing;
  try {
   let plan=action.plan;
   if(link.scope==='collection'){
    if(!plan){
     plan=await this.invoke({token:this.token,provider:connector.id,action:'plan'},{signal:link.signal});
     if(link.signal.aborted)return;
     if(plan?.error==='wallet_unavailable'){this.status.textContent=this.text.unavailable;for(const item of this.actions.values())item.button.hidden=true;return;}
     if(!validPlan(plan))throw new Error('wallet_plan');
     action.plan=plan;this.#showParts(action,plan);
     if(plan.ticketCount<plan.originalCount){this.status.textContent=collectionCopy[this.locale].partial;return;}
    }else this.#showParts(action,plan);
    if(!Number.isInteger(part)||part<0||part>=plan.parts.length)throw new Error('wallet_part');
   }
   if(connector.delivery==='file'){
    this.#submitFile(connector,plan,part);
    this.status.textContent=format(collectionCopy[this.locale].offered,{n:part+1});return;
   }
   const result=await this.invoke({token:this.token,provider:connector.id,...(plan?{revision:plan.revision,part}:{})},{signal:link.signal});
   if(link.signal.aborted)return;
   if(result?.error==='wallet_unavailable'){action.plan=null;this.status.textContent=this.text.unavailable;if(link.scope!=='collection')for(const item of this.actions.values())item.button.hidden=true;return;}
   const url=connector.validateUrl(result?.url);if(!url)throw new Error('wallet_retry');
   if(result.state==='COMPLETED'){
    this.status.textContent=this.text.used;label.textContent=connector.label(this.locale);action.url=url;
   }else this.win.location.assign(url);
  }catch{if(!link.signal.aborted){action.plan=null;this.status.textContent=this.text.retry;label.textContent=this.text.tryAgain;}}
  finally{if(!link.signal.aborted){this.busy=false;button.disabled=false;}}
 }

 clear(){this.session?.dispose();this.link=null;this.token=null;this.actions?.clear();this.walletEndpoint=null;this.host.replaceChildren();}
}
