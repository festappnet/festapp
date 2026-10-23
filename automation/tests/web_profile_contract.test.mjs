import test from 'node:test';
import assert from 'node:assert/strict';
import { webProfileContract } from '../lib/web_profile_contract.mjs';
const profile = config => webProfileContract(key => config[key]);
for (const [locale, navigation, heading, foreign] of [
  ['cs', 'Právní informace', 'Smazání účtu', 'Account deletion'],
  ['en', 'Legal information', 'Account deletion', 'Smazání účtu'],
]) {
  test(`${locale} deployment markers require the selected language`, () => {
    const contract = profile({WEB_SUPPORTED_LANGUAGES: locale, WEB_ORGANIZER_LANDING_ENABLED: 'true'});
    assert.equal(contract.organizerEnabled, true);
    assert.match(`<nav aria-label="${navigation}"></nav><main><h1>Privacy</h1>`, contract.legalPageMarker);
    assert.match(`<h1>${heading}</h1>`, contract.deletionPageMarker);
    assert.doesNotMatch(`<h1>${foreign}</h1>`, contract.deletionPageMarker);
  });
}
test('optional organizer capability defaults off and rejects invalid configuration', () => {
  assert.equal(profile({}).organizerEnabled, false);
  assert.equal(profile({WEB_ORGANIZER_LANDING_ENABLED: 'false'}).organizerEnabled, false);
  assert.throws(() => profile({WEB_ORGANIZER_LANDING_ENABLED: 'yes'}));
});
