/** Owns private email-link input, including Safari reusing an existing tab. */
export function readWalletLink(win=window) {
 const options=win.__festappWalletOptions??Object.fromEntries(new URLSearchParams(win.location.search));
 const token=win.__festappWalletToken??win.location.hash.slice(1);
 delete win.__festappWalletOptions;
 delete win.__festappWalletToken;
 if(win.location.hash||win.location.search)win.history.replaceState(win.history.state,'',win.location.pathname);
 return {token:/^[a-f0-9]{64}$/.test(token||'')?token:null,provider:options.provider,lang:options.lang};
}

/** One link owns one lifetime. A later link or disposal cancels its continuations. */
export class WalletLinkSession {
 #controller; #receive; #active=false; #win; #onNavigation;
 constructor(win=window) {this.#win=win;this.#onNavigation=()=>{if(!this.#isWalletPath())this.dispose();else if(this.#win.location.hash)void this.#open();};}
 #isWalletPath(){return /^\/wallet\/?$/.test(this.#win.location.pathname);}
 start(receive) {
  this.#receive=receive;this.#active=true;
  for(const event of ['hashchange','popstate','pageshow'])this.#win.addEventListener(event,this.#onNavigation);
  return this.#open();
 }
 #open() {
  if(!this.#active||!this.#isWalletPath())return;
  this.#controller?.abort();
  this.#controller=new AbortController();
  const signal=this.#controller.signal;
  let completion;
  try {completion=Promise.resolve(this.#receive({...readWalletLink(this.#win),signal}));}
  catch(error){completion=Promise.reject(error);}
  // History events ignore completion. Explicit initial callers can still await
  // the original rejection; background errors get a token-free diagnostic.
  completion.catch(()=>{if(!signal.aborted)console.warn('Wallet link navigation failed');});
  return completion;
 }
 dispose() {
  this.#active=false;
  this.#controller?.abort();
  for(const event of ['hashchange','popstate','pageshow'])this.#win.removeEventListener(event,this.#onNavigation);
 }
}
