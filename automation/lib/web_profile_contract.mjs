import assert from 'node:assert/strict';

// Both completed-build and public-deployment probes validate the selected UI language.
export function webProfileContract(value) {
  const en = (value('WEB_SUPPORTED_LANGUAGES') || 'cs').split(',')[0] === 'en';
  const landing = value('WEB_ORGANIZER_LANDING_ENABLED') || 'false';
  assert.ok(['true', 'false'].includes(landing), 'WEB_ORGANIZER_LANDING_ENABLED must be true or false');
  const navigation = en ? 'Legal information' : 'Právní informace';
  const deletion = en ? 'Account deletion' : 'Smazání účtu';
  return {
    organizerEnabled: landing === 'true',
    legalNavigationMarker: new RegExp(`<nav aria-label="${navigation}">`),
    legalPageMarker: new RegExp(`<nav aria-label="${navigation}">[\\s\\S]*<h1>[^<]+<\\/h1>`),
    deletionPageMarker: new RegExp(`<h1>${deletion}<\\/h1>`),
  };
}
