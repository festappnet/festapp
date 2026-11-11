(() => {
 const initialized = new WeakSet();
 function initCodeExamples() {
  document.querySelectorAll('[data-code-example]').forEach(example => {
    if (initialized.has(example)) return;
    initialized.add(example);
    const code = example.querySelector('code');
    const status = example.querySelector('[role="status"]');
    const english = document.documentElement.lang === 'en';
    example.querySelector('[data-copy-code]').addEventListener('click', async () => {
      try {
        if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
        await navigator.clipboard.writeText(code.textContent);
        status.textContent = english ? 'Code copied.' : 'Kód byl zkopírován.';
      } catch {
        code.focus({preventScroll: true});
        const range = document.createRange();
        range.selectNodeContents(code);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        status.textContent = english ? 'Code selected. Copy it with Ctrl+C or ⌘C.' : 'Kód je označený. Zkopírujte ho pomocí Ctrl+C nebo ⌘C.';
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
  const english = document.documentElement.lang === 'en';
  const text = english ? {
    invalid: `Paste a saved public form link such as ${origin}/form/your-form, without query parameters or a # fragment.`,
    title: 'Order form', link: 'Open the form in a new tab',
    ready: 'Your code is ready. Copy it into a custom HTML block on your website.',
    copied: 'Code copied.', manual: 'Code selected. Copy it with Ctrl+C or ⌘C.'
  } : {
    invalid: `Vložte veřejný odkaz uloženého formuláře ve tvaru ${origin}/form/vas-formular, bez parametrů a bez části za #.`,
    title: 'Objednávkový formulář', link: 'Otevřít formulář v nové kartě',
    ready: 'Kód je připravený. Zkopírujte ho do HTML bloku svého webu.',
    copied: 'Kód byl zkopírován.', manual: 'Kód je označený. Zkopírujte ho pomocí Ctrl+C nebo ⌘C.'
  };
  const urlInput = form.querySelector('[name="form-url"]');
  const mode = form.querySelector('[name="height-mode"]');
  const hostDataLayer = form.querySelector('[name="host-datalayer"]');
  const output = form.querySelector('[data-embed-output]');
  const code = output.querySelector('textarea');
  const status = form.querySelector('[role="status"]');
  const error = form.querySelector('[data-url-error]');
  const escape = text => text.replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const invalidate = () => { output.hidden = true; status.textContent = ''; error.textContent = ''; urlInput.removeAttribute('aria-invalid'); };
  urlInput.addEventListener('input', invalidate);
  mode.addEventListener('change', invalidate);
  hostDataLayer.addEventListener('change', invalidate);
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
    const automatic = mode.value === 'automatic';
    const marker = ' data-festapp-embed' +
      (automatic ? '' : ' data-festapp-height="fixed"') +
      (hostDataLayer.checked ? ' data-festapp-datalayer' : '');
    // Match the child canvas from creation, before the deferred helper can run.
    const frame = `<iframe${marker} src="${escape(url.href + '?embed=1')}" title="${text.title}" allow="clipboard-write" height="800" style="display:block;width:100%;max-width:100%;border:0;color-scheme:light dark" loading="lazy"></iframe>`;
    const link = `<p><a href="${escape(url.href)}" target="_blank" rel="noopener noreferrer">${text.link}</a></p>`;
    code.value = `<div data-festapp-embed-host>\n${frame}\n${link}\n</div>\n<script src="${origin}/embed.js" defer></script>`;
    output.hidden = false; output.querySelector('[data-form-link]').href = url.href;
    status.textContent = text.ready;
  });
  form.querySelector('[data-copy-embed]').addEventListener('click', async () => {
    try {
      if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
      await navigator.clipboard.writeText(code.value); status.textContent = text.copied;
    } catch {
      code.focus({preventScroll: true}); code.select(); status.textContent = text.manual;
    }
  });
 }
 document.addEventListener('help:navigated', init);
 init();
})();
