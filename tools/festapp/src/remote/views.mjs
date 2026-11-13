import { CONNECTION_DURATION_DAYS, DEFAULT_CONNECTION_DURATION_DAYS, CONNECTION_IDLE_SECONDS, DAY_SECONDS, consentDeadline } from '../../../../packages/festapp_contracts/mcp-connection.mjs';
import { accessSelection } from '../operations/access.mjs';
import cs from '../../../../assets/translations/cs.json' with { type: 'json' };
import { MCP_CONSENT_MODES, MCP_PERMISSIONS } from '../../../../packages/festapp_contracts/mcp-permissions.mjs';
const escape = value => String(value).replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]);
export function oauthFailure(code) {
    const messages = {
        invalid_redirect_uri: 'Návratová adresa klienta neodpovídá jeho registraci. Zkontrolujte registraci tohoto klienta na serveru. Pro MCP Inspector použijte jeho vlastní registraci a návratovou adresu zobrazenou v Inspectoru.',
        invalid_client: 'Klient není zaregistrován nebo nelze ověřit jeho metadata. Zkontrolujte ID klienta a registraci, případně povolený původ jeho metadat. Registrace doplňku ChatGPT není určena obecným MCP klientům.',
        invalid_client_metadata: 'Metadata klienta nejsou platná nebo nesplňují pravidla tohoto serveru. Zkontrolujte identitu dokumentu, typ klienta a jeho návratové adresy.',
        invalid_scope: 'Požadované funkce nejsou pro tuto registraci klienta dostupné. Zkontrolujte požadovaná oprávnění a jejich závislosti; obecný MCP klient a veřejný doplněk ChatGPT mají samostatné registrace.',
    };
    const message = messages[code] ?? 'Požadavek není platný nebo vypršel. Spusťte připojení znovu v aplikaci.';
    return page('Připojení se nezdařilo', `<p>${message}</p>${Object.hasOwn(messages, code) ? `<p>Kód: <code>${code}</code></p>` : ''}`);
}
export const page = (title, body, language = 'cs') => `<!doctype html><html lang="${escape(language)}"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escape(title)} | Festapp</title><style>
:root{font:16px/1.5 system-ui;color:#1b2421;background:#f7f8f7}body{max-width:560px;margin:48px auto;padding:0 24px}h1{font-size:1.7rem}label{display:block;margin:16px 0 4px}input:not([type=checkbox]){box-sizing:border-box;width:100%;padding:12px;border:1px solid #68746d;border-radius:6px;font:inherit}input[type=checkbox]{width:24px;height:24px;vertical-align:middle;margin-right:8px}button{font:inherit;min-height:48px;padding:8px 20px;border:1px solid #174d37;border-radius:6px;background:#174d37;color:white;margin:16px 8px 0 0}button.secondary{background:white;color:#174d37}:focus-visible{outline:3px solid #b46d00;outline-offset:3px}.error{border-left:4px solid #b02618;padding:8px 16px}small{display:block;color:#44524a}form:has(select[name=permissionMode] option[value=basic]:checked) .permission-list{display:none}form:has(select[name=permissionMode] option[value=read-only]:checked) .permission-list li[data-write]{display:none}fieldset{margin:24px 0;padding:16px;border:1px solid #68746d}a{color:#174d37}form:has(select[name=durationDays] option:checked:not([value="365"])) .long-duration-hint{display:none}</style><main><p>Festapp</p><h1>${escape(title)}</h1>${body}</main></html>`;

export const loginForm = ({ csrf, client, action, error = '', consent = false }) => page(
    consent ? 'Připojit účet' : 'Správa připojení',
    `${error ? `<p class="error" role="alert">${escape(error)}</p>` : ''}
    <p>${consent ? `Přihlaste se svým účtem Festapp pro připojení aplikace <strong>${escape(client)}</strong>. V dalším kroku vyberete akce a potvrdíte přístup.` : 'Přihlaste se účtem Festapp pro zobrazení a odpojení svých propojených aplikací.'}</p>
    <form method="post" action="${escape(action)}"><input type="hidden" name="csrf" value="${escape(csrf)}">
    <label for="email">E-mail</label><input id="email" name="email" type="email" required autocomplete="username" maxlength="320">
    <label for="password">Heslo</label><input id="password" name="password" type="password" required autocomplete="current-password" maxlength="1024">
    <button type="submit">Přihlásit se</button>${consent ? '<button class="secondary" name="cancel" value="1" formnovalidate>Zrušit</button>' : ''}</form>
    <small>Heslo ani přihlašovací token Festapp se nepředává připojené aplikaci.</small>`,
);

