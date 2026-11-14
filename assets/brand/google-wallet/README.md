# Google Wallet button artwork

Unmodified localized PNG buttons from Google's official
[asset archive](https://developers.google.com/static/wallet/download-assets/add-to-wallet-png.zip),
retrieved 2026-11-10. Follow the
[brand guidelines](https://developers.google.com/wallet/tickets/events/resources/brand-guidelines):
at least 48 px high, preserve aspect ratio and 8 px clear space on every side.

Before activating a tenant, publish these files as immutable public `assets/`
objects through the canonical image Worker/R2 asset workflow and configure the
verified URLs in `eshop.ticket_wallet_integrations.badge_urls`. Keeping files in
this repository does not publish them or make the integration ready.


The unmodified official condensed variants in `condensed/` come from the same
archive, retrieved 2026-11-14 (`*_add-wallet-badge.png`; Czech uses `cz`, English
uses `enUS`). They retain a 48 px displayed height in narrow emails with 8 px
clear space; the web uses the same condensed variants for a consistent action row. Publish condensed
bytes to `assets/google-wallet/v1/condensed/<locale>.png` before deploying the
email renderer that references them.
