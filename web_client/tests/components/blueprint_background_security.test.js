import test from 'node:test';
import assert from 'node:assert/strict';
import { loadLayoutAssets } from '@festapp/venue-layout';
const payload = '<svg xmlns="http://www.w3.org/2000/svg"><foreignObject><img xmlns="http://www.w3.org/1999/xhtml" src="x" onerror="globalThis.__blueprintExecuted=true"/></foreignObject></svg>';
const hash = 'a'.repeat(64);
test('active SVG is rejected before fetch by the actual shared resource boundary', async () => {
    let fetched = false;
    await assert.rejects(loadLayoutAssets({assets: {[`image:${hash}`]: {
        hash, mimeType: 'image/svg+xml', width: 1, height: 1,
        byteLength: payload.length, url: `data:image/svg+xml,${encodeURIComponent(payload)}`,
    }}}, {fetch: async () => {fetched = true; throw new Error('unreachable');}}), /invalid_asset_manifest/);
    assert.equal(fetched, false);
    assert.equal(globalThis.__blueprintExecuted, undefined);
});
test('an SVG body disguised as a raster is never made into an active DOM document', async () => {
    const bytes = new TextEncoder().encode(payload);
    await assert.rejects(loadLayoutAssets({assets: {[`image:${hash}`]: {
        hash, mimeType: 'image/png', width: 1, height: 1,
        byteLength: bytes.length, url: 'https://invalid.local/background.png',
    }}}, {fetch: async () => new Response(bytes)}), /asset_hash_mismatch/);
});