export const consentForm = ({ csrf, client, action, occasions, units = [], selectedTenant, connections = [], permissions = [], canCreate = false, api, maxConsentDays = 365 }) => page('Povolit přístup',
    `<p>Aplikace <strong>${escape(client)}</strong> žádá o přístup k účtu v ${escape(selectedTenant)}.</p>
    ${api ? `<p>API: <code>${escape(api.resource)}</code><br>Data: <code>${escape(api.dataProfile)}</code></p>` : ''}
    <p>Přístup aplikace se řídí Vašimi aktuálními právy ve vybraných akcích. Při každém úkonu je ověřuje server. Výběr celého pořadatele zahrnuje i jeho budoucí akce.</p>
    <form method="post" action="${escape(action)}"><input type="hidden" name="csrf" value="${escape(csrf)}"><input type="hidden" name="consentVersion" value="3">
    ${permissions.length || canCreate ? `<label>Rozsah funkcí<select name="permissionMode">${MCP_CONSENT_MODES.map(mode => `<option value="${mode}">${{ requested: 'Všechny požadované funkce', 'read-only': 'Jen požadované čtení', basic: 'Základní přístup' }[mode]}</option>`).join('')}</select></label><small>Základní přístup zahrnuje pouze informace o připojení, přehled dostupných akcí a podklady vstupenek. Ostatní volby povolí odpovídající požadované funkce v mezích vašich aktuálních práv.</small>` : ''}
    ${permissions.length ? `<ul class="permission-list">${permissions.map(scope => `<li${scope.endsWith(':read') ? '' : ' data-write'}>${escape(cs.McpConnection[MCP_PERMISSIONS[scope].label])}</li>`).join('')}</ul>` : ''}
    ${connections.length ? `<fieldset><legend>Připojení</legend><label><input type="radio" name="mode" value="replace" ${connections.some(c => c.defaultEligible) ? 'checked' : ''}>Nahradit</label><label><input type="radio" name="mode" value="new">Nové zařízení (zadejte název)</label><label>Připojení k nahrazení<select name="connectionId">${connections.some(c => c.defaultEligible) ? '' : '<option value="" selected>Vyberte připojení</option>'}${connections.map(c => `<option value="${escape(c.id)}" ${c.id === connections.find(item => item.defaultEligible)?.id ? 'selected' : ''}>${escape(c.name || client)} · ${escape(new Date(c.expiresAt).toLocaleString('cs-CZ'))} · ${escape(c.access.units.map(u => `Pořadatel #${u.unitId}, včetně budoucích akcí${u.canCreateOccasions ? ' a zakládání akcí' : ''}`).join('; '))} ${escape(c.access.occasionIds.map(id => `Akce #${id}`).join('; '))}</option>`).join('')}</select></label><p>Původní připojení se odpojí až po úspěšné výměně kódu za tokeny. Nové přístupy schvalujete níže.</p></fieldset>` : '<input type="hidden" name="mode" value="new">'}
    <label>Platnost připojení<select name="durationDays">${CONNECTION_DURATION_DAYS.filter(days=>days<=maxConsentDays).map(days => `<option value="${days}" ${days === DEFAULT_CONNECTION_DURATION_DAYS ? 'selected' : ''}>${days === 365 ? '1 rok' : `${days} dní`} - při potvrzení nyní do ${escape(new Date(consentDeadline(days)).toLocaleString('cs-CZ'))}</option>`).join('')}</select></label>
    <p>Připojení skončí nejpozději po zvolené době nebo po ${CONNECTION_IDLE_SECONDS / DAY_SECONDS} dnech bez obnovy tokenu. Přihlášení k účtu může skončit dříve. Název je pouze Váš štítek, nikoli ověřená identita zařízení.</p>
    <p class="long-duration-hint">Pokud zvolíte 1 rok, přístup bude platit dlouho. Kdykoli jej můžete odebrat ve správě připojení.</p>
    <label>Název zařízení (nejvýše 80 znaků; pro další zařízení povinný)<input name="name" maxlength="80"></label>
    <fieldset><legend>Vyberte akce, ke kterým povolíte přístup</legend>${occasions.map(o => `<label><input type="checkbox" name="occasion" value="${o.id}">${escape(o.title)}</label>`).join('')}</fieldset>
    ${units.length ? `<label>Celý pořadatel (místo jednotlivých akcí, včetně budoucích)<select name="unit"><option value="">Jen vybrané akce</option>${units.map(u => `<option value="${u.id}">${escape(u.title)}</option>`).join('')}</select></label>` : ''}
    <p>Přístup vyprší po zvolené době; obnova tokenu tuto dobu neprodlužuje. Kdykoli jej můžete odvolat ve <a href="/connections" target="_blank" rel="noopener">správě připojení</a>.</p>
    <button type="submit">Povolit přístup</button><button class="secondary" name="cancel" value="1">Nepovolit</button></form>`,
);

export const connectionsPage = (csrf, grants) => page('Připojené aplikace',
    `${grants.length ? grants.map(g => `<section><h2>${escape(g.clientName ?? 'Aplikace')}${g.name ? ` · ${escape(g.name)}` : ''}</h2><p>${accessSelection(g.access).units.map(u => `Pořadatel #${u.unitId}, včetně budoucích akcí${u.canCreateOccasions ? ' a zakládání skrytých akcí' : ''}.`).join(' ')} ${accessSelection(g.access).occasionIds.length ? `Jednotlivé akce: ${accessSelection(g.access).occasionIds.length}.` : ''} Platnost do ${escape(new Date(g.expiresAt).toLocaleDateString('cs-CZ'))}.</p><form method="post" action="/connections/revoke"><input type="hidden" name="csrf" value="${escape(csrf)}"><input type="hidden" name="grant" value="${escape(g.id)}"><button type="submit">Odpojit</button></form></section>`).join('') : '<p>Nemáte žádné aktivní připojení.</p>'}
    <form method="post" action="/connections/logout"><input type="hidden" name="csrf" value="${escape(csrf)}"><button class="secondary" type="submit">Odhlásit správu připojení</button></form>`,
);

export const contextChoiceForm = ({ csrf, action, contexts }) => page('Vyberte prostředí Festapp',
    `<p>Vyberte prostředí svého účtu. Přihlášení a souhlas platí pouze pro toto prostředí. Pro další prostředí vytvořte nové připojení.</p>
    <form method="post" action="${escape(action)}"><input type="hidden" name="csrf" value="${escape(csrf)}">
    <label>Prostředí<select name="context" required>${contexts.map(c => `<option value="${escape(c.profile.binding)}">${escape(c.name)}</option>`).join('')}</select></label>
    <button type="submit">Pokračovat</button></form>`);

export const contextManagementPage = config => page('Správa připojení Festapp',
    `<p>Přihlaste se v prostředí, pro které jste přístup udělili.</p><ul>${config.contexts.map(c => {
        const target = new URL('/settings/connections', c.tenantOrigin);
        target.searchParams.set('issuer', config.issuer);
        return `<li><a href="${escape(target.href)}">${escape(c.name)}</a></li>`;
    }).join('')}</ul>`);

// Trusted canonical Markdown is presented through a small escaped transport
// adapter; the legal source is shared in automation/release/legal/.
export function publicDocument(source, language = 'en') {
    const blocks = source.trim().split(/\n\s*\n/);
    const title = blocks.shift().replace(/^# /, '');
    const body = blocks.map(block => block.startsWith('## ')
        ? `<h2>${escape(block.slice(3))}</h2>` : `<p>${escape(block.replaceAll('\n', ' '))}</p>`).join('');
    return page(title, `<nav><a href="/docs">Documentation</a> · <a href="/privacy">Privacy</a> · <a href="/terms">Terms</a> · <a href="/support">Support</a> · <a href="/cs/privacy">Česky</a></nav>${body}`, language);
}
export const serviceDocumentation = config => page(config.regionalPortal?.name ?? 'Festapp',
    `<p>Publisher: Festapp. Authenticated event management, including Festapp Tickets, within your current account rights and explicit connection consent.</p>
    <p>Streamable HTTP endpoint: <code>${escape(config.resource)}</code>. Start the connection in your registered MCP client with OAuth PKCE. Select one environment, sign in on its trusted first-party page, then approve organizers/events and functions. Each environment requires its own connection.</p>
    <p>Examples: list accessible events; inspect ticket artwork; read sales or order status when granted; create a hidden event under a selected organizer when explicitly granted. The tool catalog reflects the client's scopes, data profile and your consent. Writes retain application authorization, transaction and retry rules. Retry an uncertain write with the same command ID and payload.</p>
    <p>The server supports modern and legacy HTTP MCP clients tested with the official SDKs. Callback URLs must match a registration, or an expressly allowed client metadata document. Unrestricted dynamic registration is disabled. MFA session issuance is currently unsupported and fails closed. A profile may be read-only. Public ChatGPT order-summary access does not grant arbitrary clients operator access or imply ChatGPT publication approval.</p>
    <p>You need an authorized account in the selected environment. Existing service prices and event agreements apply; this listing adds no paid subscription. Revoke connections in the environment's account settings. <a href="/connections">Connection management</a>.</p>
    <p><a href="/privacy">Privacy</a> · <a href="/terms">Connection terms</a> · <a href="/support">Support</a> · <a href="/cs/privacy">Ochrana osobních údajů</a> · <a href="/cs/terms">Podmínky připojení</a></p>
    <p><a href="https://github.com/festappnet/festapp">MIT source and documentation</a>. Original copyright and dependency notices, including embedded native libraries and MPL source availability, are retained in the source and runtime distribution.</p>`, 'en');
