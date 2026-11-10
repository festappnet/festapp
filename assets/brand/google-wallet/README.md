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
