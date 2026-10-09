import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { LocalizationService } from '../../src/services/localization_service.js';
import { CommonStrings } from '../../src/components/shared/common_strings.js';

for (const [locale, expected] of [['cs', '+ Akce'], ['en', '+ Event'], ['uk', '+ Подія']]) {
    test(`published ${locale} catalog translates the mobile create-event button`, async t => {
        const original = LocalizationService.translations;
        t.after(() => { LocalizationService.translations = original; });
        const publicCatalog = JSON.parse(await readFile(new URL(`../../public/assets/translations/${locale}.json`, import.meta.url), 'utf8'));
        const canonical = JSON.parse(await readFile(new URL(`../../../assets/translations/${locale}.json`, import.meta.url), 'utf8'));
        assert.equal(publicCatalog.FeatureUser.addEventShort, canonical.FeatureUser.addEventShort, 'the published web catalog must include the canonical label');
        LocalizationService.translations = publicCatalog;
        assert.equal(CommonStrings.addEventShort, expected, 'test the real web catalog, not mocked translations or an English fallback');
    });
}
