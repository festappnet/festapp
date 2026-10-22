import assert from 'node:assert/strict';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { build } from 'vite';
import { APP_VERSION } from '../../src/version.js';

test('production HTML, form and landing share one identity for account services', async () => {
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
    const landing = output.find(chunk => chunk.type === 'chunk' && chunk.name === 'landing');
    const chunks = new Map(output.filter(chunk => chunk.type === 'chunk').map(chunk => [chunk.fileName, chunk]));
    function dependencies(fileName, reached = new Set()) {
        if (reached.has(fileName)) return reached;
        reached.add(fileName);
        for (const dependency of chunks.get(fileName)?.imports || []) dependencies(dependency, reached);
        return reached;
    }
    // Shared services may live in an extracted chunk when multiple entries use
    // them. Verify their actual module identities rather than a Rollup layout.
    for (const service of ['rights_service.js', 'supabase_service.js', 'theme_service.js']) {
        const owners = [...chunks.values()].flatMap(chunk => Object.keys(chunk.modules)
            .filter(id => id.split('?')[0].endsWith('/services/' + service))
            .map(id => ({ chunk: chunk.fileName, id })));
        assert.equal(owners.length, 1, `${service} must execute as one module, including query aliases`);
        for (const consumer of [entry.pathname.slice(1), form.fileName, landing.fileName]) {
            assert.ok(dependencies(consumer).has(owners[0].chunk), `${consumer} must use the canonical ${service}`);
        }
    }
});
