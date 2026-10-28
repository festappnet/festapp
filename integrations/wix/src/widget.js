import {window as wixWindow} from '@wix/site-window';
import {site} from '@wix/site';
import {createClient} from '@wix/sdk';
import registration from '../wix-app.json' with {type:'json'};
import {registerTicketElement} from './element.js';
import {CHECKOUT_CONTEXT_ENDPOINT} from './config.js';
// Self-managed extensions do not receive the implicit SDK context available
// to Wix-managed code. Bind frontend APIs to this app's actual site host.
let client;
function wixClient() {
  return client ??= createClient({
    auth:site.auth(),
    host:site.host({applicationId:registration.appId}),
    modules:{wixWindow},
  });
}
registerTicketElement(window, () => wixClient().wixWindow.viewMode(), {
  injectToken: () => wixClient().auth.getAccessTokenInjector(),
  async context(url) {
    const controller = new AbortController();
    let timer;
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
        new Promise((_, reject) => { timer=setTimeout(() => {
          controller.abort(); reject(new Error('CHECKOUT_CONTEXT_UNAVAILABLE'));
        },12000); }),
      ]);
    } finally { clearTimeout(timer); }
  },
});
