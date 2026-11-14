# Apple Wallet badges

Unmodified official SVG artwork from Apple's Add to Apple Wallet archive:
https://developer.apple.com/wallet/add-to-apple-wallet-guidelines/

Downloaded 2026-11-14 after the user explicitly authorized acceptance of the
Apple Wallet Marketing Artwork License Agreement. `provenance.json` records
archive SHA-256, exact original filenames, dimensions and per-file SHA-256.
The pack provides CZ, SK, US_UK, DE, PL and UA artwork, mapped to cs/sk/en/de/pl/uk.
The English file is byte-identical to the previously installed public SVG.

Use the original localized badge when installed. If that locale has not been
published/configured, use the verified English original with localized
surrounding copy and accessible labels. Do not draw replacement badges, change
corner radii or distort their aspect ratios. Shared height is 48 px and minimum
clear space is 8 px; `wallet/presentation.js` records proportional widths.

Publish the exact bytes as canonical public image Worker/R2 objects at
`assets/apple-wallet/v1/<locale>.svg` before configuring the integration's
`badge_urls.apple` locale keys and deploying referencing email/web code. Never
overwrite immutable public artwork with different bytes at the same URL.
