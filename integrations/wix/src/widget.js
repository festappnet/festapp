import {window as wixWindow} from '@wix/site-window';
import {site} from '@wix/site';
import {createClient} from '@wix/sdk';
import registration from '../wix-app.json' with {type:'json'};
import {registerTicketElement} from './element.js';
import {CHECKOUT_CONTEXT_ENDPOINT} from './config.js';
// Wix may defer native token delivery in a background tab. Bound visible
// waiting time without cancelling authentication before the host can hydrate.
const CONTEXT_VISIBLE_TIMEOUT_MS = 60_000;
// Self-managed extensions do not receive the implicit SDK context available
// to Wix-managed code. Bind frontend APIs to this app's actual site host.
// Wix identifies this app through document.currentScript. Capture auth now;
// widget constructors may run later, after that script context is gone.
const auth = site.auth();
let client;
function wixClient() {
  return client ??= createClient({
    auth,
    host:site.host({applicationId:registration.appId}),
    modules:{wixWindow},
  });
}
registerTicketElement(window, () => wixClient().wixWindow.viewMode(), {
  injectToken: () => wixClient().auth.getAccessTokenInjector(),
  async context(url) {
    const controller = new AbortController();
    let timer, startedAt = null, remaining = CONTEXT_VISIBLE_TIMEOUT_MS;
    const deadline = new Promise((_, reject) => {
      controller.signal.addEventListener('abort', () => reject(new Error('CHECKOUT_CONTEXT_UNAVAILABLE')), {once:true});
    });
    const updateDeadline = () => {
      clearTimeout(timer);
      if (startedAt !== null) remaining = Math.max(0, remaining - (performance.now() - startedAt));
      startedAt = null;
      if (document.visibilityState === 'hidden') return;
      startedAt = performance.now();
      timer = setTimeout(() => controller.abort(), remaining);
    };
    document.addEventListener('visibilitychange', updateDeadline);
    updateDeadline();
    try {
      return await Promise.race([
        (async () => {
          const response = await wixClient().fetchWithAuth(CHECKOUT_CONTEXT_ENDPOINT, {
            method:'POST', headers:{'Content-Type':'application/json'},
            body:JSON.stringify({formLink:decodeURIComponent(new URL(url).pathname.slice('/form/'.length))}),
            signal:controller.signal,
          });
          if (!response.ok) throw new Error('CHECKOUT_CONTEXT_UNAVAILABLE');
          const data = await response.json();
          if (!/^[A-Za-z0-9_-]+\.[0-9a-f]{64}$/.test(data?.context || '') ||
              !Number.isSafeInteger(data.expiresAt) || data.expiresAt * 1000 <= Date.now()) {
            throw new Error('CHECKOUT_CONTEXT_UNAVAILABLE');
          }
          return data.context;
        })(),
        deadline,
      ]);
    } finally {
      clearTimeout(timer);
      document.removeEventListener('visibilitychange', updateDeadline);
    }
  },
});
