import assert from 'node:assert/strict';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { build } from 'vite';
import { APP_VERSION } from '../../src/version.js';

test('production form imports the same versioned entry that HTML loads', async () => {
    const { output } = await build({
        root: fileURLToPath(new URL('../..', import.meta.url)),
        logLevel: 'silent',
        build: { write: false },
    });
    const html = output.find(asset => asset.fileName === 'index.html').source;
    const entry = new URL(html.match(/<script type="module"[^>]*src="([^"]+)"/)[1], 'https://app.test');
    assert.equal(entry.search, '', 'a query-only identity would execute the shared entry twice');
    assert.ok(entry.pathname.endsWith('-' + APP_VERSION.replace('+', '-') + '.js'), 'a new release must bypass cached entry failures');
    assert.ok(output.some(chunk => chunk.fileName === entry.pathname.slice(1)), 'the referenced entry must exist');
    const form = output.find(chunk => chunk.type === 'chunk' && chunk.name === 'form_page');
    assert.ok(form.imports.includes(entry.pathname.slice(1)), 'HTML and form dependencies must resolve to one module identity');
});
