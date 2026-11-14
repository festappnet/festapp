#!/usr/bin/env node
// Every configuration the generated Joomla module emits must be accepted by the
// real service adapters (Cookiebot model and pinned CookieConsent v3 library).
// Requires web_client dependencies (pnpm install --frozen-lockfile) and PHP 8.3+.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const web = new URL('../../../web_client/', import.meta.url);
const {JSDOM} = createRequire(new URL('package.json', web))('jsdom');
const {createCookiebotSource} = await import(new URL('src/embed/host_cookiebot.js', web));
const {createCookieConsentSource} = await import(new URL('src/embed/host_cookieconsent.js', web));
const {consentScope} = await import(new URL('src/components/forms/measurement_consent_source.js', web));
const {cookiebotFixture} = await import(new URL('tests/support/cookiebot_fixture.js', web));
const {cookieconsentFixture} = await import(new URL('tests/support/cookieconsent_fixture.js', web));

const revision = '0123456789abcdef0123456789abcdef';
const cookiebot = {consent_link:'1', consent_provider:'cookiebot', consent_organization:'7', consent_unit:'11', consent_revision:revision,
  consent_cbid:'09E4E631-F8C7-434E-8387-315DA47220FE', consent_origin:'https://www.poradatel.example', consent_valid_from:'2026-01-01T00:00:00.000Z', consent_max_age:'15552000'};
const cookieconsent = {consent_link:1, consent_provider:'cookieconsent', consent_organization:7, consent_unit:11, consent_revision:revision,
  consent_cc_revision:'3', consent_cc_analytics:'', consent_cc_marketing:''};
const variants = [cookiebot, cookieconsent,
  ...[' 7 ', 9007199254740991, '9007199254740991'].map(consent_organization => ({...cookiebot, consent_organization})),
  ...['https://poradatel.example:8443', 'https://xn--lu-tka.example', 'https://a.b.c.example'].map(consent_origin => ({...cookiebot, consent_origin})),
  ...['2000-02-29T23:59:59.999Z', ' 2026-01-01T00:00:00.000Z '].map(consent_valid_from => ({...cookiebot, consent_valid_from})),
  ...['1', '31536000'].map(consent_max_age => ({...cookiebot, consent_max_age})),
  ...[['statistika', 'reklama'], ['měření', 'marketing'], ['a'.repeat(128), 'b'], ['analytics', 'ads']]
    .map(([consent_cc_analytics, consent_cc_marketing]) => ({...cookieconsent, consent_cc_analytics, consent_cc_marketing})),
  {...cookieconsent, consent_cc_revision:'9007199254740991'}];
// PHP renders through the generated module helper exactly as Joomla stores params.
const php = `namespace Joomla\\CMS\\Language{final class Text{public static function _($k){return $k;}}}
namespace{define('_JEXEC',1);require $argv[1];$out=[];foreach(json_decode(stream_get_contents(STDIN),true) as $p){$c=Festapp\\Module\\VstupenkyOnline\\Site\\Helper\\EmbedHelper::consent($p);$out[]=$c['json']??null;}echo json_encode($out);}`;
const helper = fileURLToPath(new URL('../build/mod_vstupenky_online/src/Helper/EmbedHelper.php', import.meta.url));
const emitted = JSON.parse(execFileSync('php', ['-r', php, '--', helper],
  {input:JSON.stringify(variants), env:{...process.env}}).toString());
let checked = 0;
for (const [index, json] of emitted.entries()) {
  assert.equal(typeof json, 'string', 'Valid module settings emit a helper configuration: ' + JSON.stringify(variants[index]));
  const config = JSON.parse(json);
  const scope = consentScope({organization:config.organization, unit:config.unit, processing_revision:'runtime', consent_revision:config.consentRevision});
  if (config.provider === 'cookiebot') {
    const win = new JSDOM('', {url:config.origin, runScripts:'outside-only'}).window;
    const fixture = cookiebotFixture(win, {choice:{analytics:true, marketing:false}});
    fixture.script.setAttribute('data-cbid', config.cbid);
    if (Date.parse(config.consentValidFrom) > Date.now()) { win.close(); continue; }
    const source = createCookiebotSource(win, json);
    assert.deepEqual(source.read(scope), {consentRevision:config.consentRevision, analytics:true, marketing:false}, 'Cookiebot adapter accepts ' + json);
    assert.equal(createCookiebotSource(win, {...config, organization:config.organization + 1}).read(scope), null, 'Scope still binds');
    win.close();
  } else {
    const names = config.categories || {analytics:'analytics', marketing:'marketing'};
    const win = new JSDOM('', {url:'https://www.poradatel.example', runScripts:'outside-only'}).window;
    await cookieconsentFixture(win, {choice:{[names.analytics]:true}, config:{revision:config.revision,
      categories:{necessary:{enabled:true, readOnly:true}, [names.analytics]:{}, [names.marketing]:{}}}});
    const source = createCookieConsentSource(win, json);
    assert.deepEqual(source.read(scope), {consentRevision:config.consentRevision, analytics:true, marketing:false}, 'CookieConsent adapter accepts ' + json);
    win.close();
  }
  checked++;
}
console.log(JSON.stringify({adapter_parity_cases:checked}));
