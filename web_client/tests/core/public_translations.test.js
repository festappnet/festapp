import assert from 'node:assert/strict';
import { readFile, mkdtemp, writeFile, rm, readlink, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
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

for (const locale of ['cs','en','sk','de','pl','uk']) {
 test(`published ${locale} sale notifications use the canonical dictionary`,async()=>{
  const canonical=JSON.parse(await readFile(new URL(`../../../assets/translations/${locale}.json`,import.meta.url),'utf8'));
  const published=JSON.parse(await readFile(new URL(`../../public/assets/translations/${locale}.json`,import.meta.url),'utf8'));
  assert.deepEqual(published.SaleOpening,canonical.SaleOpening);
  assert.ok(published.SaleOpening.subscribe);
 });
}

for (const locale of ['cs','en','sk','de','pl','uk']) {
 test(`published ${locale} account availability uses the canonical explanation`, async () => {
  const canonical=JSON.parse(await readFile(new URL(`../../../assets/translations/${locale}.json`,import.meta.url),'utf8'));
  const published=JSON.parse(await readFile(new URL(`../../public/assets/translations/${locale}.json`,import.meta.url),'utf8'));
  assert.ok(canonical.AccountConnections.appsUnavailable);
  assert.equal(published.AccountConnections.appsUnavailable,canonical.AccountConnections.appsUnavailable);
 });
}


test('development and built public catalogs use the canonical source for every locale', async () => {
    const {createServer, build} = await import('vite');
    const webRoot = fileURLToPath(new URL('../../', import.meta.url));
    const fixture = await mkdtemp(path.join(tmpdir(), 'festapp-canonical-catalogs-'));
    let server;
    try {
        await writeFile(path.join(fixture, 'index.html'), '<!doctype html><title>Catalog fixture</title>');
        await build({root: fixture, configFile: false, publicDir: path.join(webRoot, 'public'), logLevel: 'silent'});
        server = await createServer({root: webRoot, configFile: false, logLevel: 'error',
            server: {host: '127.0.0.1', port: 0}});
        await server.listen();
        const origin = server.resolvedUrls.local[0];
        const catalogDir = new URL('../../../assets/translations/', import.meta.url);
        const catalogs = (await readdir(catalogDir)).filter(filename => filename.endsWith('.json'));
        for (const filename of catalogs) {
            const canonical = JSON.parse(await readFile(new URL(filename, catalogDir), 'utf8'));
            const alias = path.join(webRoot, 'public/assets/translations', filename);
            assert.equal(await readlink(alias), `../../../../assets/translations/${filename}`, 'public source is a reference, not an editable second catalog');
            const response = await fetch(new URL(`/assets/translations/${filename}`, origin));
            assert.equal(response.status, 200);
            assert.deepEqual(await response.json(), canonical, `development catalog ${filename}`);
            assert.deepEqual(JSON.parse(await readFile(path.join(fixture, 'dist/assets/translations', filename), 'utf8')), canonical, `built catalog ${filename}`);
        }
    } finally {
        await server?.close();
        await rm(fixture, {recursive: true, force: true});
    }
});
