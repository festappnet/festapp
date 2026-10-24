import { FormModel } from '../../src/components/forms/form_models.js';
import { publicPageSeo } from '../../src/services/public_page_seo.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { SeoService } from '../../src/services/seo_service.js';
import { AppConfig } from '../../src/app_config.js';

test('SPA form changes update canonical, share URLs and images without retaining the previous event', () => {
    const dom = new JSDOM('<!doctype html><head><link rel="canonical" href="https://tickets.invalid/"></head>', { url: 'https://tickets.invalid/' });
    globalThis.window = dom.window;
    globalThis.document = dom.window.document;
    globalThis.DOMParser = dom.window.DOMParser;
    AppConfig.appTitleShort = 'vstupenky.online';
    SeoService.updateMetaTags({ title: 'First', header: '<p>First description</p><img src="https://images.invalid/first.png" width="1200" height="630">' }, 'https://tickets.invalid/form/first?campaign=mail#section');
    assert.equal(document.querySelector('link[rel=canonical]').href, 'https://tickets.invalid/form/first');
    assert.equal(document.querySelector('meta[property="og:image"]').content, 'https://images.invalid/first.png');
    SeoService.updateMetaTags({ title: 'Second', description: 'Second description' }, 'https://tickets.invalid/form/second?campaign=another');
    assert.equal(document.title, 'Second - vstupenky.online');
    for (const property of ['og:url', 'twitter:url']) {
        assert.equal(document.querySelector(`meta[property="${property}"],meta[name="${property}"]`).content, 'https://tickets.invalid/form/second');
    }
    assert.equal(document.querySelector('link[rel=canonical]').href, 'https://tickets.invalid/form/second');
    for (const property of ['og:image', 'twitter:image']) {
        assert.equal(document.querySelector(`meta[property="${property}"],meta[name="${property}"]`).content, 'https://tickets.invalid/android-chrome-512x512.png');
    }
    assert.equal(document.querySelector('meta[property="og:image:width"]'), null);
    assert.equal(document.querySelector('meta[property="og:image:height"]'), null);
});


test('tenant www URL canonicalizes to configured HTTPS apex without tracking or fragment', () => {
    const dom = new JSDOM('<!doctype html><head></head>', { url: 'https://www.vstupenky.online/' });
    globalThis.window = dom.window; globalThis.document = dom.window.document; globalThis.DOMParser = dom.window.DOMParser;
    const previous = AppConfig.webLink; AppConfig.webLink = 'https://vstupenky.online';
    try {
        SeoService.updateMetaTags({ title: 'Apex form' }, 'https://www.vstupenky.online/form/live?utm_source=mail#section');
        assert.equal(document.querySelector('link[rel=canonical]').href, 'https://vstupenky.online/form/live');
        assert.equal(document.querySelector('meta[property="og:url"]').content, 'https://vstupenky.online/form/live');
    } finally { AppConfig.webLink = previous; dom.window.close(); }
});


test('hydrated metadata equals the edge projection, including alias identity, entities and image', () => {
    const dom = new JSDOM('<!doctype html><head></head>', { url: 'https://tickets.invalid/form/old' });
    globalThis.window = dom.window; globalThis.document = dom.window.document;
    const seo = { title: 'Occasion', form_title: 'Tickets', form_description: '<p>Dinner&nbsp;&amp; music &#269;</p><script>bad()</script>', form_link: 'saved', image: 'posters/event.png' };
    const expected = publicPageSeo(seo, {origin:'https://tickets.invalid', siteName:AppConfig.appTitleShort, path:'/form/old'});
    SeoService.updateMetaTags(new FormModel({title:'Different fallback', seo}), dom.window.location.href);
    assert.equal(document.title, expected.title);
    assert.equal(document.querySelector('meta[name="description"]').content, 'Dinner & music č');
    assert.equal(document.querySelector('meta[property="og:image"]').content, expected.image);
    assert.equal(document.querySelector('link[rel="canonical"]').href, expected.canonical);
    dom.window.close();
});

test('event date follows the selected interface language', async () => {
    const { LocalizationService } = await import('../../src/services/localization_service.js');
    const previous = LocalizationService.currentLocale;
    try {
        const date = new Date(2026, 9, 23);
        LocalizationService.currentLocale = 'cs';
        assert.equal(SeoService._formatDate(date), '23. 10. 2026');
        LocalizationService.currentLocale = 'en';
        assert.equal(SeoService._formatDate(date), '10/23/2026');
    } finally {
        LocalizationService.currentLocale = previous;
    }
});
