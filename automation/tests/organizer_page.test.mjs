import {fileURLToPath} from 'node:url';
import {readConfig,resolveContext,publicManifest} from '../release/organizers/context.mjs';
import { helpActionWorkerSource } from '../lib/help_action_worker_source.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { symlinkSync, mkdtempSync, mkdirSync, cpSync, readFileSync, writeFileSync, existsSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

test('tenant generator produces truthful standalone HTML and removes page/nav on tenant switch', t => {
  const root = mkdtempSync(join(tmpdir(), 'festapp-seo-generator-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(join(root, 'automation/release'), { recursive: true });
  mkdirSync(join(root, 'web_client'), { recursive: true });
  cpSync(new URL('../../web_client/public', import.meta.url), join(root, 'web_client/public'), {recursive:true});
  cpSync(new URL('../release/platform_updates',import.meta.url),join(root,'automation/release/platform_updates'),{recursive:true,filter:source=>!source.includes('node_modules')});
  symlinkSync(fileURLToPath(new URL('../release/platform_updates/node_modules',import.meta.url)),join(root,'automation/release/platform_updates/node_modules'),'dir');
  cpSync(new URL('../../content/platform-updates',import.meta.url),join(root,'content/platform-updates'),{recursive:true});
  mkdirSync(join(root,'web_client/public'),{recursive:true});
  for (const name of ['brand-logo.svg','brand-logo-light.svg','brand-symbol.svg','brand-wordmark.svg','brand-wordmark-stacked.svg']) cpSync(new URL('../../web_client/public/'+name,import.meta.url),join(root,'web_client/public',name));
  cpSync(new URL('../../assets/brand/vstupenky-online',import.meta.url),join(root,'assets/brand/vstupenky-online'),{recursive:true,filter:source=>!['concepts','source','tools'].includes(source.split('/').pop())});
  mkdirSync(join(root,'automation/lib'),{recursive:true});
  cpSync(new URL('../lib/write_if_changed.cjs',import.meta.url),join(root,'automation/lib/write_if_changed.cjs'));
  cpSync(new URL('../release/render_organizer_page.mjs', import.meta.url), join(root, 'automation/release/render_organizer_page.mjs'));
  cpSync(new URL('../release/organizers', import.meta.url), join(root, 'automation/release/organizers'), { recursive: true });
  cpSync(new URL('../../web/organizers-media',import.meta.url),join(root,'web/organizers-media'),{recursive:true});
  cpSync(new URL('../../web_client/index.html', import.meta.url), join(root, 'web_client/index.html'));
  const config = join(root, 'automation/project.conf');
  writeFileSync(config, 'DOMAIN=vstupenky.online\nWEB_ORGANIZER_LANDING_ENABLED=true\nWEB_LINK=https://vstupenky.online\nAPP_NAME="Tickets & events"\nVERSION=0.0.1+1\nTHEME_SEED_3=#4465a6\nWEB_ORGANIZER_CONTENT_PROFILE=vstupenky-cs\nWEB_SUPPORTED_LANGUAGES=cs\nPRIVACY_URL=https://vstupenky.online/privacy/\nTERMS_URL=https://vstupenky.online/terms/\nSUPPORT_URL=https://vstupenky.online/support/\n');
  const render = () => {
    const run = spawnSync(process.execPath, [join(root, 'automation/release/render_organizer_page.mjs'), '--config', config], { encoding: 'utf8' });
    assert.equal(run.status, 0, run.stderr);
  };
  const prepare=spawnSync(process.execPath,[join(root,'automation/release/render_organizer_page.mjs'),'--config',config,'--catalog-only'],{encoding:'utf8'});
  assert.equal(prepare.status,0,prepare.stderr);
  assert.equal(existsSync(join(root,'web/organizers-page')),false,'compiler preparation does not render public documents');
  render();
  const output = join(root, 'web/organizers-page');
  const mtime=statSync(output).mtimeMs;
  render();
  assert.equal(statSync(output).mtimeMs,mtime,'unchanged organizer HTML retains mtime');
  const html = readFileSync(output, 'utf8');
  assert.ok(html.includes('Tickets &amp; events'));
  assert.ok(html.includes('href="https://vstupenky.online/"'));
  const seo = JSON.parse(readFileSync(join(root, 'automation/release/organizers/content.json'), 'utf8')).publicProjection.seo;
  const head = html.slice(0, html.indexOf('</head>'));
  assert.ok(head.includes(`<title>${seo.title}</title>`));
  assert.ok(head.includes(`name="description" content="${seo.description}"`));
  assert.equal((head.match(/rel="canonical"/g) || []).length, 1);
  assert.ok(head.includes('max-image-preview:large'));
  assert.ok(!head.includes('FESTAPP_CLIENT_VERSION'),
    'the network homepage must not pin shared imports to an older worker cache');
  assert.ok(!head.includes('FESTAPP_REPORT_VERSION'));
  assert.ok(head.includes('https://vstupenky.online/organizers-media/organizers-social.png'));
  assert.ok(head.includes('og:image:width" content="1200"'));
  assert.ok(head.includes('name="twitter:card" content="summary_large_image"'));
  const graph = JSON.parse(head.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
  assert.deepEqual(graph['@graph'].map(entity => entity['@type']), ['WebSite','WebPage','Service','Person']);
  assert.equal(graph['@graph'][0].url, 'https://vstupenky.online/');
  assert.equal(graph['@graph'][0].name, 'Tickets & events');
  assert.equal(graph['@graph'][1].description, seo.description);
  assert.ok(!JSON.stringify(graph).match(/aggregateRating|priceCurrency|SearchAction|FAQPage/));
  const catalog = readFileSync(join(root, 'web_client/index.html'), 'utf8');
  assert.ok(catalog.includes(`<title>${seo.catalogTitle}</title>`));
  assert.match(catalog, /property="og:image" content="https:\/\/vstupenky\.online\/android-chrome-512x512\.png"/);
  assert.match(catalog, /property="og:image:width" content="512"/);
  assert.doesNotMatch(catalog, /(?:property|name)="(?:og|twitter):image" content="[^"]*organizers-social\.png"/);
  assert.ok(catalog.includes('href="https://vstupenky.online/events"'));
  assert.ok(!catalog.includes('SearchAction'));
  assert.ok(!catalog.includes('class="catalog-navigation"'), 'generated catalogue must not duplicate shared header navigation');

  assert.equal((html.match(/<h1[ >]/g) || []).length, 1);
  assert.match(html, /class="hero-outlines" aria-hidden="true"><svg[^>]*data-hero-sketch/);
  assert.match(html, /data-sketch-motif="modern-ball-template"/);
  assert.match(html, /data-sketch-motif="concert-ticket"/);
  const purchase = html.slice(html.indexOf('id="ukazka-nakupu"'), html.indexOf('</section>', html.indexOf('id="ukazka-nakupu"')));
  assert.equal((purchase.match(/data-demo-player/g) ?? []).length, 2);
  assert.ok(purchase.includes('/organizers-media/seat-select-landing-cut.mp4'));
  assert.ok(purchase.includes('/organizers-media/order-payment-detail.mp4'));
  assert.ok(purchase.includes('data-portrait') && purchase.includes('width="426" height="900"'));
  assert.ok(html.includes('id="prvni-akce"'));
  const hero = html.slice(html.indexOf('<div class="hero-copy">'), html.indexOf('id="ukazka-nakupu"'));
  assert.equal((hero.match(/class="button primary"/g) ?? []).length, 1);
  assert.ok(hero.includes('class="text-link" href="https://cal.com/michael-bujnovsky-5srszz/ukazka">Domluvit ukázku'));
  assert.ok(hero.includes('Prodávejte vstupenky') && hero.includes('online i na místě'));
  for (const target of ['ukazka-nakupu', 'funkce', 'cena']) assert.ok(hero.includes(`href="#${target}"`));
  assert.ok(purchase.includes('data-seat-demo') && purchase.includes('data-seat-map') && purchase.includes('/organizers-media/scout-reference-plan.webp'));
  assert.match(purchase, /V ukázce se místa nerezervují a nic se neplatí/);
  assert.ok(html.indexOf('id="ukazka-nakupu"') < html.indexOf('id="funkce"'));
  assert.match(html, /Divadlo s balkonem a lóžemi/);
  assert.match(html, /src="\/organizers-media\/layout-theatre\.jpg"/);
  assert.doesNotMatch(html, /country_bal_vetrkovice|Otevřít plánek Country bálu/);
  assert.ok(html.includes('class="pricing-facts"'));
  const productPages = [
    ['ticket-sales', '/online-prodej-vstupenek'],
    ['payments-and-orders', '/platby-a-objednavky'],
    ['in-person-sales', '/prodej-vstupenek-na-miste'],
    ['ticket-check-in', '/odbaveni-vstupenek'],
    ['website-embed', '/prodej-vstupenek-na-vlastnim-webu'],
  ];
  const registry = JSON.parse(readFileSync(join(root, 'web/organizer-pages.json'), 'utf8'));
  for (const [asset, route] of productPages) {
    assert.ok(html.includes(`href="${route}"`), `${route} is discoverable from the landing page`);
    assert.ok(registry.pages.some(page => page.path === route && page.asset === `/organizers/${asset}`));
    const product = readFileSync(join(root, 'web/organizers', asset), 'utf8');
    assert.ok(product.includes(`rel="canonical" href="https://vstupenky.online${route}"`));
    assert.ok(product.includes('id="workflow-steps-title"') && product.includes('id="workflow-guides-title"'));
    assert.ok(product.includes('<details>'));
    if (asset === 'website-embed') {
      assert.match(product, /src="\/organizers-media\/wordpress-published-form\.webp"/);
      assert.match(product, /href="\/napoveda\/wordpress\/#nastaveni-bloku"/);
      assert.match(product, /srcset="\/organizers-media\/joomla-embedded-form-mobile\.webp"/);
    } else if (asset === 'in-person-sales') {
      assert.match(product, /href="\/organizers-media\/ticket-batch-print\.pdf"/);
      assert.match(product, /src="\/organizers-media\/order-cash-dialog\.webp"/);
    } else {
      assert.ok(product.includes('data-demo-player'));
    }
    if (asset === 'ticket-check-in') {
      assert.ok(product.includes('poster="/organizers-media/check-in-live-portrait.webp" width="430" height="900"'));
    }
  }
  assert.ok(html.includes('href="/login"'));
  const footer = html.slice(html.indexOf('<footer'));
  for (const route of ['/rezervacni-system-s-planem-salu']) assert.ok(footer.includes(`href="${route}"`),'topic is discoverable from shared footer');
  const seatingSection = html.slice(html.indexOf('id="planek"'), html.indexOf('id="formular"'));
  assert.ok(seatingSection.includes('href="/rezervacni-system-s-planem-salu"'),'seating demo links to its detail');
  assert.ok(seatingSection.includes('/organizers-media/layout-build-assembly.mp4'));
  assert.ok(seatingSection.includes('/organizers-media/layout-build-assembly-mobile.mp4'));
  assert.equal(existsSync(join(root,'web/organizers/ball-ticket-sales')),false,'retired article is removed');
  assert.ok(!html.includes('href="/prodej-vstupenek-na-ples"'));

  assert.ok(html.includes('info@vstupenky.online'));
  assert.match(html, /href="#kontakt">Napsat kvůli ceně/);
  assert.match(html, /<form data-organizer-contact method="post" action="https:\/\/api\.festapp\.net\/functions\/v1\/organizer-contact" hidden>/);
  assert.match(html, /<input id="contact-email" name="email" type="email" autocomplete="email" maxlength="254" required>/);
  assert.match(html, /<p data-contact-status role="status" aria-live="polite"><\/p>/);
  const faq = html.slice(html.indexOf('id="faq"'), html.indexOf('id="kontakt"'));
  assert.match(faq, /Co je zdarma a za co jako pořadatel zaplatím\?/);
  assert.match(faq, /Už prodávám jinde\. Jak přejdu s rozjetou akcí\?/);
  assert.match(faq, /href="\/napoveda\/objednavky\/#zmena"/);
  assert.match(faq, /href="\/napoveda\/odbaveni\/#offline"/);
  assert.doesNotMatch(faq, /Potřebuji k založení akce účet\?/);
  assert.match(html, /<textarea id="contact-message" name="message" rows="4" maxlength="1000" required>/);
  assert.ok(html.includes('https://cal.com/michael-bujnovsky-5srszz/ukazka'));
  // Shared documents never own a beacon: only resolved public responses do.
  for (const document of [html, catalog]) {
    assert.ok(!document.includes('static.cloudflareinsights.com/beacon.min.js'));
    assert.ok(!document.includes('data-cf-beacon'));
  }
  assert.ok(!html.includes('internalSources'));
  assert.ok(!html.includes('&amp;amp;'));
  assert.ok(!html.includes('{{'));
  assert.ok(!html.includes('fonts.googleapis.com'));
  render(); assert.equal(readFileSync(output, 'utf8'), html);
  mkdirSync(join(root, 'web_client/web-assets'), {recursive:true});
  mkdirSync(join(root, 'web_client/assets/translations'), {recursive:true});
  writeFileSync(join(root, 'web_client/web-assets/landing-test.js'), 'import "./account_header-cached.js";');
  writeFileSync(join(root, 'web_client/web-assets/account_header-cached.js'), 'export const ready = true;');
  writeFileSync(join(root, 'web_client/web-assets/index-fixture.css'), 'body{}');
  writeFileSync(join(root, 'web_client/assets/translations/cs.json'), '{}');
  const builtIndex = join(root, 'web_client/built.html');
  writeFileSync(builtIndex, '<link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet"><link rel="stylesheet" href="/web-assets/index-fixture.css">');
  mkdirSync(join(root, 'web_client/.vite'), { recursive: true });
  writeFileSync(join(root, 'web_client/.vite/manifest.json'), JSON.stringify({'src/marketing/landing.js': {file: 'web-assets/landing-test.js'}}));
  mkdirSync(join(root,'web_client/web-assets'),{recursive:true});
  mkdirSync(join(root,'web_client/assets/translations'),{recursive:true});
  const bundleOutput = join(root, 'bundle/organizers-page');
  cpSync(join(root,'web/organizers-media'),join(root,'bundle/organizers-media'),{recursive:true});
  const sourceCatalog = readFileSync(join(root, 'web_client/index.html'), 'utf8');
  const build = spawnSync(process.execPath, [join(root, 'automation/release/render_organizer_page.mjs'), '--config', config, '--built-index', builtIndex, '--output', bundleOutput], { encoding: 'utf8' });
  assert.equal(build.status, 0, build.stderr);
  assert.equal(readFileSync(join(root, 'web_client/index.html'), 'utf8'), sourceCatalog, 'built rendering must preserve the source bytes captured by the build receipt');
  const bundled = readFileSync(bundleOutput, 'utf8');
  const runtimeRoot = bundled.match(/src="(\/organizers-assets\/[a-f0-9]+\/)runtime\/landing-test.js"/)?.[1];
  assert.ok(runtimeRoot, 'homepage uses the canonical versioned public runtime, avoiding cached app-chunk failures');
  assert.ok(bundled.includes(`href="${runtimeRoot}runtime/index-fixture.css"`));
  assert.equal(readFileSync(join(root, 'bundle', runtimeRoot, 'runtime/account_header-cached.js'), 'utf8'), 'export const ready = true;');
  assert.ok(!bundled.includes('src="/web-assets/'));

  assert.ok(bundled.includes('https://fonts.googleapis.com/icon?family=Material+Icons'));
  assert.ok(!bundled.includes('css2?family=Roboto'));
  assert.equal(readFileSync(output, 'utf8'), html, 'compiled theme must not alter the deterministic source leaf');

  const contentPath = join(root, 'automation/release/organizers/content.json');
  const originalContent = readFileSync(contentPath, 'utf8');
  const malicious = JSON.parse(originalContent);
  malicious.publicProjection.seo.description = '</script><script>alert("x")</script> & $&';
  writeFileSync(contentPath, JSON.stringify(malicious));
  render();
  const escaped = readFileSync(output, 'utf8').split('</head>')[0];
  const safeGraph = JSON.parse(escaped.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
  assert.equal(safeGraph['@graph'][1].description, malicious.publicProjection.seo.description);
  assert.ok(!escaped.includes('<script>alert('));
  writeFileSync(contentPath, originalContent);

  writeFileSync(config, 'WEB_ORGANIZER_LANDING_ENABLED=false\nDOMAIN=other.invalid\nWEB_LINK=https://other.invalid\nAPP_NAME=Other\n');
  render(); assert.equal(existsSync(output), false);
  assert.equal(existsSync(join(root,'web/organizers/press')),false);
  assert.equal(existsSync(join(root,'web/organizers-media/press-kit')),false);
  assert.ok(!readFileSync(join(root, 'web_client/index.html'), 'utf8').includes('cloudflareinsights.com'));
  assert.ok(!readFileSync(join(root, 'web_client/index.html'), 'utf8').includes('href="/pro-poradatele"'));
});

test('actual build stamping uses configured canonical origin and the shared classifier', t => {
  const root = mkdtempSync(join(tmpdir(), 'festapp-worker-stamp-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const script = readFileSync(new URL('../cloudflare_build.sh', import.meta.url), 'utf8');
  const worker = join(root, 'worker.js'); const config = join(root, 'project.conf');
  writeFileSync(worker, script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1].replace('// HELP_ACTION_ROUTE_POLICY', () => helpActionWorkerSource));
  writeFileSync(config, 'WEB_LINK=https://vstupenky.online\nWEB_ORGANIZER_LANDING_ENABLED=true\nAPP_NAME=Tickets\nIS_APP_SUPPORTED=true\nFORCE_OCCASION_LINK=\n');
  writeFileSync(config, readFileSync(new URL('../project.conf',import.meta.url),'utf8'));
  const registry = publicManifest(resolveContext(readConfig(config)));
  for (const {asset} of registry.pages) {
    const file = join(root, asset.slice(1));
    mkdirSync(join(file, '..'), {recursive: true});
    writeFileSync(file, 'fixture');
  }
  writeFileSync(join(root,'organizer-pages.json'),JSON.stringify(registry));
  writeFileSync(join(root,'platform-updates.json'),JSON.stringify({schemaVersion:1,items:[]}));
  const python = script.match(/python3 - build\/web\/_worker.js automation\/project.conf <<'PY'\n([\s\S]*?)\nPY/)[1];
  const result = spawnSync('python3', ['-', worker, config], { input: python, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const source = readFileSync(worker, 'utf8');
  assert.ok(source.includes('const CANONICAL_ORIGIN = "https://vstupenky.online";'));
  assert.ok(source.includes('const MARKETING = {"schemaVersion": 1, "enabled": true'));
  assert.ok(source.includes('function classifyOccasions('));
  assert.ok(!source.includes('// SHARED_CATALOG_CLASSIFICATION'));
  for (const domain of ['other.invalid', 'plesy.vstupenky.online']) {
    writeFileSync(config, `WEB_LINK=https://${domain}\nAPP_NAME=Other\nIS_APP_SUPPORTED=true\nFORCE_OCCASION_LINK=\n`);
    writeFileSync(worker, script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1].replace('// HELP_ACTION_ROUTE_POLICY', () => helpActionWorkerSource));
    writeFileSync(join(root,'organizer-pages.json'),JSON.stringify(publicManifest(resolveContext(readConfig(config)))));
    const other = spawnSync('python3', ['-', worker, config], {input:python, encoding:'utf8'});
    assert.equal(other.status,0,other.stderr);
    assert.ok(readFileSync(worker,'utf8').includes('\"enabled\": false'));
  }
});


test('static sitemap fallback keeps tenant-specific catalog URLs and sharing asset has real social dimensions', t => {
  const root = mkdtempSync(join(tmpdir(), 'festapp-sitemap-fallback-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const apply = readFileSync(new URL('../apply_config.sh', import.meta.url), 'utf8');
  const python = apply.match(/<<'SITEMAP'\n([\s\S]*?)\nSITEMAP/)[1];
  const output = join(root, 'sitemap.xml');
  for (const domain of ['vstupenky.online','other.invalid']) {
    const config=join(root,'project.conf');
    writeFileSync(config,readFileSync(new URL('../project.conf',import.meta.url),'utf8').replace(/^DOMAIN=.*$/m,`DOMAIN=${domain}`).replace(/^WEB_LINK=.*$/m,`WEB_LINK=https://${domain}`).replace(/^WEB_ORGANIZER_LANDING_ENABLED=.*$/m,`WEB_ORGANIZER_LANDING_ENABLED=${domain==='vstupenky.online'}`));
    const run = spawnSync('python3', ['-',output,config,process.cwd()], {input:python,encoding:'utf8',env:{...process.env,PYTHONPATH:join(process.cwd(),'automation/lib')}});
    assert.equal(run.status, 0, run.stderr);
    const xml = readFileSync(output, 'utf8');
    assert.ok(xml.includes(`https://${domain}/`));
    assert.equal(xml.includes('/events</loc>'), domain === 'vstupenky.online');
    if (domain !== 'vstupenky.online') assert.ok(!xml.includes('vstupenky.online'));
  }
  const png = readFileSync(new URL('../../web/organizers-media/organizers-social.png', import.meta.url));
  assert.equal(png.subarray(1,4).toString(), 'PNG');
  assert.equal(png.readUInt32BE(16), 1200);
  assert.equal(png.readUInt32BE(20), 630);
});

test('English illustrated home ships English examples, one regional link and fails atomically on missing artwork', t => {
  const root = mkdtempSync(join(tmpdir(), 'festapp-en-marketing-'));
  cpSync(new URL('../../web_client/public', import.meta.url), join(root, 'web_client/public'), {recursive:true});
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(join(root, 'automation/release'), { recursive: true });
  mkdirSync(join(root,'automation/lib'),{recursive:true});
  cpSync(new URL('../lib/write_if_changed.cjs',import.meta.url),join(root,'automation/lib/write_if_changed.cjs'));
  cpSync(new URL('../release/render_organizer_page.mjs', import.meta.url), join(root, 'automation/release/render_organizer_page.mjs'));
  cpSync(new URL('../release/organizers', import.meta.url), join(root, 'automation/release/organizers'), { recursive: true });
  cpSync(new URL('../release/platform_updates',import.meta.url),join(root,'automation/release/platform_updates'),{recursive:true,filter:source=>!source.includes('node_modules')});
  symlinkSync(fileURLToPath(new URL('../release/platform_updates/node_modules',import.meta.url)),join(root,'automation/release/platform_updates/node_modules'),'dir');
  cpSync(new URL('../../web/organizers-media/global',import.meta.url),join(root,'web/organizers-media/global'),{recursive:true});
  const config = join(root, 'project.conf');
  writeFileSync(config, 'WEB_ORGANIZER_LANDING_ENABLED=true\nWEB_SUPPORTED_LANGUAGES=en\nWEB_LINK=https://tickets.example.invalid\nDOMAIN=tickets.example.invalid\nAPP_NAME=Festapp Tickets\nWEB_ORGANIZER_CONTENT_PROFILE=festapp-en\nPRIVACY_URL=https://tickets.example.invalid/privacy/\nTERMS_URL=https://tickets.example.invalid/terms/\nSUPPORT_URL=https://tickets.example.invalid/support/\n');
  const run = (...args) => spawnSync(process.execPath, [join(root, 'automation/release/render_organizer_page.mjs'), '--config', config, ...args], { encoding: 'utf8' });
  const rendered = run();
  assert.equal(rendered.status, 0, rendered.stderr);
  const output=join(root,'web/organizers-page');
  const html = readFileSync(output, 'utf8');
  assert.match(html, /<html lang="en">/);
  assert.equal((html.match(/vstupenky\.online/g) || []).length, 1);
  assert.match(html,/href="https:\/\/vstupenky\.online\/"[^>]*>Czech version/);
  assert.match(html,/rel="manifest" href="\/site\.webmanifest"/);
  assert.match(html,/classic-ball-en\.png/);
  assert.match(html,/hamlet-ticket-en\.png/);
  assert.match(html,/info@festapp\.net/);
  const canonicalBooking=JSON.parse(readFileSync(new URL('../release/organizers/content.json',import.meta.url),'utf8')).publicProjection.bookingUrl;
  const globalBooking=JSON.parse(readFileSync(new URL('../release/organizers/content.en.json',import.meta.url),'utf8')).publicProjection.bookingUrl;
  assert.equal(globalBooking,canonicalBooking,'global demo uses the canonical booking flow');
  assert.equal((html.match(new RegExp('href="'+canonicalBooking+'"','g'))??[]).length,3,'demo is available in hero, support and footer');
  assert.match(html,/href="\/help\/"/,'global guides are reachable from the homepage');
  assert.match(html,/<header class="site-header auth-pending"/,'illustrated home exposes the shared account-header mount');
  assert.match(html,/class="header-signin" href="\/login"/,'sign-in remains reachable before account hydration');
  assert.doesNotMatch(html,/href="#how-it-works"/,'Help owns guidance; duplicate scroll actions are removed');

  assert.match(html,/href="\/events\?create=1"/);
  assert.ok(!html.includes('tickets.fesup.net'));
  assert.ok(!html.includes('{{'));
  assert.ok(!html.includes('English recording pending.'));
  assert.ok(!html.includes('cloudflareinsights.com'));
  rmSync(join(root,'web/organizers-media/global/classic-ball-en.png'));
  const failed=run();
  assert.notEqual(failed.status,0);
  assert.match(failed.stderr,/Missing\/foreign marketing media/);
  assert.equal(readFileSync(output,'utf8'),html,'invalid media cannot overwrite a previously rendered page');
});


test('illustrated branding preserves the canonical account header layout', () => {
  const css = readFileSync(new URL('../release/organizers/illustrated-home.css', import.meta.url), 'utf8');
  const allowed = new Set(['background', 'color', 'border-color', 'border-bottom-color', 'box-shadow']);
  let themedRules = 0;
  for (const [, selectors, declarations] of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    if (!selectors.includes('user-header[data-marketing]')) continue;
    themedRules++;
    for (const declaration of declarations.split(';').filter(value => value.trim())) {
      const property = declaration.slice(0, declaration.indexOf(':')).trim();
      assert.ok(allowed.has(property), `Account header layout must stay shared: ${property}`);
    }
  }
  assert.ok(themedRules > 0);
});


test('cinematic document scrollbar stays visible and matches its dark canvas', () => {
  const css = readFileSync(new URL('../release/organizers/illustrated-home.css', import.meta.url), 'utf8');
  const rootRule = css.match(/html:has\(body\[data-cinematic="true"\]\)\s*\{([^}]*)\}/)?.[1];
  assert.ok(rootRule, 'Only the illustrated document owns its scrollbar theme');
  assert.match(css, /html:has\(body\[data-cinematic="true"\]\),body\[data-cinematic="true"\]\s*\{[^}]*scrollbar-width:thin;/);
  assert.match(css, /scrollbar-color:#[a-f0-9]+ var\(--night\)/);
  assert.match(rootRule, /background:var\(--night\)!important/);
  assert.doesNotMatch(rootRule, /overflow[^;]*hidden|scrollbar-width:none/);
});
