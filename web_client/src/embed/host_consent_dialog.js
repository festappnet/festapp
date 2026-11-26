const labels = {
    cs: { title: 'Objednávka', close: 'Zavřít', separate: 'Otevřít samostatně' },
    sk: { title: 'Objednávka', close: 'Zavrieť', separate: 'Otvoriť samostatne' },
    en: { title: 'Checkout', close: 'Close', separate: 'Open separately' },
};

export function openConsentCheckoutDialog(win, link, url) {
    const {document} = win;
    const dialog = document.createElement('dialog');
    if (typeof dialog.showModal !== 'function' || document.querySelector('dialog[data-festapp-consent-checkout][open]')) return false;
    const language = document.documentElement.lang.toLowerCase().split('-')[0];
    const copy = ['cs', 'sk'].includes(language) ? labels[language] : labels.en;
    const title = link.textContent.trim() || copy.title;
    dialog.setAttribute('data-festapp-consent-checkout', '');
    dialog.setAttribute('aria-label', title);
    Object.assign(dialog.style, {
        border: '0', borderRadius: '8px', boxSizing: 'border-box', padding: '8px',
        width: 'min(96vw, 900px)', height: '90vh', maxHeight: '90vh',
    });

    const controls = document.createElement('form');
    controls.method = 'dialog';
    controls.style.margin = '0 0 8px';
    const close = document.createElement('button');
    close.textContent = copy.close;
    close.autofocus = true;
    const separate = document.createElement('a');
    separate.href = url.href;
    separate.target = '_blank';
    separate.rel = 'noopener';
    separate.textContent = copy.separate;
    separate.style.marginInlineStart = '12px';
    controls.append(close, separate);

    const frame = document.createElement('iframe');
    const embedded = new URL(url);
    embedded.searchParams.set('embed', '1');
    frame.src = embedded.href;
    frame.title = title;
    frame.setAttribute('data-festapp-embed', '');
    frame.dataset.festappHeight = 'fixed';
    Object.assign(frame.style, {width: '100%', height: 'calc(100% - 2.5rem)', border: '0'});
    dialog.append(controls, frame);
    dialog.addEventListener('close', () => {
        dialog.remove();
        if (link.isConnected) link.focus({preventScroll: true});
    }, {once: true});
    document.body.append(dialog);
    try {
        dialog.showModal();
        return true;
    } catch {
        dialog.remove();
        return false;
    }
}
