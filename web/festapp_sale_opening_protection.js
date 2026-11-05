/* Shared browser adapter for Flutter web and the public JS form. */
(() => {
  if (window.FestappSaleOpeningProtection) return;
  let loading;
  function load() {
    if (window.turnstile) return Promise.resolve(window.turnstile);
    if (!loading) loading = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
      script.async = true;
      const timer = setTimeout(() => { script.remove(); reject(new Error('verification_unavailable')); }, 15000);
      script.onload = () => { clearTimeout(timer); window.turnstile ? resolve(window.turnstile) : reject(new Error('verification_unavailable')); };
      script.onerror = () => { clearTimeout(timer); script.remove(); reject(new Error('verification_unavailable')); };
      document.head.append(script);
    }).catch(error => { loading = null; throw error; });
    return loading;
  }
  window.FestappSaleOpeningProtection = {
    async verify(siteKey, formLink, email) {
      const api = await load();
      const binding = new TextEncoder().encode(JSON.stringify([formLink, email.trim().toLowerCase()]));
      const cData = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', binding)), b => b.toString(16).padStart(2,'0')).join('');
      return new Promise((resolve, reject) => {
        const host = document.createElement('div');
        // This stays invisible for normal background checks. Only provider-requested
        // interaction appears, without moving or replacing the subscription form.
        host.style.cssText = 'position:fixed;bottom:16px;left:50%;transform:translateX(-50%);z-index:2147483647;max-width:100vw';
        document.body.append(host);
        let widget, done = false;
        const finish = (error, token, code) => {
          if (done) return; done = true; clearTimeout(timer);
          if (widget !== undefined) api.remove(widget);
          host.remove();
          if (error) {
            // Provider diagnostics contain a code only, never a token or contact.
            const safeCode = /^\d{6}$/.test(String(code)) ? String(code) : 'unavailable';
            window.dispatchEvent(new CustomEvent('festapp-sale-opening-verification-error', {detail: {code: safeCode}}));
            reject(new Error('verification_failed'));
          } else resolve(token);
        };
        const timer = setTimeout(() => finish(true), 120000);
        try {
          widget = api.render(host, {
            sitekey: siteKey, action: 'sale_opening_subscribe', cData,
            appearance: 'interaction-only', execution: 'render', size: 'flexible',
            callback: token => finish(false, token),
            'error-callback': code => { finish(true, undefined, code); return true; },
            'expired-callback': () => finish(true), 'timeout-callback': () => finish(true),
          });
        } catch { finish(true); }
      });
    },
  };
})();
