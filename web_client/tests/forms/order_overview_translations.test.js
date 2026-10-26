import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
for (const locale of ['cs', 'en', 'sk', 'de', 'pl', 'uk']) {
    test(`customer overview translations ship to the standalone web: ${locale}`, () => {
        const canonical = JSON.parse(readFileSync(new URL(`../../../assets/translations/${locale}.json`, import.meta.url), 'utf8'));
        const served = JSON.parse(readFileSync(new URL(`../../public/assets/translations/${locale}.json`, import.meta.url), 'utf8'));
        assert.deepEqual(served.OrderOverview, canonical.OrderOverview);
    });
}
