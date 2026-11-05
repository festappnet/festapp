import test from 'node:test';
import assert from 'node:assert/strict';
import { LocalizationService } from '../../src/services/localization_service.js';
import { browserStorage } from '../../src/services/browser_storage.js';
import { AppConfig } from '../../src/app_config.js';

for (const [locale, preference] of [['cs','en'],['en','cs']]) {
    test(`marketing ${locale} keeps its document language without overwriting app preference ${preference}`, async t => {
        const previous = {document:Object.getOwnPropertyDescriptor(globalThis,'document'),navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator'),locale:LocalizationService.currentLocale,translations:LocalizationService.translations,initialization:LocalizationService._initialization,preference:browserStorage.getItem(AppConfig.Keys.locale),shared:browserStorage.getItem('flutter.locale')};
        t.after(()=>{
            for(const key of ['document','navigator']) {
                if(previous[key]) Object.defineProperty(globalThis,key,previous[key]); else delete globalThis[key];
            }
            LocalizationService.currentLocale=previous.locale;LocalizationService.translations=previous.translations;LocalizationService._initialization=previous.initialization;
            if(previous.preference===null) browserStorage.removeItem(AppConfig.Keys.locale); else browserStorage.setItem(AppConfig.Keys.locale,previous.preference);
            if(previous.shared===null) browserStorage.removeItem('flutter.locale'); else browserStorage.setItem('flutter.locale',previous.shared);
        });
        Object.defineProperty(globalThis,'document',{configurable:true,value:{documentElement:{lang:locale}}});
        Object.defineProperty(globalThis,'navigator',{configurable:true,value:{language:preference+'-XX'}});
        browserStorage.setItem(AppConfig.Keys.locale,preference);
        browserStorage.removeItem('flutter.locale');
        LocalizationService._initialization=null;
        const fetched=[];
        t.mock.method(globalThis,'fetch',async url=>{fetched.push(url);return Response.json({label:locale});});
        await LocalizationService.init({locale,persist:false});
        assert.deepEqual(fetched,[`/assets/translations/${locale}.json`]);
        assert.equal(LocalizationService.currentLocale,locale);
        assert.equal(document.documentElement.lang,locale);
        assert.equal(browserStorage.getItem(AppConfig.Keys.locale),preference);
        assert.equal(LocalizationService.tr('label'),locale);
        // The ordinary application still honors the previously saved preference.
        LocalizationService._initialization=null;
        await LocalizationService.init();
        assert.equal(LocalizationService.currentLocale,preference);
        assert.equal(JSON.parse(browserStorage.getItem('flutter.locale')),preference);
    });
}


test('English public document works on a Czech-only tenant without enabling English in the app', async t => {
    const previous = {document:Object.getOwnPropertyDescriptor(globalThis,'document'),navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator'),languages:AppConfig.supportedLanguages,locale:LocalizationService.currentLocale,translations:LocalizationService.translations,initialization:LocalizationService._initialization};
    t.after(()=>{
        for(const key of ['document','navigator']) {
            if(previous[key]) Object.defineProperty(globalThis,key,previous[key]); else delete globalThis[key];
        }
        AppConfig.supportedLanguages=previous.languages;
        LocalizationService.currentLocale=previous.locale;LocalizationService.translations=previous.translations;LocalizationService._initialization=previous.initialization;
    });
    Object.defineProperty(globalThis,'document',{configurable:true,value:{documentElement:{lang:'en'}}});
    Object.defineProperty(globalThis,'navigator',{configurable:true,value:{language:'cs-CZ'}});
    AppConfig.supportedLanguages=['cs'];LocalizationService._initialization=null;
    const fetched=[];
    t.mock.method(globalThis,'fetch',async url=>{fetched.push(url);return Response.json({label:'English'});});
    const preference=browserStorage.getItem('flutter.locale');
    await LocalizationService.init({locale:'en',persist:false});
    assert.deepEqual(fetched,['/assets/translations/en.json']);
    assert.equal(LocalizationService.currentLocale,'en');
    assert.equal(LocalizationService.tr('label'),'English');
    assert.equal(browserStorage.getItem('flutter.locale'),preference);
    await assert.rejects(LocalizationService.setLocale('en'),/Unsupported locale/);
    await assert.rejects(LocalizationService.loadTranslations('xx',{persist:false}),/Unsupported locale/);
});
