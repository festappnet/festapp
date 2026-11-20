(() => {
 const initialized = new WeakSet();
 const copyMessages = {
  cs: {copied: 'Kód byl zkopírován.', manual: 'Kód je označený. Zkopírujte ho pomocí Ctrl+C nebo ⌘C.'},
  en: {copied: 'Code copied.', manual: 'Code selected. Copy it with Ctrl+C or ⌘C.'},
  sk: {copied: 'Kód bol skopírovaný.', manual: 'Kód je označený. Skopírujte ho klávesmi Ctrl+C alebo ⌘C.'},
 };
 const generatorMessages = {
  cs: origin => ({
    invalid: `Vložte veřejný odkaz uloženého formuláře ve tvaru ${origin}/form/vas-formular, bez parametrů a bez části za #.`,
    title: 'Objednávkový formulář', link: 'Otevřít formulář v nové kartě',
    ready: 'Kód je připravený. Zkopírujte ho do HTML bloku svého webu.',
    invalidExport: 'Vložte platný export z Festappu pro tuto službu. Formulář ověří aktuální propojení webu a pokrytí souhlasu.',
  }),
  en: origin => ({
    invalid: `Paste a saved public form link such as ${origin}/form/your-form, without query parameters or a # fragment.`,
    title: 'Order form', link: 'Open the form in a new tab',
    ready: 'Your code is ready. Copy it into a custom HTML block on your website.',
    invalidExport: 'Paste a valid Festapp export for this service. The form checks the current website binding and consent coverage.',
  }),
  sk: origin => ({
    invalid: `Vložte verejný odkaz na uložený formulár v tvare ${origin}/form/vas-formular, bez parametrov a časti za #.`,
    title: 'Objednávkový formulár', link: 'Otvoriť formulár na novej karte',
    ready: 'Kód je pripravený. Skopírujte ho do bloku HTML na svojom webe.',
    invalidExport: 'Vložte platný export z Festappu pre túto službu. Formulár overí aktuálne prepojenie webu a pokrytie súhlasu.',
  }),
 };
 const locale = () => Object.hasOwn(copyMessages, document.documentElement.lang) ? document.documentElement.lang : 'cs';
 function initCodeExamples() {
  document.querySelectorAll('[data-code-example]').forEach(example => {
    if (initialized.has(example)) return;
    initialized.add(example);
    const code = example.querySelector('code');
    const status = example.querySelector('[role="status"]');
    const messages = copyMessages[locale()];
    example.querySelector('[data-copy-code]').addEventListener('click', async () => {
      try {
        if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
        await navigator.clipboard.writeText(code.textContent);
        status.textContent = messages.copied;
      } catch {
        code.focus({preventScroll: true});
        const range = document.createRange();
        range.selectNodeContents(code);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        status.textContent = messages.manual;
      }
    });
  });
 }
 function init() {
  initCodeExamples();
  const form = document.querySelector('[data-embed-generator]');
  if (!form || initialized.has(form)) return;
  initialized.add(form);
  const origin = form.dataset.formOrigin || window.location.origin;
  const language = locale();
  const text = generatorMessages[language](origin);
  const messages = copyMessages[language];
  const urlInput = form.querySelector('[name="form-url"]');
  const mode = form.querySelector('[name="height-mode"]');
  const hostDataLayer = form.querySelector('[name="host-datalayer"]');
  const consentEnabled=form.querySelector('[name=consent-enabled]');
  const consentExport=form.querySelector('[name=consent-export]');
  const consentError=form.querySelector('[data-consent-error]');
  const output = form.querySelector('[data-embed-output]');
  const code = output.querySelector('textarea');
  const status = form.querySelector('[role="status"]');
  const error = form.querySelector('[data-url-error]');
  const escape = text => text.replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const invalidate = () => { output.hidden = true; status.textContent = ''; error.textContent = ''; urlInput.removeAttribute('aria-invalid');consentExport.removeAttribute('aria-invalid');consentError.textContent=''; };
  urlInput.addEventListener('input', invalidate);
  mode.addEventListener('change', invalidate);
  hostDataLayer.addEventListener('change', invalidate);
  consentEnabled.addEventListener('change',invalidate);consentExport.addEventListener('input',invalidate);
  form.addEventListener('submit', event => {
    event.preventDefault(); invalidate();
    let url;
    try {
      url = new URL(urlInput.value.trim());
      const slug = decodeURIComponent(url.pathname.slice('/form/'.length));
      if (url.origin !== origin || url.href !== url.origin + url.pathname || url.username || url.password || url.search || url.hash ||
          !url.pathname.startsWith('/form/') || !/^[\p{L}\p{N}_-]+$/u.test(slug) ||
          url.pathname !== '/form/' + encodeURIComponent(slug)) throw new Error('Invalid public URL');
    } catch {
      error.textContent = text.invalid;
      urlInput.setAttribute('aria-invalid', 'true'); urlInput.focus({preventScroll: true}); return;
    }
    let imported;
    if (consentEnabled.checked) {
      try {
        if (consentExport.value.length>16384) throw Error();
        const v=JSON.parse(consentExport.value), c=v?.providerConfig, b=v?.binding;
        const site=new URL(v.websiteOrigin);
        if (v.schemaVersion!==1 || v.serviceOrigin!==origin || site.protocol!=='https:' || site.origin!==v.websiteOrigin ||
            !/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(b?.id) || !Number.isSafeInteger(b?.version) || b.version<1 ||
            !['complianz','cookiebot','cookieconsent','wix'].includes(c?.provider) || ![c.organization,c.unit].every(v=>Number.isSafeInteger(v)&&v>0) ||
            c.origin!==v.websiteOrigin || typeof c.consentRevision!=='string' || !/^[a-f0-9]{32}$/.test(c.consentRevision)) throw Error();
        imported=v;
      } catch {
        consentError.textContent=text.invalidExport;consentExport.setAttribute('aria-invalid','true');consentExport.focus({preventScroll:true});return;
      }
    }
    const automatic = mode.value === 'automatic';
    const marker = ' data-festapp-embed' +
      (automatic ? '' : ' data-festapp-height="fixed"') +
      (hostDataLayer.checked ? ' data-festapp-datalayer' : '');
    // Match the child canvas from creation, before the deferred helper can run.
    const frame = `<iframe${marker} src="${escape(url.href + '?embed=1')}" title="${text.title}" allow="clipboard-write" height="800" style="display:block;width:100%;max-width:100%;border:0;color-scheme:light dark" loading="lazy"></iframe>`;
    const link = `<a href="${escape(url.href)}" target="_blank" ${imported ? 'data-festapp-consent-link' : 'rel="noopener noreferrer"'}>${text.link}</a>`;
    const importAttributes=imported ? ` data-festapp-consent="${escape(JSON.stringify(imported))}"${imported.providerConfig.provider==='cookiebot' ? ' data-cookieconsent="ignore"' : ''}${imported.providerConfig.provider==='complianz' ? ' data-category="functional"' : ''}` : '';
    code.value = `<div data-festapp-embed-host>\n${frame}\n${link}\n</div>\n<script src="${origin}/embed.js"${importAttributes} defer></script>`;
    output.hidden = false; output.querySelector('[data-form-link]').href = url.href;
    status.textContent = text.ready;
  });
  form.querySelector('[data-copy-embed]').addEventListener('click', async () => {
    try {
      if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
      await navigator.clipboard.writeText(code.value); status.textContent = messages.copied;
    } catch {
      code.focus({preventScroll: true}); code.select(); status.textContent = messages.manual;
    }
  });
 }
 document.addEventListener('help:navigated', init);
 init();
})();
