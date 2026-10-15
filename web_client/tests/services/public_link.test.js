import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { canonicalPublicPath } from '../../src/services/public_link.js';

test('resolved aliases retain subpage, raw query and capability bytes', () => {
    for (const old of ['a', 'b']) {
        assert.equal(canonicalPublicPath(`/form/${old}?preview=true&x=%2f#order?token=secret`, 'form', old, 'c'),
            '/form/c?preview=true&x=%2f#order?token=secret');
        assert.equal(canonicalPublicPath(`/${old}/admin/forms/form-old/design?q=1#anchor`, 'occasion', old, 'c'),
            '/c/admin/forms/form-old/design?q=1#anchor');
    }
    assert.equal(canonicalPublicPath('/form/a', 'form', 'a', 'a'), '/form/a');
    assert.equal(canonicalPublicPath('/form/other', 'form', 'a', 'c'), '/form/other');
    assert.equal(canonicalPublicPath('https://foreign.invalid/form/a', 'form', 'a', 'c'), 'https://foreign.invalid/form/a');
});
test('canonicalization replaces the URL without navigation or an extra history entry', async () => {
    globalThis.window = new JSDOM('', { url: 'https://tickets.invalid/form/a?preview=true#waitlist?token=secret' }).window;
    const { RouterService } = await import('../../src/services/router_service.js');
    window.history.replaceState({ overlay: 'keep' }, '', window.location.href);
    const count = window.history.length;
    RouterService.canonicalizePublicLink('form', 'a', 'c');
    assert.equal(window.location.href, 'https://tickets.invalid/form/c?preview=true#waitlist?token=secret');
    assert.equal(window.history.length, count);
    assert.deepEqual(window.history.state, { overlay: 'keep' });
});
