import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { LocalizationService } from '../../src/services/localization_service.js';
import { CommonStrings } from '../../src/components/shared/common_strings.js';

for (const locale of ['cs', 'en']) {
    test(`published ${locale} MCP consent uses its canonical dictionary`, async () => {
        const published = JSON.parse(await readFile(new URL(`../../public/assets/translations/${locale}.json`, import.meta.url), 'utf8'));
        const canonical = JSON.parse(await readFile(new URL(`../../../assets/translations/${locale}.json`, import.meta.url), 'utf8'));
        assert.ok(canonical.McpConnection);
        assert.deepEqual(published.McpConnection, canonical.McpConnection);
    });
}

for (const [locale, expected] of [['cs', 'Založit zdarma'], ['en', '+ Event'], ['uk', '+ Подія']]) {
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


test('abuse errors have the same localized message in every published locale',async()=>{
 for(const language of ['cs','de','en','pl','sk','uk']) {
  const canonical=JSON.parse(await readFile(new URL(`../../../assets/translations/${language}.json`,import.meta.url),'utf8'));
  const published=JSON.parse(await readFile(new URL(`../../public/assets/translations/${language}.json`,import.meta.url),'utf8'));
  assert.ok(canonical.Common.resourceLimited);
  assert.equal(published.Common.resourceLimited,canonical.Common.resourceLimited);
 }
});

for (const locale of ['cs', 'en', 'sk', 'de', 'pl', 'uk']) {
    test(`published ${locale} scanner uses the canonical catalog`, async t => {
        const original = LocalizationService.translations;
        t.after(() => { LocalizationService.translations = original; });
        const published = JSON.parse(await readFile(new URL(`../../public/assets/translations/${locale}.json`, import.meta.url), 'utf8'));
        const canonical = JSON.parse(await readFile(new URL(`../../../assets/translations/${locale}.json`, import.meta.url), 'utf8'));
        assert.deepEqual(published.Scanner, canonical.Scanner);
        LocalizationService.translations = published;
        const { tr } = await import('../../src/components/scan/scan_strings.js');
        assert.notEqual(tr('camera_ready'), 'camera_ready');
        assert.notEqual(tr('settings'), 'settings');
    });
}

for (const locale of ['cs', 'en', 'sk', 'de', 'pl', 'uk']) {
    test(`published ${locale} standing controls use the canonical catalog and plural forms`, async t => {
        const original = {locale: LocalizationService.currentLocale, translations: LocalizationService.translations};
        t.after(() => {LocalizationService.currentLocale = original.locale; LocalizationService.translations = original.translations;});
        const published = JSON.parse(await readFile(new URL(`../../public/assets/translations/${locale}.json`, import.meta.url), 'utf8'));
        const canonical = JSON.parse(await readFile(new URL(`../../../assets/translations/${locale}.json`, import.meta.url), 'utf8'));
        assert.deepEqual(published.FeatureBlueprint, canonical.FeatureBlueprint);
        LocalizationService.currentLocale = locale; LocalizationService.translations = published;
        const {BlueprintStrings} = await import('../../src/components/blueprint/blueprint_strings.js');
        for (const count of [0,1,2,5,21]) {
            const plural = new Intl.PluralRules(locale).select(count);
            assert.equal(BlueprintStrings.placeCount(count), published.FeatureBlueprint.viewer[`placeCount_${plural}`].replace('{count}',count));
        }
        assert.equal(BlueprintStrings.chooseQuantity, published.FeatureBlueprint.viewer.chooseQuantity);
        assert.ok(BlueprintStrings.chooseQuantity);
        assert.notEqual(BlueprintStrings.viewerMessages.confirmQuantity, 'FeatureBlueprint.viewer.confirmQuantity');
    });
}
