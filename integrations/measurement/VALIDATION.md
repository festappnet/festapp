# Preset validation - 2026-11-10

The exact `festapp-host-gtm.json` with SHA-256
`356981e51d82cd398eca4760f317a8e1a1fd9ffd3ca9b1664bae16ffb26e3ffa`
was imported using **Merge** into a task-owned workspace of the existing Festapp
nonproduction web GTM container. No version was published and no tag was fired.

The actual GTM editor accepted and interpreted:

- Four paused tags: two native GA4 tags, native Ads conversion, Meta Custom HTML.
- Ten custom-event triggers requiring the host `form_embedded` marker; six
  ecommerce events and four form/lead events use separate GA4 tags.
- GA4 public context parameters and event-scoped lead parameters; ecommerce is
  enabled only on the ecommerce tag. Analytics storage is explicitly required.
- Ads value/currency/transaction variable references and the native CODE-mode
  User-Provided Data variable, referenced through event parameter `user_data`.
- Meta's public-field source and event-gated ecommerce/lead data. Ads and Meta
  require ad storage, ad user data and ad personalization.
- Native Custom JavaScript interpretation of the event-scoped lead variables.

The first import failed when container metadata was omitted. The committed
wrapper uses generic zero identifiers and a WEB container context; it contains
no actual account/container identifiers or auto-generated Google settings.

This evidence proves importability and editor interpretation. It does not prove
merchant consent configuration, actual conversion delivery, customer-data terms,
attribution, or campaign reporting. The setup guide requires Preview and an
approved destination test before enabling tags. Automated contract tests also
exercise public Meta projection and reject inherited native ecommerce state.
