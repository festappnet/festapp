import {startMeasurementConsent} from '../../../src/components/forms/form_measurement_cmp.js';
import {LocalizationService} from '../../../src/services/localization_service.js';
LocalizationService.translations = await (await fetch('/assets/translations/en.json')).json();
const origin = new URL(document.referrer).origin;
window.linkChoices = [];
const start = (policy = {}) => startMeasurementConsent({model:{data:{analytics:{organization:1,unit:2,
    measurement_consent_bridge:true,processing_revision:'link-browser',privacy_url:'https://organizer.example/privacy',approved_hosts:[origin], ...policy}}},
    setConsent:value=>window.linkChoices.push(value),host:document.querySelector('main')});
window.stopLinkFixture = start();
// The measurement session reconnects consent like this when the policy scope changes.
window.changeLinkScope = policy => { window.stopLinkFixture(); window.stopLinkFixture = start(policy); };
