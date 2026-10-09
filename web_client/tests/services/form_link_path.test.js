import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
globalThis.window = new JSDOM('', { url: 'https://tickets.invalid/' }).window;
const { RouterService } = await import('../../src/services/router_service.js');

test('native card URLs decode their form slug once on initial navigation and history transitions', () => {
    for (const slug of ['camp-registration', 'tábor 2027', 'discount%20', 'form/alias']) {
        assert.equal(RouterService.getFormLink('/form/' + encodeURIComponent(slug)), slug);
    }
    assert.equal(RouterService.getFormLink('/form/'), null);
    assert.equal(RouterService.getFormLink('/form/bad%ZZ'), null);
    assert.equal(RouterService.getFormLink('/login'), null);
});
