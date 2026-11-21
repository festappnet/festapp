import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { register } from 'node:module';
import test from 'node:test';
import { JSDOM } from 'jsdom';
register('../css_loader.mjs', import.meta.url);
const dom = new JSDOM('<body></body>', { url: 'https://vstupenky.online/' });
Object.assign(globalThis, { window: dom.window, document: dom.window.document,
    HTMLElement: dom.window.HTMLElement, customElements: dom.window.customElements });
const { AccountSecurityPanel } = await import('../../src/components/users/account_security_panel.js');
const { AppConfig } = await import('../../src/app_config.js');
const { LocalizationService } = await import('../../src/services/localization_service.js');
const { PasskeyService } = await import('../../src/services/passkey_service.js');
test.after(() => dom.window.close());

test('enrollment explains which change needs password verification and can be cancelled', async t => {
    AppConfig.appName = 'vstupenky.online';
    LocalizationService.translations = JSON.parse(readFileSync(
        new URL('../../../assets/translations/cs.json', import.meta.url), 'utf8'));
    t.mock.method(PasskeyService, 'supportsRegistration', () => true);

    const session = { user: { id: 'pilot' } };
    const panel = new AccountSecurityPanel({
        auth: { getSession: async () => ({ data: { session } }) },
        rpc: async () => ({ data: 'proof_required' }),
    }, 'pilot');
    panel.methods = {
        passkey: { offer: true, registration: true },
        totp: { offer: true, registration: true },
    };
    dom.window.document.body.append(panel.root);

    for (const [method, action] of [['passkey', 'Přidat passkey'], ['totp', 'Přidat ověřovací aplikaci']]) {
        await panel.run(signal => panel.enroll(method, signal));
        const password = panel.root.querySelector('input[type="password"]');
        assert.equal(password.autocomplete, 'current-password');
        const buttons = [...panel.root.querySelectorAll('button')];
        assert.deepEqual(buttons.map(button => button.textContent), ['Ověřit totožnost', 'Zrušit']);
        assert.equal(panel.root.querySelector('h3').textContent, action);
        assert.match(panel.root.textContent, /heslo k účtu na vstupenky\.online/);
        buttons[1].click();
        assert.equal(panel.root.querySelector('form'), null);
        assert.ok([...panel.root.querySelectorAll('button')].some(button => button.textContent === action));
    }
});
