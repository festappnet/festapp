// Side-effect module, imported first by main.js: windows opened by the consent
// link helper drop window.opener before any other code runs.
import {prepareConsentLink} from '../components/forms/form_consent_link.js';
prepareConsentLink(window);
