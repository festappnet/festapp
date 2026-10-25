(() => {
 const initialized = new WeakSet();
 function init() {
  const form = document.querySelector('[data-embed-generator]');
  if (!form || initialized.has(form)) return;
  initialized.add(form);
  const origin = form.dataset.formOrigin || 'https://vstupenky.online';
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
  const inherit = form.querySelector('[name="inherit-style"]');
  const output = form.querySelector('[data-embed-output]');
  const code = output.querySelector('textarea');
  const status = form.querySelector('[role="status"]');
  const error = form.querySelector('[data-url-error]');
  const escape = text => text.replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const invalidate = () => { output.hidden = true; status.textContent = ''; error.textContent = ''; urlInput.removeAttribute('aria-invalid'); };
  urlInput.addEventListener('input', invalidate);
  mode.addEventListener('change', () => { inherit.disabled = mode.value === 'fixed'; invalidate(); });
  inherit.addEventListener('change', invalidate);
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
    const marker = automatic ? ' data-festapp-embed' + (inherit.checked ? ' data-festapp-style="inherit"' : '') : '';
    const frame = `<iframe${marker} src="${escape(url.href + '?embed=1')}" title="${text.title}" width="100%" height="800" style="border:0;max-width:100%" loading="lazy"></iframe>`;
    const link = `<p><a href="${escape(url.href)}" target="_blank" rel="noopener noreferrer">${text.link}</a></p>`;
    code.value = automatic ? `<div data-festapp-embed-host>\n${frame}\n${link}\n</div>\n<script src="${origin}/embed.js" defer></script>` : frame + '\n' + link;
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
