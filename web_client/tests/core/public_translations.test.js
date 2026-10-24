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

for (const locale of ['cs', 'en', 'sk', 'de', 'pl', 'uk']) {
    test(`published ${locale} catalog explains temporary resource limits`, async t => {
        const original = LocalizationService.translations;
        t.after(() => { LocalizationService.translations = original; });
        const catalog = JSON.parse(await readFile(new URL(`../../public/assets/translations/${locale}.json`, import.meta.url), 'utf8'));
        const canonical = JSON.parse(await readFile(new URL(`../../../assets/translations/${locale}.json`, import.meta.url), 'utf8'));
        assert.equal(catalog.Common.resourceLimited, canonical.Common.resourceLimited);
        LocalizationService.translations = catalog;
        const { PublicOrderStrings } = await import('../../src/components/forms/public_order_strings.js');
        const { WaitlistStrings } = await import('../../src/components/forms/waitlist_strings.js');
        assert.equal(PublicOrderStrings.orderError(429), catalog.Common.resourceLimited);
        assert.equal(WaitlistStrings.text('ABUSE_LIMIT_EXCEEDED'), catalog.Common.resourceLimited);
    });
}
for(const locale of ['cs','en','sk','de','pl','uk']){
 test(`published ${locale} Stripe purchase and recovery labels match their canonical catalogs`,async()=>{
  const catalog=JSON.parse(await readFile(new URL(`../../public/assets/translations/${locale}.json`,import.meta.url),'utf8'));
  const canonical=JSON.parse(await readFile(new URL(`../../../assets/translations/${locale}.json`,import.meta.url),'utf8'));
  for(const namespace of ['CardPayments','CardPaymentConnection','PaymentMethods','CardRefundDecision'])assert.deepEqual(catalog[namespace],canonical[namespace]);
  assert.ok(catalog.PaymentMethods.orderAndPay);assert.ok(catalog.PaymentMethods.refreshFailed);
 });
}
