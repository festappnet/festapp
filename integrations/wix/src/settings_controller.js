import {PROPERTIES, HELP_URL, DEFAULT_TITLE, settingsFrom} from './config.js';

export async function saveSettings(api, values) {
  const settings = settingsFrom(values);
  // Wix propagates custom-element attributes asynchronously after setProp resolves.
  // Confirm each write before touching sibling props; never repeat the write itself.
  for (const name of PROPERTIES) {
    await api.setProp(name, settings[name]);
    const deadline = Date.now() + 5000;
    while (await api.getProp(name) !== settings[name]) {
      if (Date.now() >= deadline) throw new Error('Nastavení se nepodařilo potvrdit. Zkuste uložit znovu.');
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }
}

export async function initSettings(document, api) {
  const form = document.querySelector('form');
  const status = document.getElementById('status');
  const submit = document.querySelector('button[type="submit"]');
  document.getElementById('help').href = HELP_URL;
  let ready = false;
  const controls = [...form.querySelectorAll('input, button')];
  const setBusy = busy => {
    form.setAttribute('aria-busy', String(busy));
    for (const control of controls) control.disabled = busy;
  };
  setBusy(true);
  try {
    for (const name of PROPERTIES) {
      const value = await api.getProp(name);
      const input = form.elements.namedItem(name);
      if (input.type === 'checkbox') input.checked = value !== 'false';
      else input.value = value || (name === 'form-title' ? DEFAULT_TITLE : '');
    }
    ready = true;
    status.textContent = '';
    setBusy(false);
  } catch {
    form.setAttribute('aria-busy', 'false');
    status.textContent = 'Nastavení nelze načíst. Otevřete tento panel přímo v editoru Wix a zkuste to znovu.';
  }
  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (!ready || submit.disabled) return;
    setBusy(true); status.textContent = 'Ukládání…';
    // Keep progress and the result visible in Wix's small settings viewport.
    const panel = form.closest('main');
    if (panel) panel.scrollTop = 0;
    try {
      await saveSettings(api, {
        'form-url': form.elements.namedItem('form-url').value,
        'form-title': form.elements.namedItem('form-title').value,
        'inherit-style': String(form.elements.namedItem('inherit-style').checked),
      });
      status.textContent = 'Uloženo. Formulář ověřte na zveřejněném webu.';
    } catch (error) { status.textContent = error.message || 'Nastavení nelze uložit. Zkuste to znovu.'; }
    finally { setBusy(false); }
  });
}
