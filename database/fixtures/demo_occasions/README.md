# Shared demo catalogue

All demo logic and presentation inputs live on `main` in this directory.
`seed.sql` owns the common event, seat, inventory, order, ticket and simulated
payment rules. `locales.sql` supplies presentation data; `localization.sql`
applies the selected locale. English does not maintain a second business seed.
The sample prices and CZK currency remain identical in both versions.

Run the canonical operational entry with an explicitly authorized tenant:

```sh
psql -v demo_organization=3 -v demo_locale=cs -f automation/seed_demo_occasions.sql
psql -v demo_organization=25 -v demo_locale=en -f automation/seed_demo_occasions.sql
```

The default locale remains `cs` for existing callers. Unsupported locales,
incomplete catalogues and attempts to overwrite another locale fail. English
replay preserves the same three versioned events and creates no duplicates.
Each tenant has its own demo organizer, separate from real organizer Units.
The same seed reserves event and form URLs through the canonical link registry,
including on replay; activation rejects examples whose URLs do not resolve.

The seating geometry, seat identity and numeric lettering remain shared.
`reference.en.sql` changes only four labels and their immutable shaped text
resources. Regenerate it with `python3 automation/prepare_english_demo_reference.py`;
this uses the canonical bundled-font shaper with network font fallback disabled.
Ticket artwork has no baked-in text; editable ticket fields use the selected
locale.

Inspect the unlisted examples, verify read-only access and disabled payment
routing, then publish the catalogue through the matching locale:

```sh
psql -v demo_organization=25 -v demo_locale=en -f automation/activate_demo_occasions.sql
```

Production operations use the protected backend access workflow and exact
published source, never the local test database or a tenant code fork. No Auth
invitation, checkout, bank import or email producer runs during fixture creation.
