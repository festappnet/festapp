// Generated from packages/festapp_contracts/configuration-settings.json.
// Omission preserves server settings; explicit null clears nullable overrides.
const unitSettingsKeys = <String>{
  'reply_to',
  'communication_tone',
  'timezone',
  'measurement_enabled',
  'measurement_consent_layout',
  'measurement_consent_title',
  'measurement_consent_text',
  'measurement_gtm_container',
  'measurement_scripts',
  'measurement_privacy_url',
  'measurement_consent_version',
  'measurement_consent_bridge',
  'measurement_websites',
};
const unitMeasurementWebsitePattern =
    r'^https://[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*(:([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))?$';
