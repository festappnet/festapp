import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, cpSync, readFileSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

test('tenant generator produces truthful standalone HTML and removes page/nav on tenant switch', t => {
  const root = mkdtempSync(join(tmpdir(), 'festapp-seo-generator-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(join(root, 'automation/release'), { recursive: true });
  mkdirSync(join(root, 'web_client'), { recursive: true });
  cpSync(new URL('../release/render_organizer_page.mjs', import.meta.url), join(root, 'automation/release/render_organizer_page.mjs'));
  cpSync(new URL('../release/organizers', import.meta.url), join(root, 'automation/release/organizers'), { recursive: true });
  cpSync(new URL('../../web_client/index.html', import.meta.url), join(root, 'web_client/index.html'));
  const config = join(root, 'automation/project.conf');
  writeFileSync(config, 'DOMAIN=vstupenky.online\nWEB_LINK=https://vstupenky.online\nAPP_NAME="Tickets & events"\nVERSION=0.0.1+1\nTHEME_SEED_3=#4465a6\n');
  const render = () => {
    const run = spawnSync(process.execPath, [join(root, 'automation/release/render_organizer_page.mjs'), '--config', config], { encoding: 'utf8' });
    assert.equal(run.status, 0, run.stderr);
  };
  render();
  const output = join(root, 'web/organizers-page');
  const html = readFileSync(output, 'utf8');
  assert.ok(html.includes('Tickets &amp; events'));
  assert.ok(html.includes('href="https://vstupenky.online/"'));
  const seo = JSON.parse(readFileSync(join(root, 'automation/release/organizers/content.json'), 'utf8')).publicProjection.seo;
  const head = html.slice(0, html.indexOf('</head>'));
  assert.ok(head.includes(`<title>${seo.title}</title>`));
  assert.ok(head.includes(`name="description" content="${seo.description}"`));
  assert.equal((head.match(/rel="canonical"/g) || []).length, 1);
  assert.ok(head.includes('max-image-preview:large'));
  assert.ok(head.includes('FESTAPP_CLIENT_VERSION'));
  assert.ok(head.includes('FESTAPP_REPORT_VERSION'));
  assert.ok(head.includes('https://vstupenky.online/organizers-media/organizers-social.png'));
  assert.ok(head.includes('og:image:width" content="1200"'));
  assert.ok(head.includes('name="twitter:card" content="summary_large_image"'));
  const graph = JSON.parse(head.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
  assert.deepEqual(graph['@graph'].map(entity => entity['@type']), ['WebSite','WebPage','Service','Person']);
  assert.equal(graph['@graph'][0].url, 'https://vstupenky.online/');
  assert.equal(graph['@graph'][0].name, 'vstupenky.online');
  assert.equal(graph['@graph'][1].description, seo.description);
  assert.ok(!JSON.stringify(graph).match(/aggregateRating|priceCurrency|SearchAction|FAQPage/));
  const catalog = readFileSync(join(root, 'web_client/index.html'), 'utf8');
  assert.ok(catalog.includes(`<title>${seo.catalogTitle}</title>`));
  assert.ok(catalog.includes('href="https://vstupenky.online/events"'));
  assert.ok(!catalog.includes('SearchAction'));

  assert.equal((html.match(/<h1[ >]/g) || []).length, 1);
  assert.ok(html.includes('href="/login"'));
  assert.ok(html.includes('info@vstupenky.online'));
  assert.ok(html.includes('https://cal.com/michael-bujnovsky-5srszz/ukazka'));
  assert.equal((html.match(/src="https:\/\/static\.cloudflareinsights\.com\/beacon\.min\.js"/g)||[]).length,1);
  assert.ok(html.includes('10a70df3585344258adf7bb3b6611a84'));
  assert.equal((catalog.match(/src="https:\/\/static\.cloudflareinsights\.com\/beacon\.min\.js"/g)||[]).length,1);
  assert.ok(!html.includes('internalSources'));
  assert.ok(!html.includes('&amp;amp;'));
  assert.ok(!html.includes('{{'));
  assert.ok(!html.includes('fonts.googleapis.com'));
  render(); assert.equal(readFileSync(output, 'utf8'), html);
  const builtIndex = join(root, 'web_client/built.html');
  writeFileSync(builtIndex, '<link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet"><link rel="stylesheet" href="/web-assets/index-fixture.css">');
  mkdirSync(join(root, 'web_client/.vite'), { recursive: true });
  writeFileSync(join(root, 'web_client/.vite/manifest.json'), JSON.stringify({'src/marketing/landing.js': {file: 'web-assets/landing-test.js'}}));
  const bundleOutput = join(root, 'bundle/organizers-page');
  const build = spawnSync(process.execPath, [join(root, 'automation/release/render_organizer_page.mjs'), '--config', config, '--built-index', builtIndex, '--output', bundleOutput], { encoding: 'utf8' });
  assert.equal(build.status, 0, build.stderr);
  const bundled = readFileSync(bundleOutput, 'utf8');
  assert.ok(bundled.includes('href="/web-assets/index-fixture.css"'));
  assert.ok(!bundled.includes('fonts.googleapis.com'));
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

  writeFileSync(config, 'DOMAIN=other.invalid\nWEB_LINK=https://other.invalid\nAPP_NAME=Other\n');
  render(); assert.equal(existsSync(output), false);
  assert.ok(!readFileSync(join(root, 'web_client/index.html'), 'utf8').includes('cloudflareinsights.com'));
  assert.ok(!readFileSync(join(root, 'web_client/index.html'), 'utf8').includes('href="/pro-poradatele"'));
});

test('actual build stamping uses configured canonical origin and the shared classifier', t => {
  const root = mkdtempSync(join(tmpdir(), 'festapp-worker-stamp-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const script = readFileSync(new URL('../cloudflare_build.sh', import.meta.url), 'utf8');
  const worker = join(root, 'worker.js'); const config = join(root, 'project.conf');
  writeFileSync(worker, script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1]);
  writeFileSync(config, 'WEB_LINK=https://vstupenky.online\nAPP_NAME=Tickets\nIS_APP_SUPPORTED=true\nFORCE_OCCASION_LINK=\n');
  const python = script.match(/python3 - build\/web\/_worker.js automation\/project.conf <<'PY'\n([\s\S]*?)\nPY/)[1];
  const result = spawnSync('python3', ['-', worker, config], { input: python, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const source = readFileSync(worker, 'utf8');
  assert.ok(source.includes('const CANONICAL_ORIGIN = "https://vstupenky.online";'));
  assert.ok(source.includes('const ORGANIZERS_ENABLED = true;'));
  assert.ok(source.includes('function classifyOccasions('));
  assert.ok(!source.includes('// SHARED_CATALOG_CLASSIFICATION'));
  for (const domain of ['other.invalid', 'plesy.vstupenky.online']) {
    writeFileSync(config, `WEB_LINK=https://${domain}\nAPP_NAME=Other\nIS_APP_SUPPORTED=true\nFORCE_OCCASION_LINK=\n`);
    writeFileSync(worker, script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1]);
    const other = spawnSync('python3', ['-', worker, config], {input:python, encoding:'utf8'});
    assert.equal(other.status,0,other.stderr);
    assert.ok(readFileSync(worker,'utf8').includes('const ORGANIZERS_ENABLED = false;'));
  }
});


test('static sitemap fallback keeps tenant-specific catalog URLs and sharing asset has real social dimensions', t => {
  const root = mkdtempSync(join(tmpdir(), 'festapp-sitemap-fallback-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const apply = readFileSync(new URL('../apply_config.sh', import.meta.url), 'utf8');
  const python = apply.match(/<<'SITEMAP'\n([\s\S]*?)\nSITEMAP/)[1];
  const output = join(root, 'sitemap.xml');
  for (const domain of ['vstupenky.online','other.invalid']) {
    const run = spawnSync('python3', ['-',output,domain], {input:python,encoding:'utf8'});
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
