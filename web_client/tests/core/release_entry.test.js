import assert from 'node:assert/strict';
import test from 'node:test';
import config from '../../vite.config.js';
import { APP_VERSION } from '../../src/version.js';

const transform = config.plugins.find(plugin => plugin.name === 'festapp-release-entry').transformIndexHtml.handler;
const html = '<script type="module" crossorigin src="/web-assets/index-unchanged.js"></script>';

test('an unchanged production entry hash gets this release cache key', () => {
    const built = transform(html, { bundle: {} });
    const src = built.match(/src="([^"]+)"/)[1];
    const url = new URL(src, 'https://app.test');
    assert.equal(url.pathname, '/web-assets/index-unchanged.js');
    assert.equal(url.searchParams.get('release'), APP_VERSION);
});

test('development HTML keeps its original entry URL', () => {
    assert.equal(transform(html, {}), html);
});
