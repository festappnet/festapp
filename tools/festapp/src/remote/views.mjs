const escape = value => String(value).replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]);
export const page = (title, body) => `<!doctype html><html lang="cs"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escape(title)} | Festapp</title><style>
:root{font:16px/1.5 system-ui;color:#1b2421;background:#f7f8f7}body{max-width:560px;margin:48px auto;padding:0 24px}h1{font-size:1.7rem}label{display:block;margin:16px 0 4px}input:not([type=checkbox]){box-sizing:border-box;width:100%;padding:12px;border:1px solid #68746d;border-radius:6px;font:inherit}input[type=checkbox]{width:24px;height:24px;vertical-align:middle;margin-right:8px}button{font:inherit;min-height:48px;padding:8px 20px;border:1px solid #174d37;border-radius:6px;background:#174d37;color:white;margin:16px 8px 0 0}button.secondary{background:white;color:#174d37}:focus-visible{outline:3px solid #b46d00;outline-offset:3px}.error{border-left:4px solid #b02618;padding:8px 16px}small{display:block;color:#44524a}fieldset{margin:24px 0;padding:16px;border:1px solid #68746d}a{color:#174d37}</style><main><p>Festapp</p><h1>${escape(title)}</h1>${body}</main></html>`;

export const loginForm = ({ csrf, client, action, error = '', consent = false }) => page(
    consent ? 'Připojit účet' : 'Správa připojení',
    `${error ? `<p class="error" role="alert">${escape(error)}</p>` : ''}
    <p>${consent ? `Přihlas se svým účtem Festapp pro připojení aplikace <strong>${escape(client)}</strong>. V dalším kroku vybereš akce a potvrdíš přístup.` : 'Přihlas se účtem Festapp pro zobrazení a odpojení svých propojených aplikací.'}</p>
    <form method="post" action="${escape(action)}"><input type="hidden" name="csrf" value="${escape(csrf)}">
    <label for="email">E-mail</label><input id="email" name="email" type="email" required autocomplete="username" maxlength="320">
    <label for="password">Heslo</label><input id="password" name="password" type="password" required autocomplete="current-password" maxlength="1024">
    <button type="submit">Přihlásit se</button>${consent ? '<button class="secondary" name="cancel" value="1" formnovalidate>Zrušit</button>' : ''}</form>
    <small>Heslo ani přihlašovací token Festapp se nepředává připojené aplikaci.</small>`,
);

export const consentForm = ({ csrf, client, action, occasions, selectedTenant }) => page('Povolit přístup',
    `<p>Aplikace <strong>${escape(client)}</strong> žádá o přístup k účtu v ${escape(selectedTenant)}.</p>
    <p>Může číst tvoji identitu a vzhled vstupenek u akcí, které vybereš. Nemůže měnit vstupenky, spustit prodej ani odesílat e-maily.</p>
    <form method="post" action="${escape(action)}"><input type="hidden" name="csrf" value="${escape(csrf)}">
    <fieldset><legend>Vyber akce, ke kterým povolíš přístup</legend>${occasions.map(o => `<label><input type="checkbox" name="occasion" value="${o.id}">${escape(o.title)}</label>`).join('')}</fieldset>
    <p>Přístup vyprší za 7 dní. Kdykoliv jej můžeš odvolat ve <a href="/connections" target="_blank" rel="noopener">správě připojení</a>.</p>
    <button type="submit">Povolit přístup</button><button class="secondary" name="cancel" value="1">Nepovolit</button></form>`,
);

export const connectionsPage = (csrf, grants, clients) => page('Připojené aplikace',
    `${grants.length ? grants.map(g => `<section><h2>${escape(clients.find(c => c.id === g.clientId)?.name ?? 'Aplikace')}</h2><p>Čtení vzhledu vstupenek pro ${g.occasions.length} akcí. Platnost do ${escape(new Date(g.expiresAt).toLocaleDateString('cs-CZ'))}.</p><form method="post" action="/connections/revoke"><input type="hidden" name="csrf" value="${escape(csrf)}"><input type="hidden" name="grant" value="${escape(g.id)}"><button type="submit">Odpojit</button></form></section>`).join('') : '<p>Nemáš žádné aktivní připojení.</p>'}
    <form method="post" action="/connections/logout"><input type="hidden" name="csrf" value="${escape(csrf)}"><button class="secondary" type="submit">Odhlásit správu připojení</button></form>`,
);
